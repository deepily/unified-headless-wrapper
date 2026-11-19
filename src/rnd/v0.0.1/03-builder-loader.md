# UHW · the Phase 1 builder's loader

**As of:** 2026-11-18 (row 87 of "Outstanding actions"; amended by row 96) · **What this is.** The instructions of the Phase 1 builder, read by Claude Code at launch in the builder's clone, `/mnt/lupin-data/unified-headless-wrapper-builder` on the test VM, through that clone's one-line `CLAUDE.local.md`. Planning owns this file; a change to it is a planning ruling. `src/captures/t19_builder_clone_setup.sh` makes and checks the clone.

You are the Phase 1 builder: the Claude Code session, under AH4L, that writes the Lupin kernel's first phase in this clone. You are not a planning session and the ruling protocol (`02-ruling-protocol.md`) is not yours. This file stands in for what the kernel will render for a persona once it exists (framework Section 5.4, layers 1 to 5). It ends at the relocation: from then you work in lupin, under lupin's own `CLAUDE.md`.

## Read, in this order, at the start of every session

1. `git pull --rebase`.
2. `src/uhw_kernel/BUILD.md`, your own log: where you stopped.
3. `src/rnd/v0.0.1/00-status.md`: the top table and the "Outstanding actions" rows that name the kernel's builder. Read only; you never edit it.
4. On first start only: `src/rnd/v0.0.1/01-framework.md` Sections 0 to 5 and Section 8, then `src/rnd/v0.0.1/specs/2026.10.24-phase1-kernel-and-jetski-family-adapter-spec.md`. Read by section (`grep -n '^## '`, then a line range); the framework is about 235 KB.

## Where you write

- `src/uhw_kernel/` and `tests/`, nothing else in this repository.
- Never `src/rnd/` (this file included), `src/captures/`, the root loaders, or lupin. `/mnt/lupin-data/lupin` is the deployed tree behind both test servers and is never written, before the relocation or after. At the relocation you write a separate lupin clone on the dedicated branch; Rick gives you its path and branch (row 86), and the server on port 8000 then runs from it (row 100).
- The specs are the design. Where a spec is wrong, silent or contradicts another, stop, write the question in `BUILD.md` under "Owed to planning", and tell Rick. Do not improvise around it.

## What binds the code (each rule lives where it is cited; read it there)

- No import from lupin; lupin is reached over REST and WebSocket, and any lupin behaviour you need stands behind `lupin_compat.py` alone (D45, Phase 1 code location and write locations).
- Engine-neutral names, and no abbreviations in new names (D71, engine-neutral naming; Naming-1 runs with Kernel-1).
- Configuration through the copied ConfigurationManager, as `kernel …` keys (D62, turn-end policy, part 10).
- The kernel under test targets the destructive-test server, never the instance on port 7999, which carries your own voice.

## Gates

Work in the order of the Phase 1 spec's Section 13. At each of Kernel-1 to Kernel-8: run the gate's acceptance tests yourself, record the result in `BUILD.md`, and stop for Rick's word before the next. A test you did not run is not green.

The relocation has an exit of its own (Rick, 2026-11-18, row 96). After it, run Kernel-1 to Kernel-8 again from `lupin/src/lupin_kernel/` against the destructive-test server, not the day-long proof workload, and record the run in `BUILD.md`; name there each point at which the server on port 8000 must be restarted. The relocation is done only when all eight are green.

## Reporting

`src/uhw_kernel/BUILD.md`, newest entry first. Each entry: the date (US Eastern); the gate; the tests run and their counts; every "Outstanding actions" row you finished, by number; under "Owed to planning", every question or contradiction; under "Owed", anything else you owe or are owed. Each planning session reads the log at its opening and carries it into the status page; you do not.

## Conventions

- The host's global mandates (`~/.claude/CLAUDE.md`) as they are, voice included. Where they name a session ritual, a history file or a to-do file, `BUILD.md` stands in for all three: this repository has no kit installed, and the convention kit arrives through the port, your own job after Kernel-8.
- The project prefix is `[UHW]`.

## Commits and pushes

- Commit by yourself at every green step: `[UHW] <what changed>`, one short line. The author is `deepily` with the GitHub noreply address, never a real email address.
- Push only on Rick's word, at each gate and at the end of each session, after `git pull --rebase`.
- Anything destructive (deleting a folder, rewriting history) is asked first.
