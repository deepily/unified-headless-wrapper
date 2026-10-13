#!/usr/bin/env python3
"""Exercises Session and run_persona against fake_engine.py for both protocol families."""
import asyncio, os, sys, tempfile
from pathlib import Path
from lupin_headless import ClaudeCode, JetskiFamily, Session, PersonaStore, run_persona

HERE = Path(__file__).parent
FAKE = [sys.executable, str(HERE / "fake_engine.py")]
os.environ["FAKE_STORE"] = tempfile.mkdtemp()


def engine(flavor):
    return ClaudeCode((*FAKE, "claude")) if flavor == "claude" else JetskiFamily((*FAKE, flavor))


async def collect(sess, text, interrupt_after=None):
    evs = []
    async def consume():
        async for ev in sess.turn(text): evs.append(ev)
    t = asyncio.create_task(consume())
    if interrupt_after:
        await asyncio.sleep(interrupt_after); await sess.interrupt()
    await t
    return evs


async def session_scenario(flavor):
    s = Session(engine(flavor), sys_prompt="SYSPROMPT")
    r1 = await collect(s, "hello")
    assert r1[-1].kind == "result" and r1[-1].status == "ok", r1[-1]
    sid, pid1 = s.sid, s.p.pid
    assert sid and [e.kind for e in r1].count("result") == 1

    r2 = await collect(s, "count please", interrupt_after=0.3)
    spoken = "".join(e.text for e in r2 if e.kind == "text")
    assert r2[-1].status == "interrupted" and "40." not in spoken, (r2[-1], spoken[-40:])

    r3 = await collect(s, "tool then recall")            # 100 KB tool frame + history check
    assert r3[-1].status == "ok" and s.sid == sid, r3[-1]
    assert any(e.kind == "tool" for e in r3) and any(e.kind == "tool_done" for e in r3)
    assert "said 2 things" in r3[-1].text, r3[-1].text
    if flavor == "jetski":
        assert s.p.pid != pid1, "jetski must respawn after SIGINT"
        assert "SYSPROMPT" in r3[-1].text, "system prompt prefixed to turn 1"
    else:
        assert s.p.pid == pid1, "claude process survives a control interrupt"
    await s.close()
    assert s.p is None

    s2 = Session(engine(flavor), sid=sid)                # cold resume from a stored id
    r4 = await collect(s2, "recall")
    assert "said 3 things" in r4[-1].text and s2.sid == sid, r4[-1].text
    await s2.close()
    print(f"  {flavor}: session scenario OK (sid={sid[:8]})")


async def deny_scenario():
    s = Session(engine("deny"))
    r = await collect(s, "list files")
    assert r[-1].status == "error" and "permission" in r[-1].text, r[-1]
    await s.close()
    print("  deny: EOF without result -> error with stderr tail OK")


async def loop_scenario(flavor):
    store = PersonaStore(tempfile.mkdtemp())
    said, q = [], asyncio.Queue()
    task = asyncio.create_task(run_persona("alpha", flavor, q, engine=engine(flavor), sys_prompt="SYS",
                                           store=store, say=said.append))
    await q.put("hello");        await asyncio.sleep(0.6)
    await q.put("count please"); await asyncio.sleep(0.3)
    await q.put("recall")                                # barge-in mid-count
    await asyncio.sleep(0.8); await q.put(None)
    await task
    sid = store.load("alpha").get(flavor)
    assert sid, "sid persisted"
    assert "Hello there." in said and "This is fake speech then done." in said, said
    assert not any("40." in s for s in said), "speech after barge-in was muted"
    assert any("said 2 things" in s for s in said), said
    print(f"  {flavor}: loop + barge-in + persona store OK; spoke {len(said)} sentences")


async def main():
    for f in ("jetski", "claude"):
        await session_scenario(f)
    await deny_scenario()
    for f in ("jetski", "claude"):
        await loop_scenario(f)
    print("all passed")

asyncio.run(main())
