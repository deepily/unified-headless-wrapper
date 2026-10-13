#!/usr/bin/env python3
"""
lupin_headless.py -- one wrapper, three headless agent CLIs: Claude Code, Jetski, AGY.

Scope: a single persona, one warm engine process per conversation, barge-in aware. POSIX only.
Every protocol fact encoded below was captured empirically on 2026-10-12 (see the design doc),
except the Claude Code control_request interrupt path, which is marked UNVERIFIED.

    python3 lupin_headless.py --engine agy --persona alpha
    > list the files here          (type while it talks = barge-in)
    > /quit
"""
import argparse, asyncio, json, os, re, signal, sys, tempfile
from dataclasses import dataclass, field
from pathlib import Path

PIPE = asyncio.subprocess.PIPE
LINE_LIMIT = 2 ** 24      # tool-output frames blow past asyncio's 64 KiB default line limit


# ---------------------------------------------------------------- normalized event model
@dataclass
class Ev:
    kind: str                       # init | text | tool | tool_done | usage | result
    text: str = ""                  # text delta, tool name, or final response / error
    session: str | None = None      # engine session / conversation id, when the frame carries one
    status: str | None = None       # result only: ok | error | interrupted
    raw: dict = field(default_factory=dict)   # usage dict, tool frame, or structured_output


# ---------------------------------------------------------------- engine adapters
class ClaudeCode:
    """Claude Code: -p + stream-json in/out. Interrupt = control_request; the process survives."""
    interrupt_mode = "control"
    system_prompt_flag = True       # --append-system-prompt; per process, NOT persisted -> pass on every spawn

    def __init__(self, cmd=("claude",), extra=()):
        self.cmd, self.extra = list(cmd), list(extra)

    def argv(self, sid, sys_prompt, skip_perms):
        a = [*self.cmd, "-p", "--input-format", "stream-json", "--output-format", "stream-json",
             "--verbose", "--include-partial-messages", *self.extra]
        if skip_perms: a.append("--dangerously-skip-permissions")
        if sid:        a += ["--resume", sid]
        if sys_prompt: a += ["--append-system-prompt", sys_prompt]
        return a

    def user(self, text):
        return {"type": "user", "message": {"role": "user", "content": text}}

    def interrupt(self, rid):       # UNVERIFIED in this study: capture it before relying on it
        return {"type": "control_request", "request_id": rid, "request": {"subtype": "interrupt"}}

    def parse(self, e):
        t = e.get("type")
        if t == "system" and e.get("subtype") == "init":
            yield Ev("init", session=e.get("session_id"), raw=e)
        elif t == "stream_event":
            d = e.get("event", {}).get("delta", {})
            if d.get("type") == "text_delta":
                yield Ev("text", d.get("text", ""), raw=e)
        elif t == "assistant":
            for b in e.get("message", {}).get("content", []):
                if b.get("type") == "tool_use":
                    yield Ev("tool", b.get("name", ""), raw=b)
        elif t == "user":
            c = e.get("message", {}).get("content")
            for b in c if isinstance(c, list) else []:
                if b.get("type") == "tool_result":
                    yield Ev("tool_done", b.get("tool_use_id", ""), raw=b)
        elif t == "result":
            if e.get("usage"):
                yield Ev("usage", raw=e["usage"])                 # per turn
            yield Ev("result", e.get("result") or "", e.get("session_id"),
                     "error" if e.get("is_error") else "ok", e.get("structured_output") or {})


class JetskiFamily:
    """Jetski and AGY: one engine, one schema. Interrupt = SIGINT; the process exits after its result frame."""
    interrupt_mode = "signal"       # control_request: "not supported yet" (AGY, 2026-10-12)
    system_prompt_flag = False      # none found; prefixed to the conversation's first user message

    def __init__(self, cmd=("jetski",), extra=()):
        self.cmd, self.extra = list(cmd), list(extra)

    def argv(self, sid, sys_prompt, skip_perms):
        a = [*self.cmd, "--input-format", "stream-json", "--output-format", "stream-json", *self.extra]
        if skip_perms: a.append("--dangerously-skip-permissions")
        if sid:        a += ["--conversation", sid]
        return a

    def user(self, text):
        return {"event": "user", "message": {"role": "user", "content": text}}

    def interrupt(self, rid):
        return None

    def parse(self, e):
        k = e.get("event")
        if k == "init":
            yield Ev("init", session=e.get("conversation_id"), raw=e)
        elif k == "step_update":
            u = e.get("step_update", {})
            if u.get("text_delta"):                            # incl. the tail on the DONE frame
                yield Ev("text", u["text_delta"], raw=e)
            if u.get("step_type") == "tool":                   # ACTIVE = pre (observe only), DONE = post
                yield Ev("tool" if u.get("state") == "ACTIVE" else "tool_done", u.get("tool_name", ""), raw=u)
            if u.get("state") == "DONE" and "usage" in u:      # per model call; result.usage is cumulative
                yield Ev("usage", raw=u["usage"])
        elif k == "result":
            r = e.get("result", {})
            st = ("ok" if r.get("status") == "SUCCESS"
                  else "interrupted" if r.get("error") == "interrupted" else "error")
            yield Ev("result", r.get("response") or r.get("error", ""),
                     r.get("conversation_id") or None,         # "" on early errors: never overwrite a known id
                     st, r.get("structured_output") or {})


ENGINES = {
    "claude": lambda: ClaudeCode(),
    "jetski": lambda: JetskiFamily(("jetski",)),
    "agy":    lambda: JetskiFamily(("agy",), ("--print-timeout", "0")),   # AGY defaults to a 5 min cap
}


# ---------------------------------------------------------------- session: one warm process per conversation
def _killpg(p, sig):
    try: os.killpg(p.pid, sig)                # start_new_session=True -> pgid == pid
    except ProcessLookupError: pass


class Session:
    """Lazily (re)spawned engine process. Turns are serialized; interrupt() is safe from another task."""

    def __init__(self, engine, sid=None, sys_prompt=None, cwd=None, skip_perms=False):
        self.e, self.sid, self.sys, self.cwd, self.skip = engine, sid, sys_prompt, cwd, skip_perms
        self.p, self._err, self._lock = None, None, asyncio.Lock()
        self.busy = self._interrupting = self._dying = False
        self._rid = 0

    async def _spawn(self):
        self.p = await asyncio.create_subprocess_exec(
            *self.e.argv(self.sid, self.sys, self.skip), cwd=self.cwd,
            stdin=PIPE, stdout=PIPE, stderr=PIPE, start_new_session=True, limit=LINE_LIMIT,
            env={**os.environ, "NO_COLOR": "1"})
        self._err = asyncio.create_task(self.p.stderr.read())        # drain, or risk a pipe deadlock

    async def _reap(self, grace=10.0):
        p, self.p, self._dying = self.p, None, False
        if p and p.returncode is None:
            try: await asyncio.wait_for(p.wait(), grace)
            except asyncio.TimeoutError:
                _killpg(p, signal.SIGKILL); await p.wait()

    async def _send(self, obj):
        try:
            self.p.stdin.write((json.dumps(obj) + "\n").encode())
            await self.p.stdin.drain()
        except (BrokenPipeError, ConnectionResetError):
            pass                                                     # surfaces as EOF below

    async def turn(self, text):
        """Async generator of Ev for one user turn. Always ends with exactly one Ev('result')."""
        async with self._lock:
            if self.p and (self._dying or self.p.returncode is not None):
                await self._reap()                                   # one writer per conversation
            if not self.p:
                await self._spawn()
            if self.sys and not self.e.system_prompt_flag and not self.sid:
                text = f"{self.sys}\n\n{text}"                       # persists in history from turn 1
            self.busy, self._interrupting = True, False
            try:
                await self._send(self.e.user(text))
                async for line in self.p.stdout:
                    try: frame = json.loads(line)
                    except json.JSONDecodeError: continue
                    for ev in self.e.parse(frame):
                        if ev.session: self.sid = ev.session
                        if ev.kind == "result":
                            if self._interrupting and ev.status != "ok":
                                ev.status = "interrupted"
                            yield ev
                            return
                        yield ev
                # stdout EOF without a result frame: e.g. a permission auto-deny (empty stdout, rc=0)
                await self._reap(grace=2.0)
                tail = (await self._err).decode(errors="replace").strip()[-500:] if self._err else ""
                yield Ev("result", tail, self.sid, "interrupted" if self._interrupting else "error")
            finally:
                self.busy = False

    async def interrupt(self):
        """Barge-in. Control message where supported; else SIGINT, and the next turn respawns on self.sid."""
        if not (self.busy and self.p and self.p.returncode is None):
            return
        self._interrupting = True
        if self.e.interrupt_mode == "control":
            self._rid += 1
            await self._send(self.e.interrupt(f"int-{self._rid}"))
        else:
            self._dying = True
            _killpg(self.p, signal.SIGINT)

    async def close(self):
        if self.p and self.p.returncode is None:
            try: self.p.stdin.close()                                # stdin EOF ends a stream-json engine
            except Exception: pass
        await self._reap(grace=5.0)


# ---------------------------------------------------------------- persona -> session id
class PersonaStore:
    """persona_id -> {engine: session_id}, one JSON file per persona, atomic replace."""

    def __init__(self, root="~/.lupin/personas"):
        self.root = Path(root).expanduser()
        self.root.mkdir(parents=True, exist_ok=True)

    def _path(self, pid): return self.root / f"{pid}.json"

    def load(self, pid):
        try: return json.loads(self._path(pid).read_text())
        except (FileNotFoundError, json.JSONDecodeError): return {}

    def save(self, pid, engine, sid):
        d = self.load(pid)
        if d.get(engine) == sid: return
        d[engine] = sid
        fd, tmp = tempfile.mkstemp(dir=self.root, suffix=".tmp")
        with os.fdopen(fd, "w") as f: json.dump(d, f, indent=1)
        os.replace(tmp, self._path(pid))

    def forget(self, pid, engine):
        d = self.load(pid)
        if d.pop(engine, None) is not None:
            self._path(pid).write_text(json.dumps(d, indent=1))


# ---------------------------------------------------------------- voice-side helpers
_MD = [(re.compile(r"\[([^\]]+)\]\([^)]*\)"), r"\1"),       # [text](url) -> text
       (re.compile(r"\$\\(?:rightarrow|to)\$"), " then "),     # LaTeX arrows seen in captures
       (re.compile(r"\$([^$]*)\$"), r"\1"),
       (re.compile(r"[*_`#>|]+"), "")]


class Speaker:
    """Accumulates deltas and emits whole sentences without markdown. Swap say() for your TTS client."""
    _end = re.compile(r"(?<=[.!?:])\s+|\n+")

    def __init__(self, say=lambda s: print(f"  say> {s}", flush=True)):
        self.say, self.buf, self.muted = say, "", False

    def reset(self):  self.buf, self.muted = "", False
    def cancel(self): self.buf, self.muted = "", True          # barge-in: drop everything not yet spoken

    def feed(self, delta):
        if self.muted: return
        self.buf += delta
        *done, self.buf = self._end.split(self.buf)
        for s in done: self._emit(s)

    def flush(self):
        if not self.muted: self._emit(self.buf)
        self.buf = ""

    def _emit(self, s):
        for rx, rep in _MD: s = rx.sub(rep, s)
        s = " ".join(s.split())
        if s: self.say(s)


def awaiting_user(text):
    """Placeholder for a local intent classifier: did the agent end its turn by asking something?"""
    return text.rstrip().rstrip("*_`").endswith("?")


def log(msg): print(f"[lupin] {msg}", file=sys.stderr, flush=True)


# ---------------------------------------------------------------- the single-persona loop
async def run_persona(persona_id, engine_name, inbox, *, engine=None, sys_prompt=None, cwd=None,
                      skip_perms=False, store=None, say=None):
    """inbox yields utterances (ASR transcripts, typed lines); None ends the loop.
    A new utterance that arrives mid-turn is a barge-in: silence, interrupt, then start the new turn."""
    store = store or PersonaStore()
    sess = Session(engine or ENGINES[engine_name](), sid=store.load(persona_id).get(engine_name),
                   sys_prompt=sys_prompt, cwd=cwd, skip_perms=skip_perms)
    speaker = Speaker(say) if say else Speaker()
    log(f"persona={persona_id} engine={engine_name} resume={sess.sid or 'new'}")

    async def one_turn(text):
        speaker.reset()
        usage = {}
        async for ev in sess.turn(text):
            if ev.kind == "init":
                log(f"session {ev.session}")
            elif ev.kind == "text":
                speaker.feed(ev.text)
            elif ev.kind == "tool":
                log(f"tool> {ev.text}")
            elif ev.kind == "usage":
                for k, v in ev.raw.items():
                    if isinstance(v, (int, float)): usage[k] = usage.get(k, 0) + v
            elif ev.kind == "result":
                speaker.flush()                                       # no-op when muted by a barge-in
                if sess.sid: store.save(persona_id, engine_name, sess.sid)
                ask = ev.status == "ok" and awaiting_user(ev.text)
                log(f"turn {ev.status} in={usage.get('input_tokens', 0)} out={usage.get('output_tokens', 0)}"
                    + (" awaiting-user" if ask else "")
                    + (f" | {ev.text[:200]}" if ev.status == "error" else ""))

    current = None
    try:
        while (text := await inbox.get()) is not None:
            if current and not current.done():
                speaker.cancel()                                      # 1. silence immediately
                await sess.interrupt()                                # 2. stop the engine
                await current                                         # 3. its result frame closes the turn
            current = asyncio.create_task(one_turn(text))
        if current: await current
    finally:
        if current and not current.done():
            await sess.interrupt()
            await asyncio.gather(current, return_exceptions=True)
        await sess.close()


async def stdin_inbox(q):
    while True:
        line = await asyncio.to_thread(sys.stdin.readline)
        if not line or line.strip() in ("/quit", "/exit"):
            await q.put(None); return
        if line.strip(): await q.put(line.strip())


VOICE_RULES = ("You are speaking aloud to one person. Answer in short plain sentences. "
               "No markdown, links, tables or code blocks unless explicitly asked.")


def main():
    ap = argparse.ArgumentParser(description="single-persona headless loop for claude / jetski / agy")
    ap.add_argument("--engine", choices=sorted(ENGINES), default="agy")
    ap.add_argument("--persona", default="default")
    ap.add_argument("--system", default=VOICE_RULES)
    ap.add_argument("--cwd")
    ap.add_argument("--skip-permissions", action="store_true",
                    help="auto-approve tools; otherwise the Jetski family needs allow-rules in settings.json")
    ap.add_argument("--new", action="store_true", help="forget this persona's stored session for this engine")
    a = ap.parse_args()

    async def go():
        store, q = PersonaStore(), asyncio.Queue()
        if a.new: store.forget(a.persona, a.engine)
        reader = asyncio.create_task(stdin_inbox(q))
        try:
            await run_persona(a.persona, a.engine, q, sys_prompt=a.system, cwd=a.cwd,
                              skip_perms=a.skip_permissions, store=store)
        finally:
            reader.cancel()

    asyncio.run(go())


if __name__ == "__main__":
    main()
