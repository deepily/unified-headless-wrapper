"""Build the UHW phase chart: who drives each build phase, and where.

Framework Section 15 stays the authority. The chart is kept current by
check_phase_chart.py beside this file (Rick, 2026-11-18, row 96), which fails
when the text the chart was drawn from has changed: redraw here, then set
SOURCES_DIGEST to the digest that check prints with --digest.
Run: python3 build_phase_chart.py build-phases-and-drivers.html build-phases-and-drivers.svg
The .svg is the chart alone, standalone: white background, fixed fonts.
"""
import html
import sys

AS_OF = "2026-11-18, after row 96"
SOURCES_DIGEST = "3990f3019395739a"  # check_phase_chart.py --digest, taken when the chart was last drawn
AMBER = "#d97706"
LANE_WIDTH = 220
LANE_X = {"plan": 16, "rick": 248, "builder": 480, "agy": 712, "dev": 944}
LANES = {
    "plan": ("Planning (Claude models)", "writes src/rnd/ only"),
    "rick": ("Rick, by hand", "terminal, SSH, laptop console"),
    "builder": ("Claude Code under AH4L", "test VM · the builder's clone"),
    "agy": ("AGY persona under the kernel", "test VM · writes lupin"),
    "dev": ("Kernel-run personas", "development server"),
}
HEIGHT = 1720

parts = []
nodes = {}


def text(x, y, s, size=11, weight=None, anchor="start", fill="currentColor", opacity=None):
    w = f' font-weight="{weight}"' if weight else ""
    o = f' fill-opacity="{opacity}"' if opacity else ""
    parts.append(f'<text x="{x}" y="{y}" font-size="{size}"{w} text-anchor="{anchor}" '
                 f'fill="{fill}"{o}>{html.escape(s)}</text>')


def badge(cx, cy, label):
    parts.append(f'<circle cx="{cx}" cy="{cy}" r="9" fill="{AMBER}"/>')
    text(cx, cy + 4, str(label), 11, "700", "middle", "#ffffff")


def box(key, lane, y, title, lines, kind="phase", tag=None, questions=()):
    """kind: phase | done | open | gate (gates and clocks get thick borders)."""
    x = LANE_X[lane]
    h = 32 + 14 * len(lines)
    stroke = "2.4" if kind == "gate" else "1.2"
    dash = ' stroke-dasharray="5 3"' if kind == "open" else ""
    radius = 16 if kind == "gate" else 6
    parts.append(f'<g opacity="{0.45 if kind == "done" else 1}">')
    parts.append(f'<rect x="{x}" y="{y}" width="{LANE_WIDTH}" height="{h}" rx="{radius}" '
                 f'fill="currentColor" fill-opacity="0.05" stroke="currentColor" '
                 f'stroke-width="{stroke}"{dash}/>')
    text(x + 10, y + 18, title, 12.5, "600")
    for i, line in enumerate(lines):
        text(x + 10, y + 36 + 14 * i, line, 11, opacity="0.85")
    if tag:
        text(x + LANE_WIDTH - 10, y + 18, tag, 10, "600", "end", opacity="0.6")
    parts.append("</g>")
    for i, q in enumerate(questions):
        badge(x + LANE_WIDTH, y + 16 + 22 * i, q)
    nodes[key] = (x, y, LANE_WIDTH, h)


def arrow(a, b, label=None, color="currentColor", marker="arrow", dashed=False):
    ax, ay, aw, ah = nodes[a]
    bx, by, bw, _ = nodes[b]
    x1, y1, x2, y2 = ax + aw / 2, ay + ah, bx + bw / 2, by
    dash = ' stroke-dasharray="4 3"' if dashed else ""
    if abs(x1 - x2) < 1:
        path, lx, ly, anchor = f"M{x1},{y1} L{x2},{y2 - 2}", x1 + 8, (y1 + y2) / 2 + 4, "start"
    else:
        mid = (y1 + y2) / 2
        path = f"M{x1},{y1} L{x1},{mid} L{x2},{mid} L{x2},{y2 - 2}"
        lx, ly, anchor = (x1 + x2) / 2, mid - 5, "middle"
    parts.append(f'<path d="{path}" fill="none" stroke="{color}" stroke-width="1.3"{dash} '
                 f'marker-end="url(#{marker})"/>')
    if label:
        text(lx, ly, label, 10.5, anchor=anchor, opacity="0.75")


def planning_note(y, h, title, lines):
    x = LANE_X["plan"]
    parts.append(f'<rect x="{x}" y="{y}" width="{LANE_WIDTH}" height="{h}" rx="6" '
                 f'fill="currentColor" fill-opacity="0.05" stroke="currentColor" '
                 f'stroke-width="1" stroke-dasharray="2 3"/>')
    text(x + 10, y + 18, title, 12.5, "600")
    for i, line in enumerate(lines):
        text(x + 10, y + 36 + 14 * i, line, 11, opacity="0.85")


# Lanes
for i, (lane, (head, sub)) in enumerate(LANES.items()):
    x = LANE_X[lane]
    parts.append(f'<rect x="{x - 6}" y="4" width="{LANE_WIDTH + 12}" height="{HEIGHT - 8}" rx="8" '
                 f'fill="currentColor" fill-opacity="{0.035 if i % 2 == 0 else 0.015}"/>')
    text(x + LANE_WIDTH / 2, 26, head, 13.5, "700", "middle")
    text(x + LANE_WIDTH / 2, 44, sub, 11, anchor="middle", opacity="0.7")

# Planning lane
planning_note(70, 106, "Test VM, since 11-15", ["Antigravity on Fable; Claude Code", "/mnt/lupin-data/", "  unified-headless-wrapper", "root CLAUDE.md, AGENTS.md"])
planning_note(192, 92, "MacBook", ["Claude Code desktop; claude.ai", "chats through the device bridge;", "the laptop checkout"])
planning_note(300, 1400, "Every phase", [
    "D40 as amended 11-17:", "planning runs on Claude models,", "under Claude Code or Antigravity", "",
    "writes src/rnd/ only; never", "src/uhw_kernel/ or lupin", "",
    "opens with git pull --rebase;", "reads the builder's BUILD.md", "into the status page", "",
    "owns 03-builder-loader.md,", "changed only by ruling"])

# Rick
box("phase0", "rick", 70, "Phase 0 · captures", ["C1 to C14; gate G1 passed", "work laptop (Jetski),", "test VM (AGY)"], kind="done", tag="DONE")
box("before", "rick", 182, "Before the build", ["destructive-test Lupin :8000 (row 17)", "builder's clone (row 91)", "global mandates (row 93)", "AH4L launch, voice (row 95)", "C20, T22 inventory → Kernel-2", "C18 → Kernel-5 ask rules"], kind="open", tag="OPEN")
parts.append(f'<path d="M{LANE_X["rick"] + LANE_WIDTH + 2},205 L{LANE_X["rick"] + LANE_WIDTH + 44},205" '
             f'stroke="{AMBER}" stroke-width="2" marker-start="url(#amberStart)"/>')
text(LANE_X["builder"] + 36, 201, "we are here", 11, "700", fill=AMBER)
text(LANE_X["builder"] + 36, 215, "11-19, no kernel code", 10.5, fill=AMBER)

# The Phase 1 builder
box("phase1", "builder", 330, "Phase 1 · kernel + AGY adapter", ["src/uhw_kernel/, tests/ only", "loader: 03-builder-loader.md", "reports in src/uhw_kernel/BUILD.md", "kernel under test → :8000", "Kernel-1 to 8 (bootstrap 1 to 4)", "proof: one AGY persona by voice,", "  one working day, no terminal"])
box("kit", "builder", 488, "Convention kit port", ["~25 workflows (T37 spec Sect. 5)"])
box("relocation", "builder", 568, "The relocation", ["closes Phase 1", "src/uhw_kernel/ →", "  lupin/src/lupin_kernel/", "lupin_compat.py → imports (row 89)", "written in its own lupin clone,", "  which :8000 then runs (rows 86, 100)", "exit: Kernel-1 to 8 green again"], kind="gate")

# The AGY implementer
box("gate15", "agy", 730, "Gate G1.5", ["Convention-1 to 9", "an AGY implementer follows the kit", "  on one kernel task, in lupin"], kind="gate", tag="GATE")
box("phase2", "agy", 834, "Phase 2 · fleet, crew, Lupin side", ["the Move clock's lupin wiring", "  (Section 4.1, steps 2 to 6)", "Fleet, Bootstrap, Console, grant,", "  ticket store, Lupin-1 to 8, crew", "proof: cascade review, AGY", "  manager + workers, scratch repo"])
box("move", "agy", 990, "Move inventory run", ["closes the Move clock and Phase 2;", "every Move row resolved"], kind="gate", tag="CLOCK")
box("phase3", "agy", 1078, "Phase 3 · Claude adapter", ["AGY implementer builds it", "Claude persona under the kernel", "  tests or reviews (row 90)", "Kernel-1 to 8 on claude; C15b,", "  Inbox-6, Timeout-1"])

# The development server
box("phase4", "dev", 1234, "Phase 4 · parity + shadow", ["every family green on Claude", "dev-server roles under the kernel", "  beside AH4L; baseline recorded"])
box("parity", "dev", 1348, "Gate G2, parity", ["full table green on both families;", "Switch-5: go or no-go to stop AH4L"], kind="gate", tag="GATE")
box("switchRick", "rick", 1438, "Switch week · Rick", ["laptop console: tag ah4l-final,", "freeze, memento, snapshot,", "quiescence, AH4L stopped, archive"], kind="gate", tag="CLOCK")
box("switchPersona", "dev", 1438, "Switch week · persona", ["Claude persona makes lupin edits;", "kernel fleet spawned; soak starts"], kind="gate", tag="CLOCK")
box("soak", "dev", 1530, "Gate G2, soak", ["5 working days, 7 measures;", "failure restarts the clock"], kind="gate", tag="GATE")
box("delete", "dev", 1622, "The Delete", ["one commit, merged to main"], kind="gate", tag="CLOCK")

arrow("phase0", "before", "G1 passed")
arrow("before", "phase1", "clone made, :8000 up")
arrow("phase1", "kit", "Kernel-1 to 8 green")
arrow("kit", "relocation")
arrow("relocation", "gate15", "handoff (D40, D51)")
arrow("gate15", "phase2")
arrow("phase2", "move")
arrow("move", "phase3")
arrow("phase3", "phase4", "Claude families green")
arrow("phase4", "parity")
arrow("parity", "switchPersona", "go")
arrow("switchPersona", "soak")
arrow("soak", "delete", "soak passed")
rx, ry, rw, rh = nodes["switchRick"]
px, py, _, _ = nodes["switchPersona"]
parts.append(f'<path d="M{rx + rw},{ry + 30} L{px},{py + 30}" fill="none" stroke="currentColor" '
             f'stroke-width="1.2" stroke-dasharray="4 3"/>')
text((rx + rw + px) / 2, ry + 24, "Rick runs the week; the persona edits", 10.5, anchor="middle", opacity="0.75")
sx, sy, _, sh = nodes["soak"]
parts.append(f'<path d="M{sx},{sy + sh - 12} L{rx + rw / 2},{sy + sh - 12} L{rx + rw / 2},{ry + rh + 2}" '
             f'fill="none" stroke="{AMBER}" stroke-width="1.3" stroke-dasharray="4 3" marker-end="url(#amber)"/>')
text(rx + rw / 2 + 8, sy + sh - 18, "rollback: tag + archive, ~1 hour (rehearsed on test VM)", 10.5, fill=AMBER)

defs = (f'<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
        f'orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="currentColor"/></marker>'
        f'<marker id="amber" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
        f'orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="{AMBER}"/></marker>'
        f'<marker id="amberStart" viewBox="0 0 10 10" refX="1" refY="5" markerWidth="7" markerHeight="7" '
        f'orient="auto"><path d="M10,0 L0,5 L10,10 z" fill="{AMBER}"/></marker></defs>')
summary = ("UHW build phases as swimlanes. Planning runs on Claude models throughout. Rick runs Phase 0 and "
           "the pre-build items. A Claude Code session under AH4L in the builder's clone builds Phase 1, ports "
           "the convention kit and relocates the package into lupin. From gate G1.5 an AGY persona under the "
           "kernel builds Phases 2 and 3 on the test VM, writing lupin there. Phase 4, Gate G2 parity, the "
           "switch week, Gate G2 soak and the Delete run on the development server, with Rick running the week "
           "from the laptop console.")
svg = (f'<svg viewBox="0 0 1176 {HEIGHT}" role="img" aria-label="{html.escape(summary)}" '
       f'font-family="inherit" xmlns="http://www.w3.org/2000/svg">{defs}{"".join(parts)}</svg>')

STAGES = [
    ("Phase 0 (done)", "Rick, running scripts planning wrote", "work laptop, test VM", "<code>src/captures/out/</code>", "AGY, Jetski; Claude for C5 to C7", "C1 to C14; gate G1 passed"),
    ("Before the build (open)", "Rick", "test VM, development server", "captures; destructive-test Lupin on :8000; the builder's clone", "—", "rows 17, 91, 93, 95; C20 and the T22 inventory before Kernel-2; C18 before Kernel-5"),
    ("Phase 1", "Claude Code session under AH4L, voice via the :7999 test instance, loader <code>03-builder-loader.md</code>", "test VM, <code>/mnt/lupin-data/unified-headless-wrapper-builder</code>", "<code>src/uhw_kernel/</code>, <code>tests/</code>; reports in <code>BUILD.md</code>", "AGY", "Kernel-1 to 8; one AGY persona by voice for a working day, no terminal"),
    ("Convention kit port", "the same session", "test VM", "the kit (T37 spec, Sect. 5)", "—", "—"),
    ("The relocation", "the same session; it closes Phase 1", "test VM", "<code>lupin/src/lupin_kernel/</code>, in a lupin clone of its own on the dedicated branch (row 86), which the server on :8000 then runs (row 100); the tree behind :7999 is never written", "AGY", "<code>lupin_compat.py</code> replaced by imports (row 89); Kernel-1 to 8 green again from lupin"),
    ("Gate G1.5", "AGY implementer persona, observed", "test VM", "one kernel task, in lupin", "AGY", "Convention-1 to 9"),
    ("Phase 2 <span class=\"badge\">3</span>", "AGY persona under the kernel", "test VM", "the test VM's lupin checkout, dedicated branch", "AGY", "its families; cascade review by AGY manager and workers on a scratch repo"),
    ("Move inventory run", "AGY persona under the kernel", "test VM", "—", "—", "every Move row resolved; closes Phase 2"),
    ("Phase 3 <span class=\"badge\">4</span>", "AGY implementer builds; a Claude persona under the kernel tests or reviews (row 90)", "test VM", "the <code>claude</code> adapter, in lupin", "Claude Code", "Kernel-1 to 8 on Claude; C15b, Inbox-6, Timeout-1; one day by voice; not resting on the reviewer's verdicts"),
    ("Phase 4", "kernel-run personas beside AH4L (the shadow)", "development server", "nothing; baseline recorded", "both", "every family green on Claude"),
    ("Gate G2, parity", "Rick's go or no-go", "development server", "—", "both", "full table green on both families; Switch-5"),
    ("Switch week", "Rick at the laptop console; a kernel-run Claude persona makes the lupin edits", "every fleet host", "lupin", "both", "the Switch clock's steps; Name-6, Name-7; soak clock started"),
    ("Gate G2, soak", "the kernel fleet, AH4L stopped but startable", "development server", "—", "both", "five working days, seven measures"),
    ("The Delete", "the kernel-run Claude persona", "development server, merged to main", "the Delete commit", "—", "Switch-6, Name-8, Role-7; commit merged"),
]
QUESTIONS = [
    ("1", "The relocation is done only when Kernel-1 to Kernel-8 are green again, run from lupin against the server on :8000; the day-long proof workload is not repeated."),
    ("2", "Three lupin trees on the test VM: :7999 stays on the deployed tree, never written; the kernel is written in a separate clone on the dedicated branch; :8000 is re-pointed at that clone."),
    ("3", "Lower-case “the move” is read three ways: what lupin_compat.py stands for, at the relocation; what the kernel had not done in Phase 1, under the Move clock; lupin's side, the Move clock. A sweep holds the reading of every such line."),
    ("4", "The build-platform decision's caveat, that Claude adapter testing on the test VM is “constrained”, is struck: no constraint holds."),
    ("5", "This chart is kept current by a zero-token check at every planning session's close."),
]
rows = "\n".join("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>" for r in STAGES)
questions = "\n".join(f'<li><span class="badge">{n}</span>{html.escape(t)}</li>' for n, t in QUESTIONS)

PAGE = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>UHW phases and who drives them</title>
<style>
:root{{color-scheme:light dark;--fg:#1d1d1f;--bg:#fbfbf9;--mute:#5f6368;--rule:#d9d9d4;--amber:{AMBER}}}
@media (prefers-color-scheme:dark){{:root{{--fg:#e8e6e1;--bg:#1b1b1a;--mute:#a3a29d;--rule:#3a3a37}}}}
body{{margin:0;background:var(--bg);color:var(--fg);font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,sans-serif}}
main{{max-width:1240px;margin:0 auto;padding:28px 22px 60px}}
h1{{font-size:24px;margin:0 0 4px}} h2{{font-size:18px;margin:36px 0 10px}}
.sub{{color:var(--mute);margin:0 0 18px}}
.badge{{display:inline-block;background:var(--amber);color:#fff;border-radius:999px;min-width:20px;text-align:center;font-weight:700;font-size:12px;line-height:20px;margin-right:6px}}
figure{{margin:0}} svg{{width:100%;height:auto;color:var(--fg)}}
figcaption{{color:var(--mute);font-size:13.5px;margin-top:8px}}
table{{border-collapse:collapse;width:100%;font-size:13.5px}}
th,td{{text-align:left;vertical-align:top;padding:7px 9px;border-bottom:1px solid var(--rule)}}
th{{font-weight:600;color:var(--mute)}}
ol{{padding-left:0;list-style:none}} ol li{{margin:0 0 10px}}
code{{font:12.5px ui-monospace,SFMono-Regular,Menlo,monospace}}
.note{{color:var(--mute);font-size:13px;margin-top:28px;border-top:1px solid var(--rule);padding-top:10px}}
</style></head><body><main>
<h1>UHW: phases, places and who drives them</h1>
<p class="sub">As of {AS_OF}. Drawn from <code>00-status.md</code>, framework Section 15 and the rulings of rows 85, 87 and 96. Framework Section 15 is the authority; <code>check_phase_chart.py</code>, run at every planning session’s close, fails when the text this chart was drawn from has changed.</p>
<figure>
{svg}
<figcaption>Time runs top to bottom. A box sits in the lane of whoever drives that stage; thick borders are gates and clocks; dashed boxes are still open. Rows named in boxes are open rows of “Outstanding actions”.</figcaption>
</figure>
<h2>Stage by stage</h2>
<table>
<tr><th>Stage</th><th>Driven by</th><th>Host</th><th>Writes to</th><th>Engine under test</th><th>Exit</th></tr>
{rows}
</table>
<h2>Ruled on 2026-11-18 (row 96, “Review: what the sequence rulings left open”)</h2>
<ol>
{questions}
</ol>
<p class="note">Generated by <code>build_phase_chart.py</code> beside this file: <code>python3 build_phase_chart.py build-phases-and-drivers.html build-phases-and-drivers.svg</code>. Edit the script, not the page.</p>
</main></body></html>
"""

FONTS = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Inter, Roboto, Helvetica, Arial, sans-serif"


def standalone_svg():
    """The chart alone, for use outside the page: white ground, fixed fonts, a title."""
    head, body = svg.split(">", 1)
    head = head.replace('font-family="inherit"', f'font-family="{FONTS}" color="#1d1d1f"')
    title = html.escape(f"UHW: phases, places and who drives them ({AS_OF})")
    ground = f'<rect x="0" y="0" width="1176" height="{HEIGHT}" fill="#ffffff"/>'
    return f'<?xml version="1.0" encoding="UTF-8"?>\n{head}><title>{title}</title>{ground}{body}\n'


if __name__ == "__main__":
    outputs = sys.argv[1:] or ["build-phases-and-drivers.html"]
    for out in outputs:
        content = standalone_svg() if out.endswith(".svg") else PAGE
        with open(out, "w", encoding="utf-8") as f:
            f.write(content)
        print(out)
