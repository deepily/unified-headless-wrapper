#!/usr/bin/env python3
"""t19_move_reading_sweep.py: every lower-case "the move" in the record, with its reading (row 96, ruling 3).

Zero tokens, standard library only, read-only. The rule (Rick, 2026-11-18):
  (a) whatever `lupin_compat.py` stands for is replaced at the relocation (row 89's list);
  (b) what the kernel had not done in Phase 1 is imported by the Phase 2 work that needs it, under the Move clock;
  (c) everything on lupin's side is the Move clock.

Usage:
  src/captures/t19_move_reading_sweep.py            # the table, as markdown
  src/captures/t19_move_reading_sweep.py --check    # exit 1 when an occurrence has no reading, or a reading matches nothing

An occurrence is one match of PATTERN in the framework, the status page or a spec. A reading is keyed by the
file, a phrase that stands on the same line, and which match on that line it is, never by a line number.
A row of this script's own table, where a spec quotes it, is passed over.
"""
import glob, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2] / "src" / "rnd" / "v0.0.1"
PATTERN = re.compile(r"\b(before|after|at|from|until) the move\b")
OWN_TABLE_ROW = re.compile(r"^\| \d+ \| `[^`]+`:\d+ \| ")

RELOCATION = "the relocation"
MOVE_CLOCK = "the Move clock"
BY_LIST    = "the relocation if row 89's list holds it; otherwise the Move clock"
EITHER     = "either: nothing changes at either"
RULE_TEXT  = "not read: the rule's own words"

# ( file, phrase on the line, which match on the line, reading, part of the rule, why )
READINGS = [
    ("01-framework.md", "| D45 |", 1, RELOCATION, "a", "what stands behind `lupin_compat.py` before it"),
    ("01-framework.md", "| D58 |", 1, MOVE_CLOCK, "c", "Lupin's tailer imports the mapper"),
    ("01-framework.md", "| D59 |", 1, MOVE_CLOCK, "b", "the worktree modules and `vertex_env`, kept and imported"),
    ("01-framework.md", "| D61 |", 1, BY_LIST, "a", "the interim acknowledgment write gives way to `CommonsStore.post`"),
    ("01-framework.md", "| D62 |", 1, RELOCATION, "a", "the `configuration_manager.py` copy is deleted"),
    ("01-framework.md", "| D69 |", 1, EITHER, "", "no copy of lupin's module, before or after"),
    ("01-framework.md", "All of it is one pure leaf module", 1, RELOCATION, "a", "the package's name"),
    ("01-framework.md", "The model never acknowledges", 1, BY_LIST, "a", "the interim acknowledgment write"),
    ("01-framework.md", "- Build: steps 1, 2, 4, 6 are kernel code", 1, MOVE_CLOCK, "b", "the dismissal steps import the worktree modules"),
    ("01-framework.md", "Naming-2 with the Lupin changes", 1, MOVE_CLOCK, "c", "Lupin's changes"),
    ("01-framework.md", "drops the copy at the move", 1, RELOCATION, "a", "the `configuration_manager.py` copy is dropped"),
    ("00-status.md", "D45's rule is scoped to the time before the move", 1, RELOCATION, "a", "session log, history: the rule against lupin imports"),
    ("00-status.md", "the web console's kernel side lands only after the move", 1, MOVE_CLOCK, "c", "session log, history: Lupin's web console"),
    ("specs/2026.11.03-t10-stable-id-spec.md", "# identity.py", 1, RELOCATION, "a", "the package's name"),
    ("specs/2026.11.03-t10-stable-id-spec.md", "# identity.py", 2, MOVE_CLOCK, "c", "cosa-voice, lupin's side, imports the module"),
    ("specs/2026.11.03-t10-stable-id-spec.md", "persona_normalization", 1, MOVE_CLOCK, "b", "superseded by D69 (canonical persona name), part 7: the kernel never normalizes"),
    ("specs/2026.11.03-t10-stable-id-spec.md", "persona_normalization", 2, EITHER, "", "no copy is needed before it"),
    ("specs/2026.11.08-t17-log-schema-and-rotation-spec.md", "**Amended 2026-11-09 (D58):**", 1, MOVE_CLOCK, "c", "Lupin's tailer imports the mapper"),
    ("specs/2026.11.08-t17-log-schema-and-rotation-spec.md", "Kernel-3 (Lupin side after the move)", 1, MOVE_CLOCK, "c", "the Lupin side of Log-6"),
    ("specs/2026.11.08-t17-log-schema-and-rotation-spec.md", "the Lupin side in Phase 2, after the move", 1, MOVE_CLOCK, "c", "the Lupin side of Log-6"),
    ("specs/2026.11.09-t16-fleet-spec.md", "- **Build:** steps 1, 2, 4, 6", 1, MOVE_CLOCK, "b", "the dismissal steps import the worktree modules"),
    ("specs/2026.11.09-t16-fleet-spec.md", "fleet-size-cap", 1, MOVE_CLOCK, "c", "Lupin's routes repointed"),
    ("specs/2026.11.09-t16-fleet-spec.md", "kept and imported after the move; liveness", 1, MOVE_CLOCK, "b", "the worktree modules"),
    ("specs/2026.11.09-t16-fleet-spec.md", "| Fleet-6 |", 1, MOVE_CLOCK, "b", "a Phase 2 test of the dismissal steps"),
    ("specs/2026.11.09-t20-console-spec.md", "**One mapper, in the kernel package:**", 1, MOVE_CLOCK, "c", "Lupin's tailer imports the mapper"),
    ("specs/2026.11.09-t20-console-spec.md", "Lupin side, after the move", 1, MOVE_CLOCK, "c", "the Lupin side of the console tests"),
    ("specs/2026.11.10-t08-kernel-lifecycle-spec.md", "ExecStart=", 1, RELOCATION, "a", "the unit names the package, so it changes when the package does"),
    ("specs/2026.11.10-t08-kernel-lifecycle-spec.md", "lupin's deploy after the move", 1, RELOCATION, "a", "the package ships with the tree it lives in"),
    ("specs/2026.11.10-t08-kernel-lifecycle-spec.md", "`tree.sweep`", 1, MOVE_CLOCK, "b", "lupin's `worktree_reaper`"),
    ("specs/2026.11.10-t15-turn-end-policy-spec.md", "left behind at the move", 1, RELOCATION, "a", "the `configuration_manager.py` copy"),
    ("specs/2026.11.10-t15-turn-end-policy-spec.md", "the copy is deleted at the move", 1, RELOCATION, "a", "the `configuration_manager.py` copy"),
    ("specs/2026.11.10-t19-exit-criteria-and-switch-over-spec.md", "**How older text is read.**", 1, RULE_TEXT, "", "row 85's rule, quoting the phrase"),
    ("specs/2026.11.10-t19-exit-criteria-and-switch-over-spec.md", "**How older text is read.**", 2, RULE_TEXT, "", "row 85's rule, quoting the phrase"),
    ("specs/2026.11.10-t28-broadcasts-spec.md", "**Parser carried over", 1, BY_LIST, "a", "the interim acknowledgment write"),
    ("specs/2026.11.10-t28-broadcasts-spec.md", "- **Phase 1:** a forty-line writer", 1, BY_LIST, "a", "the interim acknowledgment write"),
    ("specs/2026.11.15-t35-canonical-persona-name-spec.md", "no copy of lupin's module, before or after the move into lupin", 1, EITHER, "", "no copy, before or after"),
    ("specs/2026.11.15-t38-engine-neutral-naming-spec.md", "OLD_LISTENER_PREFIX =", 1, MOVE_CLOCK, "c", "kept with the Move clock by name (row 85; D71, engine-neutral naming, part 4), though the constant stands in `lupin_compat.py`"),
    ("specs/2026.11.15-t38-engine-neutral-naming-spec.md", "What Lupin accepts", 1, MOVE_CLOCK, "c", "Lupin accepts both listener names"),
    ("specs/2026.11.15-t38-engine-neutral-naming-spec.md", "The name the kernel connects under", 1, MOVE_CLOCK, "c", "follows what Lupin accepts (D71, part 4)"),
]


def occurrences():
    files = ["01-framework.md", "00-status.md"] + sorted("specs/" + pathlib.Path(p).name for p in glob.glob(str(ROOT / "specs" / "*.md")))
    for name in files:
        for number, line in enumerate((ROOT / name).read_text(encoding="utf-8").split("\n"), 1):
            if OWN_TABLE_ROW.match(line):
                continue  # this script's own table, quoted in a spec's amendment
            for index, match in enumerate(PATTERN.finditer(line), 1):
                yield name, number, line, index, match


def sweep():
    rows, unread, used = [], [], set()
    for name, number, line, index, match in occurrences():
        hits = [i for i, r in enumerate(READINGS) if r[0] == name and r[1] in line and r[2] == index]
        if len(hits) != 1:
            unread.append(f"{name}:{number} (match {index}): {len(hits)} readings: …{line[max(0, match.start() - 60):match.end() + 30]}…")
            continue
        used.add(hits[0])
        rows.append((name, number, match.group(0), READINGS[hits[0]]))
    stale = [f"{r[0]}: no line holds '{r[1]}' (match {r[2]})" for i, r in enumerate(READINGS) if i not in used]
    return rows, unread, stale


def main():
    rows, unread, stale = sweep()
    if "--check" in sys.argv:
        for problem in unread + stale:
            print("FAILS", problem)
        lines = len({(r[0], r[1]) for r in rows})
        print(f"{len(rows)} occurrences on {lines} lines in {len({r[0] for r in rows})} files, each with one reading" if not (unread or stale) else "FAILS")
        sys.exit(1 if (unread or stale) else 0)
    print("| # | Where | Words | Reading | Rule | Why |")
    print("|---|---|---|---|---|---|")
    for n, (name, number, words, reading) in enumerate(rows, 1):
        print(f"| {n} | `{name.replace('specs/', '')}`:{number} | {words} | {reading[3]} | {reading[4]} | {reading[5]} |")
    counts = {}
    for row in rows:
        counts[row[3][3]] = counts.get(row[3][3], 0) + 1
    print()
    for reading, count in sorted(counts.items(), key=lambda item: -item[1]):
        print(f"- {count}: {reading}")
    for problem in unread + stale:
        print("FAILS", problem)


if __name__ == "__main__":
    main()
