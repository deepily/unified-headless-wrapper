# Capture runbook

## Run this now: nothing

No captures are pending. Phase 0 and the capability rounds are complete for AGY, Jetski and Claude. Results:
- AGY: `src/rnd/v0.0.1/2026.10.25-agy-capabilities-results.md`
- Jetski: `…/2026.10.18-jetski-capabilities-c11-c14-results.md`
- Claude: `…/2026.10.20-claude-round-results.md`

The next work is the Phase 1 build (`…/2026.10.24-phase1-kernel-and-jetski-family-adapter-spec.md`).

**Status 2026-10-18.** Phase 0 (C1–C4, C9, C10) is done for AGY and Jetski. C11–C14 ran on Jetski in two rounds (results: `src/rnd/v0.0.1/2026.10.18-jetski-capabilities-c11-c14-results.md`). Claude round done 2026-10-20. **Next: the AGY round above.** Claude adapter testing is the last phase. Results docs: `src/rnd/v0.0.1/2026.10.15-phase0-part-a-agy-results.md` and `…-part-b-jetski-results.md`. The full capture list is in the framework's §14.

Everything runs from the **repo root**. Outputs go to `src/captures/out/` (gitignored). Newest runs are at the top; completed Phase 0 instructions are kept below for reruns.

---

## Done 2026-10-24: AGY round, finished (test VM)

The 2026-10-24 run (AGY 1.4.7, non-snap) finished C11, C12, C14, C11b and C11c, then died in C14b when SSH dropped. C13 never ran.

**1. Check that the dropped run didn't leave the probe server in AGY's MCP config:**
```bash
grep -n uhw-probe ~/.gemini/config/mcp_config.json                         # no output = clean
cp src/captures/out/c14-agy-20261024T164113/mcp_config.backup ~/.gemini/config/mcp_config.json   # only if it printed a match
```
If there's no `mcp_config.backup` in that folder, the file didn't exist before the run, and `rm ~/.gemini/config/mcp_config.json` restores it.

**2. Finish inside tmux, so a dropped connection can't kill it again:**
```bash
git pull                                                   # scripts now restore the config even on a dropped connection
tmux new -s agy                                            # reattach later with: tmux attach -t agy
WAITS=200 MCP_TIMEOUT_MS=900000 python3 src/captures/c14_mcp_wait.py agy                # C14b, about 4 min
UHW_RULES=v2 MODELS="opus-5.5-high gemini-3.8-flash-high gemini-launch-candidate-high gemini-flash-next" \
    src/captures/c13_pinned_model.sh agy                                                # C13, about 40 min
git add src/captures && git commit -m "AGY round results (non-snap)" && git push
```

## Done 2026-10-20: Claude round (Linux dev server)

```bash
git pull && chmod +x src/captures/*.sh src/captures/*.py
export LUPIN_ROOT=~/projects/lupin                          # your lupin checkout on the server; C5 reads its hooks file
src/captures/claude_round.sh                               # about 25 min: C5, C6, C7, then format probe v2 on Claude Code and AGY
git add src/captures && git commit -m "Claude round results" && git push
```

**What it does:**
- **C5:** do the launch flags keep AH4L's user-scope hooks out of a headless Claude?
- **C6:** does a `control_request` interrupt leave the process alive?
- **C7:** is a message written mid-turn absorbed, queued or dropped?
- **Format probe v2:** one sentence per line, a 20-word ceiling, one line allowed. Three repeats on Claude Code (`opus`), then on AGY for comparison.

**Heads-up:**
- C5's first probe (A) is a real AH4L session, so a notification listener may start and you may hear an "anything else?".
- `jq` must be installed.

**Knobs:**
- `CLAUDE_MODEL=sonnet` changes the Claude model.
- `SKIP_AGY=1` skips the AGY comparison.

**Bring back:** nothing to paste. Push, and tell me; I read the results from your MacBook checkout after you pull there.

## Done 2026-10-18: Jetski round 3 (work laptop)

```bash
git pull && chmod +x src/captures/*.sh src/captures/*.py
src/captures/c11c_final.py jetski                          # round 3, about 5 min
git add src/captures/out && git commit -m "Round 3 capture results" && git push
```

**What it checks:**
- global skills in `~/.gemini/config/skills/`
- rules with `trigger: always_on` / `model_decision`
- Jetski's default tool list
- which agent `tools:` list reaches the cosa-voice MCP server (`[call_mcp_tool]` alone, or plus `read_file`)

**Bring back:** nothing to paste; the `.gitignore` keeps only `verdict.txt` and `facts.json`, and leaves the MCP config backup and raw logs local.

## Done 2026-10-18: round 2 (`src/captures/capabilities_round2.sh jetski`)

C13 was skipped in the first run (the script predated the model defaults), and C11/C14 raised three questions. 
| Part | Question |
|---|---|
| C11b | How does `/workflow` run when tools are allowed (C11 denied `run_workflow`)? Which slash commands are offered? Where do *global* skills live (`~/.gemini/jetski/skills`, `~/.agents/skills`, `~/.agent/skills`)? Which agent-definition frontmatter grants tools? Field names from Jetski's builtin customization docs (headings and `key:` lines only; skim section D of the bundle before pasting if that matters at work). |
| C14b | One 200 s MCP call with `"timeout": 900000` on the server entry: is the 180 s limit configurable? |
| C13 | Pyramid format on `opus-5.5-high`, `gemini-3.8-flash-high`, `gemini-launch-candidate-high`, `gemini-flash-next` (`MODELS=…` overrides, `MODELS=none` skips). |

## Done 2026-10-18: C11–C14 (work laptop)

One command, one bundle. It measures what the planning-is-prompting layer and the voice asks need from Jetski (inventory §19.5).

```bash
git pull                                                   # wip-v0.0.1-2026.10.15-planning-prep
chmod +x src/captures/*.sh src/captures/*.py              # new files may arrive without the executable bit
jetski models                                              # model ids; `auto` = Gemini Pro Next
src/captures/capabilities_followup.sh jetski              # about 65 min: C11, C12, C14, then C13 on four models
```

| Capture | Question | What it does |
|---|---|---|
| C11 surfaces | Does Jetski load rules files, custom commands, skills and agent definitions itself? | Plants a unique codeword in each candidate location (project `GEMINI.md`, `AGENTS.md`, `CLAUDE.md` as a control, `.agents/rules`, `.agents/workflows`, `.gemini/commands/*.toml`, `.agents/skills`, `.agents/agents`, and global `~/.gemini/…`), then asks for codewords with **every tool denied by the hook**. Also lists `jetski agents` and runs `--agent` for each planted definition. |
| C12 subagents and plan mode | What is the subagent tool called, do project hooks fire inside subagents, can a hook veto it by name? What does `--mode plan` do across "create a file" then "approved"? | Three short runs in throwaway repos. |
| C13 pinned model | Do C9/C10 hold on the persona model, not `auto`? | Confirms `--model` reached the hook payload, then runs the pyramid probe 3 times and saves every reply's spoken lines. |
| C14 long MCP calls | Will Jetski wait 45 s, 200 s, 620 s for one MCP call (a voice ask waiting on a human)? | One process, three calls to the probe's `wait_seconds` tool; logs answers, cancellations and server EOF. |

**How it behaves:**
- **Global files are planted only where nothing exists,** and removed on exit, Ctrl-C included. An existing `~/.gemini/GEMINI.md` or `AGENTS.md` is left untouched and reported as "not tested".
- **C14 edits the MCP config** like C3: backed up and restored on exit.
- **What it records from your machine:** `~/.gemini` file *names* matching agent/skill/command/rule, and the *keys* (never values) of up to four definition files; the first 30 lines of `jetski agents`; `--help` lines. No hook payload text, so `lastUserInput` stays out of the bundle.
- **C13 models (default):** `opus-5.5-high` (same model as Claude Code: isolates the harness), `gemini-3.8-flash-high` (same model as AGY in Part A: isolates the binary), `gemini-launch-candidate-high` (strongest Gemini; manager and reviewer candidate), `gemini-flash-next` (fast tier; worker candidate). About 10 minutes each.
- **Knobs:** `MODELS="a b"` replaces the four; `MODELS=none` skips C13; `SKIP_WAIT=1` skips C14 (about 15 min); `WAITS="30 90"` changes its durations; `MODEL=<name>` pins C11, C12 and C14 too (otherwise they run on `auto`).

**Bring back:** `src/captures/out/jetski-capabilities-<timestamp>.txt`. AGY can run the same thing on the Linux server for comparison: `src/captures/capabilities_followup.sh agy`.

## Quick reference

| Task | Command |
|---|---|
| AGY round (current) | `src/captures/agy_round.sh` |
| Claude round | `LUPIN_ROOT=… src/captures/claude_round.sh` |
| Round 3 | `src/captures/c11c_final.py jetski` |
| Round 2 | `src/captures/capabilities_round2.sh jetski` |
| C11–C14 | `src/captures/capabilities_followup.sh jetski` (four default models; `MODELS=none` skips C13) |
| One of them | `src/captures/c11_surfaces.py jetski` (same for c12, c14); `MODELS=… src/captures/c13_pinned_model.sh jetski` |
| Everything for one engine | `src/captures/run_engine.sh agy\|jetski` |
| Part B follow-up | `src/captures/jetski_followup.sh jetski` |
| One capture | `src/captures/c1_tool_veto.sh jetski` (same pattern for c2, c4) |
| C3 | `MCP_CONFIG=<path> src/captures/c3_mcp_identity.sh jetski` |
| Format probe only | `UHW_LABEL=jetski src/captures/c9_c10_pyramid_probe.py --family jetski -- jetski --input-format stream-json --output-format stream-json --dangerously-skip-permissions` |
| Other hooks shape | `HOOKS_FORMAT=B src/captures/c1_tool_veto.sh jetski` |
| More repeats | `REPEAT=3 src/captures/run_engine.sh jetski` |
| AGY only | add `--print-timeout 0` to any manual engine command (the scripts do this already) |

---

# Completed: Phase 0, Part A (AGY) and Part B (Jetski)

Kept for reruns. Section numbers are the ones the Phase 0 results docs cite.

## 1. Before you leave (on the home machine)

```bash
git add src/captures src/rnd/v0.0.1 && git commit -m "Phase 0 capture scripts and runbook" && git push
```

## 2. Preflight (on each machine, about 2 minutes)

```bash
cd <repo root> && git pull                            # the unified-headless-wrapper checkout on this machine
ENGINE=agy                                            # Part A: agy · Part B: jetski
ls src/captures/run_engine.sh                         # fails = not pulled, or not at the repo root
chmod +x src/captures/*.sh src/captures/*.py          # git keeps the bit, but cheap insurance
command -v python3 && python3 --version               # 3.9+; standard library only, no venv needed
command -v "$ENGINE" && "$ENGINE" --version < /dev/null
ls -d ~/.gemini/*/                                    # app directories: note the one for this engine
```

| Check | Expected | If not |
|---|---|---|
| `python3` | 3.9 or newer | install, or put a newer one first on PATH |
| engine on PATH | a path prints | find the binary and add its directory to PATH for this shell |
| app directory | AGY: `~/.gemini/antigravity-cli/`; Jetski: one of the dirs listed | note it; you need it for C3 and for the fallbacks below |
| engine signed in | a one-line `-p "say hi"` answers | sign in first; every capture assumes a working engine |

Quick smoke test (about 5 s; it should print a sentence):

```bash
"$ENGINE" -p "say hi"
```

## 3. Run

```bash
src/captures/run_engine.sh jetski          # Part B   (Part A: agy)
```

This runs C1, C2, C4 and C9/C10 unattended, typically a few minutes. C3 is skipped on this pass, but it records the MCP-related `--help` lines.

**C3 next.**

1. Find the MCP config file. On AGY 1.3.5 it is `~/.gemini/config/mcp_config.json` (confirmed 10-15). It's empty when no servers are configured, and `agy mcp add|remove|list` manages it. Jetski probably uses the same path, so check that first.
2. Confirm the format in 10 seconds: write the probe entry, list it, restore the file.

    ```bash
    F=~/.gemini/config/mcp_config.json; cp "$F" /tmp/mcp_config.backup
    python3 - "$F" "$PWD/src/captures/probe_mcp.py" <<'EOF'
    import json, sys
    path, probe = sys.argv[ 1: ]
    json.dump( { "mcpServers": { "uhw-probe": { "command": sys.executable, "args": [ probe ] } } }, open( path, "w" ), indent=1 )
    EOF
    "$ENGINE" mcp list                     # uhw-probe listed as stdio/enabled = format is right
    cp /tmp/mcp_config.backup "$F"
    ```

3. Run:

    ```bash
    MCP_CONFIG=~/.gemini/config/mcp_config.json src/captures/c3_mcp_identity.sh jetski
    ```

The script backs the file up into its output directory and restores it on exit, even if it fails. If the file doesn't exist, it's created and removed afterwards.

**Optional, for steadier format numbers:**

```bash
REPEAT=3 src/captures/run_engine.sh jetski
```

## 4. Read the verdicts

Each capture prints its verdict lines and writes `verdict.txt` and `facts.json` to its own directory, `src/captures/out/<capture>-<engine>-<timestamp>/`.

| Capture | PASS means | Anything else |
|---|---|---|
| **C1 tool veto** | hook fired, `UHW_DENY_ME` call blocked, allowed call ran | see §5.1 before running anything else |
| C2 tool names | `tool-map.tsv` lists a name and argument keys per tool | PARTIAL (stream names only) is still useful: hooks didn't fire |
| C3 MCP identity | each of two concurrent servers sees its own `persona-N` tag | PARTIAL: identity must go through a config file per persona; record which lines said yes |
| C4 conversation id | the requested id came back and the resume recalled PELICAN | PARTIAL is fine: the harness reads the id from `init` instead |
| C9/C10 | a compliance count and a median gap | there is no failing value; it's data |

## 5. When something goes wrong

### 5.1 C1 says "hook never fired"

Try these in order. Stop at the first that passes and note which one it was.

1. **The other hooks.json shape:**

    ```bash
    HOOKS_FORMAT=B src/captures/c1_tool_veto.sh jetski
    ```

2. **The permission bypass may also skip hooks.** Back up `~/.gemini/<app>/settings.json`, then add a static allow rule for the shell tool, for example:

    ```json
    { "permissions.allow": [ "run_command" ] }
    ```

    AGY's own `settings.json` lists plain tool names (`"write_file"`), and C2 named the shell tool `run_command`. Jetski may differ. This fallback was not needed on AGY: C1 passed with format A and the flag on. Then rerun C1 with the flag removed:

    ```bash
    sed -i.bak 's/ --dangerously-skip-permissions//' src/captures/common.sh   # undo afterwards: mv src/captures/common.sh.bak src/captures/common.sh
    ```

    **Restore `settings.json` when you're done.**

3. **Global hooks file instead of project level.** Copy `out/c1-*/hooks.json` into `~/.gemini/<app>/hooks.json` (back up any existing one first), rerun C1, then restore.

If none of these fire the hook, record "no hook route in headless mode". The fallback is the MCP-indirection veto in framework §14.3, and C2 and C3 still matter.

### 5.2 A run hangs

- A turn times out after 600 s, and `drive.py` always reaps its engine.
- If you press Ctrl-C, check for leftover engines:

    ```bash
    pgrep -fl -- "--input-format stream-json"      # any survivors?
    pkill -f -- "--input-format stream-json"       # clean them up
    ```

### 5.3 A turn ends empty

- An empty stdout with exit code 0 is the permission auto-deny (design doc, 10-12). The reason is in `frames.jsonl.stderr`.
- Usually it means `--dangerously-skip-permissions` was removed (see §5.1 step 2) without a matching allow rule.

### 5.4 C3 left your MCP config modified

This should be impossible because restore runs on exit, but the backup is always at `src/captures/out/c3-*/mcp_config.backup`:

```bash
cp src/captures/out/c3-jetski-<ts>/mcp_config.backup <your MCP_CONFIG path>
```

### 5.5 C3 says "no server started"

- The config file is probably not the one the engine reads, or the server key is wrong. Check the discovery lines and look for another file name under the app directory (`mcp*.json`, or `settings.json` with an `mcpServers` key).
- The probe server also writes to `/tmp/uhw-mcp-probe.jsonl` when it can't find its log path. If that file exists, the server did start.

## 6. What to bring back

- **One file per part:** `src/captures/out/<engine>-bundle-<timestamp>.txt`, plus the C3 `verdict.txt` if you ran C3 separately.
- **Notes from this runbook:** which §5.1 step passed, the app directory, and the MCP config path.

**Before pasting anything from the work laptop, read the bundle.**

| Contains | Does not contain |
|---|---|
| hook payloads | tokens |
| tool names (including internal ones such as `code_search`) | credentials |
| local paths | the environment, beyond seven exact names: `UHW_PROBE_TAG`, `UHW_PROBE_BLOCK`, `UHW_PROBE_EXPANDED`, `LUPIN_PERSONA_ID`, `CLAUDE_SESSION_ID`, `CLAUDE_PROJECT_DIR`, `PWD` |
| the model's replies to the probe prompts | |

Redact anything your work policy says shouldn't leave the laptop. The verdict lines alone carry most of the value.

## 7. Cleanup

```bash
rm -rf src/captures/out/*          # results, once you've pasted them
rm -rf "${TMPDIR:-/tmp}"/tmp.*     # throwaway workspaces from mktemp; check the listing before deleting
```

## 8. Part B follow-up (work laptop)

One command finishes Part B. It answers the four questions the first Jetski bundle left open and writes one file to paste back.

```bash
git pull                                              # wip-v0.0.1-2026.10.15-planning-prep
ls src/captures/jetski_followup.sh                    # must exist
src/captures/jetski_followup.sh jetski                # about 1–2 minutes; needs the earlier C1 output in src/captures/out/
```

| Bundle section | Question | Why it matters |
|---|---|---|
| 1. names | Which model answered? Is `agentName` set? Do `parentConversationId`/`rootConversationId` mark a top-level session? | C9 numbers are per model; lineage replaces the bridge file for subagent governance (framework §8) |
| 2. `--agent` | Does Jetski take a named agent definition? | possible persona bootstrap route (framework §13) |
| 3. MCP | Where are MCP servers configured? Is the `mcpServers` format accepted? Then C3. | identity reaches cosa-voice through the inherited env (passed on AGY) |
| 4. Chrome flag | Is `--use_ls_chrome_devtools_mcp=false` accepted? | keep the default Chrome DevTools MCP server out of persona launches |

**How it behaves:**
- **Read-only, except for one file.** Section 3 adds a `uhw-probe` entry to the MCP config (default `~/.gemini/config/mcp_config.json`; override with `MCP_CONFIG=<path>`). It restores the original on exit and removes the file if it didn't exist.
- **If the format check fails,** the bundle includes `jetski mcp add --help` instead of C3. Paste it, and C3 gets switched to `mcp add`/`mcp remove`.
- **What it prints from the hook log:** only names, booleans and counts, never `lastUserInput` or payload text.

**Bring back:** `src/captures/out/jetski-followup-<timestamp>.txt`. Read it first, as in §6.

