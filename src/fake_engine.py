#!/usr/bin/env python3
"""Mock engine reproducing the stream-json behavior captured on 2026-10-12.
usage: fake_engine.py jetski|claude|deny [--conversation ID | --resume ID] [...ignored flags]"""
import asyncio, json, os, signal, sys, uuid
from pathlib import Path

flavor, args = sys.argv[1], sys.argv[2:]
opt = lambda n: args[args.index(n) + 1] if n in args else None
store = Path(os.environ.get("FAKE_STORE", "/tmp/fake_store")); store.mkdir(parents=True, exist_ok=True)
sid = opt("--conversation") or opt("--resume") or str(uuid.uuid4())
hist_path = store / f"{sid}.json"
hist = json.loads(hist_path.read_text()) if hist_path.exists() else []
active = False


def out(o): sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()


def reply_words(text):
    if "count" in text:  return [f"{i}." for i in range(1, 41)]
    if "recall" in text: return ["You", "said", str(len(hist) - 1), "things", "before.", "First:", hist[0] + "."]
    if "ask" in text:    return ["Shall", "I", "continue?"]
    return ["Hello", "there.", "This", "is", "**fake**", "[speech](http://x)", "$\\rightarrow$", "done."]


async def turn(text, intr):
    global active
    active = True
    words, done, out_toks = reply_words(text), True, 0
    if flavor == "claude":
        out({"type": "system", "subtype": "init", "session_id": sid})
    if "tool" in text:
        if flavor == "jetski":
            out({"event": "step_update", "step_update": {"conversation_id": sid, "step_index": 1, "state": "ACTIVE", "step_type": "tool", "tool_name": "run_command"}})
            out({"event": "step_update", "step_update": {"conversation_id": sid, "step_index": 1, "state": "DONE", "step_type": "tool", "tool_name": "run_command", "tool_info": {"output": "x" * 100_000}}})
        else:
            out({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {}}]}})
            out({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "t1", "content": "x" * 100_000}]}})
    for w in words:
        if intr.is_set(): done = False; break
        out_toks += 1
        if flavor == "jetski":
            out({"event": "step_update", "step_update": {"conversation_id": sid, "step_index": 2, "state": "ACTIVE", "step_type": "agent_response", "text_delta": w + " "}})
        else:
            out({"type": "stream_event", "event": {"type": "content_block_delta", "delta": {"type": "text_delta", "text": w + " "}}})
        await asyncio.sleep(0.03)
    final = " ".join(words) if done else ""
    if flavor == "jetski":
        out({"event": "step_update", "step_update": {"conversation_id": sid, "step_index": 2, "state": "DONE", "step_type": "agent_response", "usage": {"input_tokens": 1000, "output_tokens": out_toks}}})
        out({"event": "result", "result": {"conversation_id": sid, "status": "SUCCESS" if done else "ERROR", "response": final, **({} if done else {"error": "interrupted"}), "usage": {"input_tokens": 999999}}})
    else:
        out({"type": "result", "subtype": "success" if done else "error_during_execution", "is_error": not done, "result": final, "session_id": sid, "usage": {"input_tokens": 1000, "output_tokens": out_toks}})
    active = False
    return done


async def main():
    if flavor == "deny":
        sys.stderr.write('jetski: no output produced - a tool required the "command" permission\n'); return 0
    loop, intr, q = asyncio.get_running_loop(), asyncio.Event(), asyncio.Queue()
    reader = asyncio.StreamReader()
    await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    if flavor == "jetski":
        out({"event": "init", "conversation_id": sid, "init": {"tools": ["run_command"]}})
        loop.add_signal_handler(signal.SIGINT, lambda: intr.set() if active else os._exit(1))

    async def read():
        while line := await reader.readline():
            m = json.loads(line)
            if m.get("type") == "control_request":
                intr.set(); out({"type": "control_response", "response": {"subtype": "success", "request_id": m["request_id"]}})
            else:
                await q.put(m)
        await q.put(None)
    asyncio.create_task(read())

    while (m := await q.get()) is not None:
        text = m["message"]["content"]
        hist.append(text); hist_path.write_text(json.dumps(hist))       # user input persists on accept
        intr.clear()
        if not await turn(text, intr) and flavor == "jetski":
            sys.stderr.write("error: interrupted\n"); return 1           # SIGINT ends the whole process
    return 0

sys.exit(asyncio.run(main()))
