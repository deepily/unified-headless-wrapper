#!/usr/bin/env python3
"""
build_svgs.py -- the three Lupin kernel explainer diagrams, written as theme-aware SVG.

Ensures:
    - kernel-overview.svg, kernel-owns-and-brokers.svg, kernel-harnesses.svg beside this file
    - every color comes from a CSS variable with a light fallback, so the files render standalone
      and follow the page's theme when inlined
"""
from pathlib import Path

HERE  = Path( __file__ ).parent
STYLE = ( HERE / "style.inc" ).read_text()


def svg( name, width, height, body, marker ):
    style = STYLE.replace( 'id="ah"', f'id="{marker}"' )
    text = ( f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" '
             f'role="img" aria-labelledby="{marker}-title">\n<title id="{marker}-title">{name}</title>\n{style}\n'
             f'  <rect class="bg" width="{width}" height="{height}"/>\n{body.replace( "url(#ah)", f"url(#{marker})" )}\n</svg>\n' )
    return text


def box( x, y, w, h, cls, rx=10 ):
    return f'  <rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}"/>\n'


def text( x, y, s, size=13, cls="t", anchor="start", weight="" ):
    w = ' h' if weight == "bold" else ''
    return f'  <text class="{cls}{w}" x="{x}" y="{y}" font-size="{size}" text-anchor="{anchor}">{s}</text>\n'


def line( x1, y1, x2, y2, both=False, dashed=False ):
    start = ' marker-start="url(#ah)"' if both else ''
    cls = "ln dash" if dashed else "ln"
    return f'  <line class="{cls}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" marker-end="url(#ah)"{start}/>\n'


def badge( x, y, n ):
    return f'  <circle class="badge" cx="{x}" cy="{y}" r="10"/>\n  <text class="bt" x="{x}" y="{y + 4}" font-size="12" text-anchor="middle">{n}</text>\n'


# ------------------------------------------------------------------ 1. overview: kernel + four interfaces
b = ""
b += text( 550, 34, "The Lupin kernel and its four interfaces", 20, anchor="middle", weight="bold" )
# top row: operators, you
b += box( 440, 58, 260, 54, "person" ) + text( 570, 81, "Operators and scripts", 14, anchor="middle", weight="bold" ) + text( 570, 100, "lupin kernel status · persona spawn", 11, "t m mono", "middle" )
b += box( 830, 58, 250, 54, "person" ) + text( 955, 81, "You", 14, anchor="middle", weight="bold" ) + text( 955, 100, "voice · web · phone · console", 11, "t m", "middle" )
b += line( 570, 112, 570, 156 ) + badge( 585, 134, 4 ) + text( 600, 138, "lupin CLI", 12, weight="bold" )
b += line( 955, 112, 955, 156, both=True ) + text( 966, 138, "your voice and text", 11, "t m" )
# agents
b += text( 20, 160, "AGENTS · one harness each", 11, "t m", weight="bold" )
for i, ( name, sub ) in enumerate( [ ( "Claude Code", "Claude models" ), ( "AGY", "Gemini · Opus · Fable" ), ( "Jetski", "Gemini · Opus · Fable" ) ] ):
    y = 172 + i * 130
    b += box( 20, y, 230, 100, "agent" ) + text( 135, y + 40, name, 16, anchor="middle", weight="bold" ) + text( 135, y + 62, sub, 12, "t m", "middle" )
    b += f'  <line class="ln" x1="250" y1="{y + 50}" x2="282" y2="{y + 50}"/>\n'
b += '  <line class="ln" x1="282" y1="222" x2="282" y2="606"/>\n'
# agent -> cosa-voice MCP -> Lupin REST (direct; gated by the kernel through the hook shim)
b += line( 282, 606, 252, 606 )
b += box( 20, 568, 230, 76, "agent" ) + badge( 42, 592, 1 ) + text( 58, 597, "cosa-voice MCP", 14, weight="bold" ) + text( 34, 618, "one per agent, started by the kernel", 11, "t m" ) + text( 34, 634, "the tools the model calls", 11, "t m" )
b += '  <polyline class="ln" points="135,644 135,684 1092,684 1092,316 1082,316" marker-end="url(#ah)"/>\n'
b += text( 610, 676, "Lupin REST, unchanged endpoints · authenticated by API key · every call first allowed or denied by ②", 11.5, "t m", "middle" )
b += line( 282, 352, 418, 352 ) + badge( 296, 334, 2 ) + text( 311, 338, "Hook shim", 12, weight="bold" ) + text( 296, 370, "may I run this tool?", 11, "t m" )
b += line( 282, 442, 418, 442, both=True, dashed=True ) + text( 296, 430, "engine stream", 12, weight="bold" ) + text( 296, 460, "turns in, replies out", 11, "t m" )
# kernel
b += box( 420, 158, 300, 446, "kernel", 14 )
b += text( 570, 186, "Lupin kernel", 18, anchor="middle", weight="bold" ) + text( 570, 205, "owns the resources · makes every allow/deny call", 11, "t m", "middle" )
owned = [ "Agent processes", "Identity and roles", "Conversations", "Workspaces, config", "Tool gate", "Inbox router",
          "Narration", "Asks, escalation", "Fleet health", "Session logs" ]
for i, label in enumerate( owned ):
    x = 436 + ( i % 2 ) * 138; y = 220 + ( i // 2 ) * 44
    b += box( x, y, 130, 34, "chip", 7 ) + text( x + 65, y + 22, label, 12, anchor="middle" )
b += box( 436, 448, 268, 66, "store", 8 ) + text( 570, 472, "Kernel's own storage (host disk)", 12, anchor="middle", weight="bold" ) + text( 570, 492, "registry · session logs · workspaces", 11, "t m", "middle" )
b += text( 570, 548, "one per host · local API on a Unix socket", 11, "t m", "middle" ) + text( 570, 566, "(serves ② ④; not a fifth interface)", 11, "t m", "middle" )
# kernel <-> lupin
b += line( 722, 246, 828, 246, both=True ) + badge( 736, 228, 3 ) + text( 751, 232, "Notifications", 12, weight="bold" ) + text( 736, 264, "socket per agent", 11, "t m" )
# lupin app
b += box( 830, 158, 250, 316, "lupin", 14 )
b += text( 955, 186, "Lupin application", 17, anchor="middle", weight="bold" ) + text( 955, 205, "FastAPI · port 7999 · system of record", 11, "t m", "middle" )
for i, label in enumerate( [ "Notifications API + WebSocket", "Tasks", "DMs and commons", "Asks (tickets)", "Preference learner", "Files and documents" ] ):
    y = 218 + i * 40
    b += box( 846, y, 218, 32, "lchip", 7 ) + text( 955, y + 21, label, 12, anchor="middle" )
b += line( 955, 474, 955, 506 )
for i, ( name, l1, l2 ) in enumerate( [ ( "PostgreSQL", "records, and vectors", "via pgvector" ), ( "io/ files", "documents, audio,", "video, commons" ) ] ):
    x = 830 + i * 128
    b += box( x, 508, 122, 82, "store", 8 ) + text( x + 61, 532, name, 12.5, anchor="middle", weight="bold" ) + text( x + 61, 553, l1, 10.5, "t m", "middle" ) + text( x + 61, 569, l2, 10.5, "t m", "middle" )
b += text( 550, 720, "① ② ③ ④ are the four interfaces. Agent requests go straight to Lupin through ①; the kernel authorizes each one through ②.", 12, "t m", "middle" )
( HERE / "kernel-overview.svg" ).write_text( svg( "The Lupin kernel and its four interfaces", 1100, 740, b, "ah1" ) )

# ------------------------------------------------------------------ 2. owns vs brokers
b = ""
b += text( 550, 34, "What the kernel owns, and what it brokers", 20, anchor="middle", weight="bold" )
b += box( 360, 56, 380, 52, "agent" ) + text( 550, 79, "Agents: Claude Code · AGY · Jetski", 14, anchor="middle", weight="bold" ) + text( 550, 98, "every tool call is checked by the kernel", 11, "t m", "middle" )
b += line( 550, 108, 550, 136 )
b += box( 200, 138, 700, 58, "kernel", 12 ) + text( 550, 162, "Lupin kernel", 16, anchor="middle", weight="bold" ) + text( 550, 182, "checks role and rules on every call; serves owned resources itself, lets brokered calls through to Lupin", 12, "t m", "middle" )
b += line( 370, 196, 300, 236 ) + line( 730, 196, 810, 236 )
b += box( 20, 238, 520, 300, "kernel", 12 ) + text( 40, 266, "OWNS", 13, weight="bold" ) + text( 92, 266, "the kernel decides and keeps the state", 12, "t m" )
owned = [ ( "Agent processes", "start, stop, interrupt, restart" ), ( "Identity and roles", "who is who, who reports to whom" ),
          ( "Conversations", "which one each agent resumes" ), ( "Workspaces and config", "folders, instructions, skills, tool allowances" ),
          ( "Tool use", "allow or deny every call" ), ( "Message routing", "start, queue, or interrupt" ),
          ( "Fleet capacity and health", "how many run, how healthy, how full" ), ( "Session logs", "a complete record per agent" ) ]
for i, ( name, what ) in enumerate( owned ):
    y = 292 + i * 26
    b += text( 40, y, name, 12.5, weight="bold" ) + text( 232, y, what, 12, "t m" )
b += box( 40, 506, 480, 24, "store", 6 ) + text( 280, 522, "stored on the host: registry · session logs · workspaces", 11, anchor="middle" )
b += box( 560, 238, 520, 300, "lupin", 12 ) + text( 580, 266, "BROKERS", 13, weight="bold" ) + text( 652, 266, "Lupin keeps the record; the kernel authorizes access", 12, "t m" )
brokered = [ ( "Notifications", "narration out, your voice in" ), ( "Tasks", "the only source of owed work" ),
             ( "DMs and commons", "messages between agents" ), ( "Asks", "questions to you, with escalation" ),
             ( "Preference learner", "answers in your stead when you're away" ), ( "Files and documents", "artifacts that need a home" ) ]
for i, ( name, what ) in enumerate( brokered ):
    y = 292 + i * 26
    b += text( 580, y, name, 12.5, weight="bold" ) + text( 752, y, what, 12, "t m" )
for i, ( name, what ) in enumerate( [ ( "PostgreSQL + pgvector", "records and vectors" ), ( "io/ files", "artifacts" ) ] ):
    x = 580 + i * 245
    b += box( x, 456, 235, 74, "store", 8 ) + text( x + 117, 486, name, 13, anchor="middle", weight="bold" ) + text( x + 117, 506, what, 11, "t m", "middle" )
b += text( 550, 568, "Allocation and permission happen in the kernel either way. Brokered data simply lives in Lupin's databases and files.", 12, "t m", "middle" )
( HERE / "kernel-owns-and-brokers.svg" ).write_text( svg( "What the Lupin kernel owns and brokers", 1100, 590, b, "ah2" ) )

# ------------------------------------------------------------------ 3. harnesses
b = ""
b += text( 550, 34, "Three harnesses, one kernel", 20, anchor="middle", weight="bold" )
cols = [ ( "Claude Code", 186 ), ( "AGY", 484 ), ( "Jetski", 782 ) ]
b += box( 186, 52, 290, 26, "chip", 6 ) + text( 331, 70, "Claude adapter · built last", 11.5, anchor="middle" )
b += box( 484, 52, 588, 26, "chip", 6 ) + text( 778, 70, "Jetski-family adapter · one code path for both", 11.5, anchor="middle" )
for name, x in cols:
    b += box( x, 86, 290, 40, "agent", 8 ) + text( x + 145, 112, name, 15, anchor="middle", weight="bold" )
rows = [
    ( "Launch", ( "claude -p, stream-json,", "user hooks isolated" ), ( "agy, stream-json", "" ), ( "jetski, stream-json", "" ) ),
    ( "Instructions", ( "system-prompt flag", "at every launch" ), ( "AGENTS.md in the", "agent's workspace" ), ( "AGENTS.md in the", "agent's workspace" ) ),
    ( "② Tool check", ( "PreToolUse hook,", "passed at launch" ), ( ".agents/hooks.json", "in the workspace" ), ( ".agents/hooks.json", "in the workspace" ) ),
    ( "① Lupin tools", ( "MCP config", "passed at launch" ), ( "~/.gemini/config/", "mcp_config.json" ), ( "~/.gemini/config/", "mcp_config.json" ) ),
    ( "Interrupt", ( "control message;", "process keeps running" ), ( "stop, then restart on", "the same conversation" ), ( "stop, then restart on", "the same conversation" ) ),
    ( "Message mid-turn", ( "joins the current turn", "" ), ( "waits for the next turn", "" ), ( "waits for the next turn", "" ) ),
    ( "Subagents", ( "gated by role", "" ), ( "gated by role; kernel", "can't see inside" ), ( "gated by role; kernel", "sees inside" ) ),
    ( "Long tool calls", ( "not measured yet", "" ), ( "cut at 180 s:", "asks use tickets" ), ( "cut at 180 s:", "asks use tickets" ) ),
]
for r, ( label, *cells ) in enumerate( rows ):
    y = 136 + r * 46
    b += text( 20, y + 26, label, 12.5, weight="bold" )
    for ( name, x ), ( l1, l2 ) in zip( cols, cells ):
        b += box( x, y, 290, 40, "chip", 6 )
        if l2:
            b += text( x + 12, y + 17, l1, 11.5 ) + text( x + 12, y + 32, l2, 11.5, "t m" )
        else:
            b += text( x + 12, y + 25, l1, 11.5 )
for name, x in cols:
    b += line( x + 145, 504, 550 + ( x - 484 ) * 0.5, 546 )
b += box( 240, 548, 620, 58, "kernel", 12 ) + text( 550, 572, "Lupin kernel", 15, anchor="middle", weight="bold" ) + text( 550, 592, "same registry, gate, inbox, narration and fleet view for every harness", 12, "t m", "middle" )
b += text( 550, 632, "The adapters absorb each harness's differences, so every agent looks the same to the kernel and to you.", 12, "t m", "middle" )
( HERE / "kernel-harnesses.svg" ).write_text( svg( "How Claude Code, AGY and Jetski plug into the Lupin kernel", 1100, 650, b, "ah3" ) )

# ------------------------------------------------------------------ 4. FastAPI services and storage
b = ""
b += text( 550, 34, "The FastAPI services, before and after", 20, anchor="middle", weight="bold" )
b += text( 275, 70, "TODAY", 13, anchor="middle", weight="bold" ) + text( 825, 70, "WITH THE KERNEL", 13, anchor="middle", weight="bold" )
b += '  <line class="ln dash" x1="550" y1="56" x2="550" y2="320"/>\n'
# today
b += box( 20, 86, 250, 210, "lupin", 12 ) + text( 145, 112, "Lupin app · :7999", 14, anchor="middle", weight="bold" ) + text( 145, 132, "Docker · 37 routers", 11, "t m", "middle" )
for i, l in enumerate( [ "9 routers agents call", "notifications · tasks · dm", "commons · asks · learner", "files · voice · transcript" ] ):
    b += text( 40, 162 + i * 22, l, 12, "t" if i == 0 else "t m", weight="bold" if i == 0 else "" )
b += text( 40, 270, "+ 28 routers for the UI and admin", 11, "t m" )
b += box( 290, 86, 240, 100, "chip", 12 ) + text( 410, 112, "Arbiter · :8001", 14, anchor="middle", weight="bold" ) + text( 410, 134, "separate FastAPI service", 11, "t m", "middle" ) + text( 410, 152, "fleet capacity and health", 11, "t m", "middle" )
b += box( 290, 200, 240, 96, "agent", 12 ) + text( 410, 226, "AH4L harness", 14, anchor="middle", weight="bold" ) + text( 410, 248, "Claude Code only", 11, "t m", "middle" ) + text( 410, 266, "calls both services directly", 11, "t m", "middle" )
# after
b += box( 570, 86, 250, 210, "lupin", 12 ) + text( 695, 112, "Lupin app · :7999", 14, anchor="middle", weight="bold" ) + text( 695, 132, "unchanged · system of record", 11, "t m", "middle" )
for i, l in enumerate( [ "stays: notifications, tasks,", "DMs, commons, asks, learner,", "files, voice, speakerphone", "replaced: transcript and queue", "routers (to confirm)" ] ):
    b += text( 590, 162 + i * 22, l, 12, "t m" )
b += box( 840, 86, 240, 210, "kernel", 12 ) + text( 960, 112, "Lupin kernel", 14, anchor="middle", weight="bold" ) + text( 960, 132, "FastAPI on a Unix socket", 11, "t m", "middle" )
for i, l in enumerate( [ "/gate (tool check)", "/personas (CLI)", "/personas/{id}/messages", "/health (old arbiter)" ] ):
    b += text( 860, 162 + i * 22, l, 12, "t mono" )
b += text( 860, 268, "the arbiter folds in here", 11, "t m" )
b += line( 838, 190, 822, 190 ) + text( 830, 312, "agents reach Lupin only through cosa-voice, gated by the kernel", 11, "t m", "middle" )
# storage
b += text( 550, 360, "WHERE THE DATA LIVES", 13, anchor="middle", weight="bold" )
stores = [ ( "PostgreSQL + pgvector", "tasks, DMs, notifications, learner;", "768-dim vectors (pgvector, v0.2.0)" ),
           ( "io/ file tree", "documents, audio, video, PDFs,", "commons topics (io/commons/)" ), ( "Kernel host disk", "registry JSON, JSONL session", "logs, agent workspaces" ) ]
for i, ( n, l1, l2 ) in enumerate( stores ):
    x = 20 + i * 358
    b += box( x, 376, 342, 86, "store", 10 ) + text( x + 171, 402, n, 13, anchor="middle", weight="bold" ) + text( x + 171, 424, l1, 11, "t m", "middle" ) + text( x + 171, 442, l2, 11, "t m", "middle" )
b += text( 370, 488, "owned by the Lupin app (brokered by the kernel)", 11, "t m", "middle" ) + text( 907, 488, "owned by the kernel", 11, "t m", "middle" )
( HERE / "kernel-fastapi-and-storage.svg" ).write_text( svg( "The FastAPI services and storage around the Lupin kernel", 1100, 510, b, "ah4" ) )
print( "written" )
