# UHW · ruling protocol

**As of:** 2026-11-14 · **What this is.** How a register item (a T-number in framework Section 20) goes from open to ruled to recorded. Distilled from the sessions of 2026-11-05 to 2026-11-11 (T12 through T22); `chronicle.md` holds their arc, `transcripts/` their record. The root `CLAUDE.md` loads this file into every Claude Code session opened in the repo. If a later ruling contradicts this file, the ruling wins and this file is corrected in the same session.

## 1. Where this runs

| Host | Claude | Working copy | Notes |
|---|---|---|---|
| MacBook | Claude Code desktop, through the device bridge | `~/Projects/unified-headless-wrapper` | Folder grants are per chat; `git commit` needs the one-time delete permission for `.git` lock files; the bridge has no GitHub credential, so Rick pushes. Read-only clones: `~/Projects/lupin`, `~/Projects/planning-is-prompting` |
| Test VM `lupin-host-test` | Claude Code on Fable | the checkout Claude Code is opened in | Native shell: no grants, no bridge, **no Claude Docs**. The Fable allocation is small, so Section 9 binds. Lupin and planning-is-prompting paths: **ask Rick at the first session and write them into this row** |
| Development server `dual-rtx-4090s` | — | `/mnt/DATA01/include/www.deepily.ai/projects/unified-headless-wrapper` | Beside the lupin checkout; scripts importing `cosa` run from lupin's `.venv`. Lupin is written here only |

Lupin is read, never written, from any UHW session.

## 2. Opening

1. One chat per item, titled after it: "T35, canonical persona name".
2. Rick names the item, normally one of the next three on `00-status.md`.
3. If he asks for progress first, compute it from the live repo (status page, framework Sections 16 and 20), never from memory, on the scale in use since 2026-11-08: share of what is needed to begin the kernel, share of what Phase 1 needs, share of the register. Flag any inconsistency found while counting.
4. Read `00-status.md`. Run `git status -sb` and `git log --oneline -3`; note the HEAD of this repo and of lupin, because the chronicle cites both.
5. When resuming from a handoff (Section 8), read it and the files it names, and do not redo research it marks done.

## 3. Grounding

- Read the framework sections named in the item's Section 20 row, every marker (`grep -n 'TODO(Tnn)' src/rnd/v0.0.1/01-framework.md src/rnd/v0.0.1/specs/*.md`), and the specs it touches. Read by section (`grep -n '^## '`, then `sed -n 'a,bp'`), never the whole framework (about 235 KB).
- Read the lupin code the design replaces or depends on. Claims about current behavior cite a file and line, never recall or a cached summary.
- Before restating an earlier ruling, read its Section 1 row and restate only what it says. (T20: D50, credential exposure, was overstated and had to be corrected.)
- **Public record before tokens.** Before any capture that spends context or model calls, search vendor documentation, issue trackers and forums; spend tokens only on what the record cannot answer. (Ruled during T23.)
- Facts only a host holds go into a zero-token script, `src/captures/tNN_<what>.sh`, with a new top block in `src/captures/RUNBOOK.md`. From the laptop, a question about the test VM goes to the persona on the development server that manages it, as a message drafted for Rick to paste verbatim.
- Before opening a register item, check whether an existing one already covers the scope; fold the new scope in and say so.

## 4. The narrative

`src/rnd/v0.0.1/narratives/YYYY.MM.DD-tNN-<slug>.md`, written before any ruling, readable cold by Rick's manager. The shape (as in T22):

```markdown
# <Item named in words> (Tnn)
## In brief
## Where the record stands        what code, docs and research show today, with sources
## Problems and options
### 1. <problem stated in words>  the problem; options, each with pros and cons; a recommendation
## What follows without a decision
## Decisions requested and ruled
| # | Decision | Recommendation | Ruling (YYYY-MM-DD) |
## Glossary                        names to register keys, when keys appear at all
```

Plain language, few acronyms, decisions named in words. A register key appears only in the glossary, or with its name on first use. On the laptop the narrative is also drafted as a Claude doc and linked; on the test VM the markdown file is the only copy, so give Rick its path.

## 5. The walk-through

- `AskUserQuestion`, **one decision per question, asked one after another.** Never several decisions in one question, never a list of questions in a message.
- Each question stands alone: the problem in a sentence, the options, the recommended option first and labelled "(Recommended)", pros and cons in the option descriptions.
- Write each ruling into the narrative's table as it comes.
- When Rick questions an option, answer and explain before asking again; when his correction changes the design, re-present every decision it touches.
- Findings that surface after the walk-through (while recording, or from a host check) get their own one-click rulings before the commit.
- Silence is not a ruling.

## 6. Recording

In this order:

1. **Reference implementation.** A small dependency-free Python module and its `unittest` file in `.scratch/tNN/`, run until green.
2. **Spec,** `specs/YYYY.MM.DD-tNN-<slug>-spec.md` (model: T21, T22): summary of the rulings; one section per ruling; records; configuration; reference implementation (module and tests inlined by script, never retyped, then extracted back out of the spec and rerun); acceptance tests, word-prefixed (`Quota-1` …), each with the phase or `Kernel-N` gate it runs with; what only the hosts can answer; results from the hosts (left open); changes to other documents; open items raised; alternatives considered.
3. **Framework,** `01-framework.md`:
   - a new Section 1 row: `| Dnn | <name> | **<the ruling in one bold sentence>** n parts. (1) … Ruled YYYY-MM-DD, n for n as recommended (Tnn). <spec>; narrative <path>. Acceptance … Resolves Tnn |`
   - the component sections patched, every `TODO(Tnn)` replaced
   - the Section 20 row struck (`~~<name>~~` … `**resolved: Dnn** (MM-DD)`) and the item struck in Section 16
   - Sections 17 (risks) and 21 (companions) as needed, and "As of" updated
4. **Amendments.** Every other spec the ruling changes gets a section appended, `## Amendment (YYYY-MM-DD, Tnn → Dnn)`. The body of a ruled spec is never rewritten.
5. **RUNBOOK.** Anything Rick must run becomes the new top block, exactly as he will type it; older blocks move down.
6. **Narrative.** Fill in the rulings column (and, on the laptop, the doc link).

Edits are Python read-modify-write scripts that assert each anchor occurs exactly once before replacing it. Scratch files go in `.scratch/` (gitignored), never `.claude/`.

## 7. Closing

1. `00-status.md`, last of all: the "Where things stand" table (decisions, open, last session, captures pending), the next three, and one line at the top of the session log: `- **YYYY-MM-DD (nth session)** · **Tnn → Dnn.** Read … Found … Ruled … Written …`.
2. `chronicle.md`: one entry, `## YYYY-MM-DD · Tnn, <name> → Dnn`, with paragraphs **Asked**, **Read**, **Found**, **Ruled**, **Written**, **Process**, written while the context is still in hand.
3. `transcripts/YYYY.MM.DD-tNN.md`: a header (As of, how it was rendered), then Rick's turns verbatim with timestamps, the assistant's turns abridged, tool activity in brackets.
4. Report to Rick: what was written (uncommitted), anything he must decide or run, the next three.
5. **Commit only on Rick's word.** Message: `Tnn → Dnn: <the rulings in one line>`. Author `deepily` with the GitHub noreply address (repo-local configuration; never a real email address), plus the attribution trailer. **Push only on his word**; where the shell has no GitHub credential, Rick pushes.
6. Anything destructive (deleting a file or folder, rewriting history) is asked first.

## 8. Handoff

When a session must stop before recording, write a handoff for Rick to paste as the first message of the next chat, opening `Resuming Tnn:`. It contains: the state in one line; the files touched, with branch, HEAD and whether they are tracked; the facts established; the rulings so far, one line each; what remains, in order. A new session must be able to record from it without researching again. (T22 was recorded this way across three sessions.)

## 9. Token economy

- Status page first, then only the sections named; `grep` before reading.
- Read large files by line range; never print a whole spec or the framework into the conversation.
- Public record before captures; zero-token scripts for host facts.
- Reuse a narrative's "Where the record stands" rather than searching again.
- Close with a handoff rather than run a long session into compaction.

## 10. House style (every file and every message)

- Never the section sign; write "Section 4", "Sections 4–8".
- No abbreviations in new names (`Event`, not `Ev`); engine-neutral names in new code (T38).
- A register key (D, T, C) carries its name on first use in a section; no bare mile-marker sets; tests and gates carry a word prefix saying what they prove (`Kernel-1`, `Convention-9`). C-numbers stay, because the script files carry them.
- Clocks and schedules in `app timezone` (US East Coast), never UTC.
- Kernel configuration lives in lupin's `src/conf/lupin-app.ini` and `lupin-app-splainer.ini` through the ConfigurationManager, inheriting blocks such as `[Lupin: Baseline]`, as lowercase space-separated keys (`kernel engine overage = never`). Never invent `[section] key` INI sections.
- Runbooks put the current invocation first.
- Every decision is presented as options with pros, cons and a recommendation.
- Minimal working code over prose; precise, PhD-level register; no corporate language.

## 11. Names

AH4L is the ad hoc harness for Lupin, which the kernel retires; UHW is this repo; the Lupin kernel is the host service it designs. In Rick's dictated messages, "Colonel" means the kernel and "Levine" means lupin.
