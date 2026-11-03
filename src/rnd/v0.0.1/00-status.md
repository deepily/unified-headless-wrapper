# UHW · status

**Read first in every UHW session; update last.** This page says where the work stands and what is next. It holds no design. The master design is `01-framework.md` (as of 2026-11-03): decisions in Section 1, TODO register in Section 20, fill-in order in Section 16. **This repo is the single source of truth** (D20 as amended 11-03); the claude.ai project copies under `uhw/` are superseded and are deleted after 11-10.

## Where things stand (2026-11-03)

| | |
|---|---|
| Phase | Phase 0 complete (AGY 1.4.7, Jetski, Claude C5–C7). G1 passed on AGY and Jetski. Phase 1 specified (`specs/2026.10.24-phase1-…-spec.md`, acceptance A1–A8); **no kernel code written yet**, in either repo. |
| Code location | **D45:** Phase 1 is built in this repo at `src/uhw_kernel/` on the test VM, by a Claude Code session under AH4L (voice via the :7999 test instance; kernel targets the destructive-test server), with no lupin imports. Moves to `lupin/src/lupin_kernel/` after A1–A8 (D38). Lupin is written on the dev server only. Bootstrap candidate = A1–A4. |
| Decisions | D1–D46 locked. T01–T07 ruled as D38–D44 on 10-26; D45 on 11-02; T10 ruled as D46 on 11-03. |
| Open | T08–T35 less T10 (27 items): 19 design, 5 measure, 1 decide+design, 2 separate. |
| Last session | 2026-11-03, chat "T10 stable id derivation". |
| Platform | AGY 1.4.7 non-snap on GCP VM `lupin-host-test` (the lupin test VM), test Lupin instance + destructive-test server, via SSH tunnel (D32, D34). |

## Next three (framework Section 16, item 4)

1. **T11** · Section 5.4 · `--mode` per persona; system prompt contents per engine.
2. **T24** · Sections 17/19 · engine self-update: version vetting and C2 smoke check at spawn.
3. **T14** · Section 8 · Jetski internal tools; which file the engines read before their first MCP call (measure).

Then the rest of Section 8 (T26, T32) → Sections 6/7 (T12, T13, T27) → Section 11 (T17, T23, T20) → Sections 13/10/9 (T18, T16, T25, T28, T15) → Section 15 (T19, T31).

## Working rhythm

One chat per T-item, titled after it. Open from this page; close by writing the design into its framework section, flipping its Section 20 row, and adding one line below. With the laptop connected, every edit is made live in the checkout at `src/rnd/v0.0.1/`; the night's changes are pushed to `origin` before the session ends. Without the laptop, read the pushed branch from GitHub.

## Session log (newest first)

- **2026-11-03** · **T10 → D46.** Read lupin's identity code (laptop clone, read-only): `stable_session_id` is the first Claude session id of a process (write-once lockfile); only its first eight hex are ever on the wire or on disk (`job_id`, `cc-listener-{key}`, sender suffix, buffer, memento match); the web client closes the loop by posting `job_id = parseSenderId( sender_id ).sessionId`. Ruled: **one identifier, eight hex, minted by the kernel**; it is the `job_id`, the suffix, the socket name and the directory name; no UUID form; migration is `stable_session_id[:8]`, byte-identical on every contract. Found: the voice-persona pool's state is the bridge files (→ T31); the TypeScript multiplexer client replaces `notifications.js`, so T27 lands there. **T35 opened:** canonical persona name (`María` / `Mr. Radio` in five forms across the configuration manager, the pool line, DM topics, mementos, task store; four local folding copies beside `lupin_mcp/persona_normalization.py`); rule now: a name never crosses a kernel interface. Framework Section 4.1 written, Section 18 and risk table amended; Phase 1 spec Sections 6/7/8/11/12 corrected (`cos-a1b2c3d4` gone; manifests are templates, the kernel mints the id). *Docs:* framework, `specs/2026.11.03-t10-stable-id-spec`, Phase 1 spec. **D20 amended:** the repo is the single source of truth; project copies superseded, deleted after 11-10; edits live in the laptop checkout, pushed nightly. Next: T11.
- **2026-11-02** · Recovery and reorganization. Status page created; framework renamed `01-framework.md`; `src/rnd/v0.0.1/` split into living docs plus `specs/`, `evidence/`, `archive/`; Section 21, README and RUNBOOK references updated; project mirror synced. **D45** ruled: Phase 1 built in this repo (`src/uhw_kernel/`) on the test VM by a Claude Code session under AH4L, no lupin imports, lupin written on the dev server only; D38 amended; Phase 1 spec Sections 3/14 updated. Memory trimmed to working constraints. Next: T10.
- **2026-10-26/27** · Design gap review → D35 (control path), D36 (socket per persona), D37 (ticketed asks); amendments to D6, D9, D12, D18, D25, D33. T01–T07 ruled: D38 code in `lupin/src/lupin_kernel/`, D39 no AGY subagents, D40 dogfooding after A1–A8, D41 skills on every engine, D42 `agy@`/`jetski@` sender ids, D43 instruction files in worktrees, D44 default models per role. Framework refreshed (Sections 2.5a, 8 tool map, Section 20 register). Kernel explainer written and corrected (exposure ≠ enforcement; pgvector, not LanceDB). *Docs:* framework, `archive/2026.10.26-design-gap-review`, `kernel-explainer/`, Phase 1 spec Section 14.
- **2026-10-24/25** · AGY 1.4.7 non-snap round on the test VM: C11–C14, C13 on four pinned models 24/24, 180 s MCP cap confirmed family-wide, hooks do not fire inside AGY subagents. Phase 1 spec written 10-24. *Docs:* `evidence/2026.10.25-agy-capabilities-results`, `specs/2026.10.24-phase1-…-spec`.
- **2026-10-23** · AGY round on the VM under snap: invalid (confinement hid `/tmp`, project hooks, `~/.gemini`) → D34 no snap engines; D32 build platform = VM; D33 name "Lupin kernel". *Doc:* `evidence/2026.10.23-agy-round-results`.
- **2026-10-20/21** · Claude C5 (hook isolation), C6 (control interrupt, process survives), C7 (mid-turn absorbed). D26 chief_of_staff, D27 escalation, D28 narration, D29 interface partition, D30 commands → skills, D37 ticketed asks. *Docs:* `evidence/2026.10.20-claude-round-results`, `specs/2026.10.20-ticketed-asks-spec`.
- **2026-10-18** · Jetski 2026.10.16 round 3 (C11–C14, work laptop). Role table, AH4L capability inventory. D21–D25. *Docs:* `evidence/2026.10.18-jetski-capabilities-c11-c14-results`, `specs/2026.10.18-uhw-role-table`, `specs/2026.10.18-ah4l-capability-inventory`.
- **2026-10-15** · Phase 0 Part A (AGY 1.3.5) and Part B (Jetski 2026.10.14): C1–C4, C9, C10. G1 passed on both. *Docs:* `evidence/2026.10.15-phase0-part-a-agy-results`, `-part-b-jetski-results`.
- **2026-10-12/14** · Prototype `lupin_headless.py` + fake engine; build order (Jetski/AGY first); D1–D20; framework created 10-14. *Docs:* `archive/2026.10.12-…`, framework.
