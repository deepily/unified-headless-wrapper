#!/usr/bin/env python3
"""check_phase_chart.py: is the phase chart drawn from the record as it stands? (row 96, ruling 5)

Zero tokens, standard library only, read-only. The chart (build-phases-and-drivers.html and .svg, built by
build_phase_chart.py) is a second drawing of framework Section 15. This check takes a digest of the text the
chart encodes and compares it with the digest the generator recorded when the chart was last drawn:

  - Section 15's Mermaid chart;
  - the Stage and Platform columns of Section 15's table (not its two Exit columns);
  - the Section 1 rows of D38 (code location), D40 (dogfooding), D45 (Phase 1 code location and write
    locations) and D51 (convention parity), which say who drives what.

D63 (exit criteria and the switch-over) is left out: its sequence is mirrored in the table, and it is amended
for reasons the chart does not show. The check sees that the sources moved, not whether the drawing is still
right: when it fails, read the change, redraw if the chart shows it (edit build_phase_chart.py, run it), then
set SOURCES_DIGEST there to the digest printed here. Short of budget, add a row to "Outstanding actions".

Usage:
  charts/check_phase_chart.py              # "current" and exit 0, or "stale: ..." and exit 1
  charts/check_phase_chart.py --digest     # print the digest of the sources as they stand
  charts/check_phase_chart.py --self-test
"""
import hashlib, pathlib, re, sys

HERE = pathlib.Path(__file__).resolve().parent
ROWS = ("D38", "D40", "D45", "D51")


def sources(framework):
    section = framework[framework.index("\n## 15."):framework.index("\n## 16.")]
    found = [re.search(r"```mermaid.*?```", section, re.S).group(0)]
    lines = section.split("\n")
    head = [i for i, line in enumerate(lines) if line.startswith("| Stage |")]
    assert len(head) == 1, "Section 15 must hold exactly one table whose first column is Stage"
    for line in lines[head[0] + 2:]:
        if not line.startswith("|"):
            break
        cells = line.split("|")
        found.append(f"{cells[1].strip()}|{cells[-2].strip()}")
    rows = [line for line in framework.split("\n") if re.match(r"\| (%s) \|" % "|".join(ROWS), line)]
    assert len(rows) == len(ROWS), f"expected one Section 1 row each for {ROWS}, found {len(rows)}"
    return found + rows


def digest(framework):
    return hashlib.sha256("\n".join(sources(framework)).encode("utf-8")).hexdigest()[:16]


def recorded():
    return re.search(r'^SOURCES_DIGEST = "(\w+)"', (HERE / "build_phase_chart.py").read_text(encoding="utf-8"), re.M).group(1)


def self_test():
    base = "\n".join([
        "| D38 | Code location | a | 10-26 |", "| D40 | Dogfooding | b | 10-26 |", "| D45 | Phase 1 | c | 11-02 |",
        "| D51 | Parity | d | 11-06 |", "| D63 | Exit | e | 11-10 |", "", "## 15. Build phases", "```mermaid", "A --> B", "```",
        "| Stage | Exit: tests | Exit: proof workload | Platform |", "|---|---|---|---|",
        "| Phase 1 | Kernel-1 | a day | test VM |", "| Phase 2 | Fleet-3 | a review | test VM |", "",
        "| Clock | Closed by |", "|---|---|", "| the Move clock | the inventory run |", "", "## 16. Fill-in order", ""])
    cases = [
        ("a driver's row amended", base.replace("| c |", "| c, amended |"), True),
        ("a stage renamed", base.replace("| Phase 2 |", "| Phase 2, the wiring |"), True),
        ("a platform changed", base.replace("| a review | test VM |", "| a review | development server |"), True),
        ("the Mermaid chart changed", base.replace("A --> B", "A --> C"), True),
        ("a stage added", base.replace("| Phase 2 |", "| Gate G1.5 | Convention-1 | observed | test VM |\n| Phase 2 |"), True),
        ("an exit test changed", base.replace("Fleet-3", "Fleet-3 to Fleet-9"), False),
        ("D63 amended", base.replace("| e |", "| e, amended |"), False),
        ("another table in the section changed", base.replace("the inventory run", "the run"), False),
        ("text outside the sources changed", base + "a line\n", False),
    ]
    failed = 0
    for name, changed, moves in cases:
        ok = (digest(changed) != digest(base)) == moves
        failed += not ok
        print(("ok   " if ok else "FAILS"), name, "(the digest moves)" if moves else "(the digest holds)")
    print(f"{len(cases) - failed} of {len(cases)} cases")
    return failed


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(1 if self_test() else 0)
    now = digest((HERE.parent / "01-framework.md").read_text(encoding="utf-8"))
    if "--digest" in sys.argv:
        print(now)
        sys.exit(0)
    drawn = recorded()
    print("current" if now == drawn else f"stale: the sources read {now}, the chart was drawn from {drawn}")
    sys.exit(0 if now == drawn else 1)
