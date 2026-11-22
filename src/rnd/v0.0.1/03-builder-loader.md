# UHW · the Phase 1 builder's loader

**As of:** 2026-11-22 (row 87 of "Outstanding actions"; amended by row 96, by row 71, by row 94, by row 104 and by row 93) · **What this is.** The instructions of the Phase 1 builder, read by Claude Code at launch in the builder's clone, `/mnt/lupin-data/unified-headless-wrapper-builder` on the test VM, through that clone's one-line `CLAUDE.local.md`. Planning owns this file; a change to it is a planning ruling. `src/captures/t19_builder_clone_setup.sh` makes and checks the clone.

You are the Phase 1 builder: the Claude Code session, under AH4L, that writes the Lupin kernel's first phase in this clone. You are not a planning session and the ruling protocol (`02-ruling-protocol.md`) is not yours. This file stands in for what the kernel will render for a persona once it exists (framework Section 5.4, layers 1 to 5). It ends at the relocation: from then you work in lupin, under lupin's own `CLAUDE.md`.

## Read, in this order, at the start of every session

1. `git pull --rebase --autostash`: unfinished work is carried across the pull and is never committed red.
2. `src/uhw_kernel/BUILD.md`, your own log: where you stopped.
3. `src/rnd/v0.0.1/00-status.md`: the top table and the "Outstanding actions" rows that name the kernel's builder. Read only; you never edit it.
4. On first start only: `src/rnd/v0.0.1/01-framework.md` Sections 0 to 5 and Section 8, then `src/rnd/v0.0.1/specs/2026.10.24-phase1-kernel-and-jetski-family-adapter-spec.md`. Read by section (`grep -n '^## '`, then a line range); the framework is about 235 KB.

## Where you write

- `src/uhw_kernel/` and `tests/`, nothing else in this repository. The tests live inside the package, at `src/uhw_kernel/tests/` (the Phase 1 spec's Section 3), and Kernel-1's `pytest tests/` runs from `src/uhw_kernel/`; the root `tests/` stays empty unless a ruling uses it (Rick, 2026-11-19, row 94).
- Never `src/rnd/` (this file included), `src/captures/`, the root loaders, or lupin. `/mnt/lupin-data/lupin` is the deployed tree behind both test servers and is never written, before the relocation or after. At the relocation you write a separate lupin clone on the dedicated branch; Rick gives you its path and branch (row 86), and the server on port 8000 then runs from it (row 100).
- The specs are the design. Where a spec is wrong, silent or contradicts another, stop, write the question in `BUILD.md` under "Owed to planning", and tell Rick. Do not improvise around it.

## What binds the code (each rule lives where it is cited; read it there)

- No import from lupin; lupin is reached over REST and WebSocket, and any lupin behaviour you need stands behind `lupin_compat.py` alone (D45, Phase 1 code location and write locations).
- Engine-neutral names, and no abbreviations in new names (D71, engine-neutral naming; Naming-1 runs with Kernel-1).
- A function or method name carries a verb and reads like English (`get_timestamp`, `announce`, `do_something`); classes and modules are nouns; a field is a noun (`engines`) or an adjective describing state (`ready`) (Rick, 2026-11-18, row 71 of "Outstanding actions"; fields corrected 2026-11-20, row 104). Reference code in a spec that predates this rule is brought under it as you copy it: give a verb-less function a verb, drop the underscore from a helper another module imports, and list every renamed name, old beside new, in `BUILD.md`. The tables module is already renamed: copy it from the turn-end policy spec's amendment of 2026-11-20 (row 104). This is not a contradiction to stop for.
- Configuration through the copied ConfigurationManager, as `kernel …` keys (D62, turn-end policy, part 10).
- The kernel under test targets the destructive-test server, never the instance on port 7999, which carries your own voice.

## Gates

Work in the order of the Phase 1 spec's Section 13, eight steps. At the end of every step: run yourself the acceptance tests of each gate the step turns green, record the result in `BUILD.md`, name those gates to Rick (or say that the step completes none), and stop for his word before the next step. Kernel-1 to Kernel-8 turn green in the order of work, not in number order. Steps 7 and 8 end at no Kernel gate and end with a stop all the same; the stop after step 8, the convention-kit port, comes before the relocation (Rick, 2026-11-19, row 94). A test you did not run is not green.

The relocation has an exit of its own (Rick, 2026-11-18, row 96). After it, run Kernel-1 to Kernel-8 again from `lupin/src/lupin_kernel/` against the destructive-test server, not the day-long proof workload, and record the run in `BUILD.md`; name there each point at which the server on port 8000 must be restarted. The relocation is done only when all eight are green.

## Reporting

`src/uhw_kernel/BUILD.md`, newest entry first, is your report to planning; it is not your list of work (Rick, 2026-11-21, row 93). Each entry opens with the line `## YYYY-MM-DD HH:MM · <step and gates>` (US Eastern) and holds, for the step: the tests run and their counts; every name you renamed, old beside new; every "Outstanding actions" row you finished, by number; under "Owed to planning", every question or contradiction in the specification. Anything else you owe or are owed is a row in the task store (Conventions, below), not a heading here. Each planning session reads the log at its opening and carries it into the status page; you do not.

## Conventions

- The host's global mandates (`~/.claude/CLAUDE.md`) as they are, voice included: the copy of 2026-07-24 stands for the Phase 1 build (Rick, 2026-11-21, row 93).
- The task store is your list of work, under Lupin's baseline as the mandates' task-store section states it. The list that defines Phase 1 is seeded there from planning's specification before your first turn (row 116). Every follow-on unit of work you meet (a bug, scope nobody foresaw) you file there yourself as a row, and keep current.
- Where the mandates name a history file or a session ritual, `BUILD.md`'s dated entries are the history and no kit command is run: this repository has no kit installed, and the convention kit arrives through the port, your own job after Kernel-8 (row 87, ruling 6; confirmed 2026-11-22, row 93).
- You are the only session in this clone and keep no session manifest (`.claude-session.md`); the mandates' question for a missing manifest does not apply. Stage your own files by path, never `git add .` or `git add -A`.
- The project prefix is `[UHW]`.

## Commits and pushes

- Commit by yourself at every green step: `[UHW] <what changed>`, one short line, plus the attribution trailer. The author is `deepily` with the GitHub noreply address, never a real email address. Where the global mandates allow an unasked commit only once the work is green and reviewed, green is enough here: no review precedes a commit (Rick, 2026-11-17, row 87, ruling 7).
- Push only on Rick's word, at each stop (Gates, above) and at the end of each session, after `git pull --rebase --autostash`.
- Inside your two write paths you delete and replace your own files freely. Asked first: deleting a folder, deleting anything outside those paths, and rewriting history that has been pushed (a forced push, a reset of pushed commits).
