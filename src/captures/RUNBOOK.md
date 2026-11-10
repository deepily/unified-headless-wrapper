# Capture runbook

## Run this now: T25 host inventory and C20 (2026-11-10)

Two zero-token checks behind D60 (host capacity, framework Section 10.8). The inventory prints the memory budget the kernel will compute for the host, whether the persona account can make a per-persona memory scope (a live 64 MiB probe under `lupin-personas.slice`), which cgroup files the kernel offers, oomd and PSI state, the engine binaries and Node's default heap. C20 launches the engine twice with a one-word prompt and prints the process tree: leg a should show the relaunch child, leg b (`GEMINI_CLI_NO_RELAUNCH=true`) one process. Read-only; nothing of the engine's is written.

**On the test VM, as the persona account (the inventory first, then C20 on AGY):**
```bash
git pull --rebase && chmod +x src/captures/*.sh src/captures/*.py
src/captures/t25_host_inventory.sh | tee src/captures/out/t25-inventory-$( hostname )-$( date +%Y%m%d ).txt
MODEL=gemini-3.8-flash-high src/captures/c20_relaunch_tree.sh agy
```

**On the development server:** the inventory line only. **On the cloud workstation:** `src/captures/c20_relaunch_tree.sh jetski`.

**What to paste back:** the whole inventory output (it prints no secrets), and `verdict.txt` from `src/captures/out/c20-*`. The lines that matter: `budget_GiB`, `fit_at_2GiB_reserve`, `scope_probe`, `memory_peak_file`, `systemd_oomd`, `claude.file`, `node_default_heap_GiB`; and in C20 the "engine-like processes under the launched pid" count per leg.

**Heads-up:** `scope_probe: skipped` or `FAILED` on the test VM means the persona account has no user manager; `loginctl enable-linger $USER` (once, as root) is the usual fix, and until then the VM takes D60's uncapped path (`[host] class = test`).

## Then: C19 context edge (2026-11-09)

C19 confirms the public record behind D57 (context exhaustion, framework Section 11.2): the Antigravity CLI compacts on its own at a fixed ~256,000 tokens for every model and shows it as a `checkpoint` step. Leg **a** is two short turns plus a read-only look at the engine's session database for `max_context_tokens` (about one minute, two model calls); leg **b** fills the window to the ceiling (nine files of ~40k tokens, about 360k tokens in, 10–15 minutes) and ends with a recall probe. Run leg a on every D44 model first; run leg b on the flash model first, and on a D44 model only if leg a did not read its ceiling from the database.

**AGY, on the test VM, inside tmux:**
```bash
git pull --rebase && chmod +x src/captures/*.sh src/captures/*.py
MODEL=fable-5.1-high        python3 src/captures/c19_context_edge.py agy --leg a    # chief_of_staff / manager / steward / author model (D44)
MODEL=opus-5.5-high         python3 src/captures/c19_context_edge.py agy --leg a    # implementer / reviewer / tester model (D44)
MODEL=gemini-3.8-flash-high python3 src/captures/c19_context_edge.py agy --leg b    # proves the harness and the 256k stop rule cheaply
# then, only for a D44 model whose "db max_context_tokens" line above reads "not read":
MODEL=fable-5.1-high        python3 src/captures/c19_context_edge.py agy --leg b
```

**Jetski, on the cloud workstation:** the same lines with `jetski` (tokens are free there, so leg b on both D44 models is fine).

**What to paste back:** `verdict.txt` from each `out/c19-*` directory. The lines that matter: `db max_context_tokens` (→ `[context windows]` `ceiling_tokens`), `cache_read beside input` (→ the adapter's occupancy formula), `behaviour at the edge` and `recall after edge` (→ whether `pressure.compaction_action` ever needs `interrupt`, and whether silent truncation is real).

**Heads-up:** leg a copies the newest `*.db` under `~/.gemini` into the output directory and opens the copy read-only; nothing of the engine's is written. Leg b overshoots the ceiling by up to two files (~80k tokens) because the turn list is fixed; the stop rules are applied in the analysis.

## Then: T32 credential inventory (2026-11-06)

Two read-only checks behind the T32 design (framework Section 8.1): whether `~/.lupin/config` carries an `[owner]` section (the human's login, which would let a persona mint an approval), and whether any per-project hook login (`claude.code@...`) is on Lupin's approver-account map. Expected on every host: neither. Under a minute, no model turn, prints no secrets.

**Dev server (then the test VM), from the lupin virtual environment; the script finds lupin's `src` from `LUPIN_ROOT` or from the working directory:**
```bash
cd /mnt/DATA01/include/www.deepily.ai/projects/unified-headless-wrapper && git pull --rebase
cd ../lupin/src && python3 ../../unified-headless-wrapper/src/captures/t32_credential_inventory.py
```
On the test VM, adjust the first `cd` to where the checkouts live there.

**What to paste back:** the whole output. The verdict line reads `both expectations hold` or names what failed; exit 2 means the approver map could not be resolved (wrong working directory or environment).

## Then: C18 after C15–C17 (2026-11-05)

C18 measures the D49 approval loop (framework Section 8.2): a gate deny that says `call ask_wait( ticket ); then repeat this exact call`, an `ask_wait` probe that plays the human, and whether the model repeats the act so the hook can allow it once. Run once per D44 model on each engine; about 6 minutes per run (three to four turns). None of it blocks the Phase 1 build, but the five `ask` rules do not go live in Kernel-5 until the loop closes on every engine.

**AGY, on the test VM, inside tmux:**
```bash
git pull --rebase && chmod +x src/captures/*.sh src/captures/*.py
MODEL=fable-5.1-high python3 src/captures/c18_tool_approval.py agy      # chief_of_staff / manager / steward / author model (D44)
MODEL=opus-5.5-high  python3 src/captures/c18_tool_approval.py agy      # implementer / reviewer / tester model (D44)
```

**Jetski, on the cloud workstation:** the same two lines with `jetski`.

**Claude, on the dev server (D4 flags, so AH4L's user hooks stay out):**
```bash
MODEL=opus python3 src/captures/c18_tool_approval.py claude             # adds legs 3 (--tools under -p) and 4 (--permission-prompts none)
```

**What to paste back:** `verdict.txt` from each `out/c18-*` directory. The line that matters most is `loop closed` per leg; on Claude also `repeat survives --permission-prompts none`, which decides whether that flag ever ships.

**Heads-up:** the Jetski family run adds one `uhw-approval` server entry to `~/.gemini/config/mcp_config.json`, backed up and restored on exit (same mechanism as C15); the Claude run uses its own `--mcp-config` and `--settings` files under `out/`. Ticket state lives in a `mktemp` directory per leg.

## Then: C15–C17 (2026-11-03)

None of these blocks the Phase 1 build; they close T11's one open question (C15), inform D48 (C16) and T14 (C17). About 15 minutes for AGY on the test VM; the same three on Jetski whenever the cloud workstation is handy; C15b on any Claude host with AH4L installed (the dev server).

**AGY, on the test VM, inside tmux:**
```bash
git pull --rebase && chmod +x src/captures/*.sh src/captures/*.py
tmux new -s captures                                       # reattach later with: tmux attach -t captures
MODEL=gemini-3.8-flash-high python3 src/captures/c15_launch_surfaces.py agy     # about 4 min: four surfaces under --agent, auto vs accept-edits, schema-read habit
src/captures/c16_engine_update.sh agy                                            # under 2 min, no model turn: binary identity, --version cost, update hints
MODEL=gemini-3.8-flash-high python3 src/captures/c17_internal_tools.py agy      # about 8 min: 17 launches with tools denied, then one turn per surviving tool
```

**Jetski, on the cloud workstation:** the same three lines with `jetski` in place of `agy` and `MODEL=gemini-flash-next`.

**Claude, on the dev server:**
```bash
src/captures/c15b_claude_memory.sh                         # under 2 min: does ~/.claude/CLAUDE.md load under the D4 flags?
```

**What to paste back:** `verdict.txt` from each `out/c15-*`, `c15b-*`, `c16-*`, `c17-*` directory. C17 also writes `tool-map.tsv`. Then `git add src/captures && git commit -m "C15–C17 results" && git push` on your word.

**Heads-up:**
- C15 and C17 touch nothing global except the probe server entry C15 adds to `~/.gemini/config/mcp_config.json`, backed up and restored on exit (same mechanism as C11c/C14).
- C15b appends one line to `~/.claude/CLAUDE.md` and restores the file on exit; it needs `jq`.
- `CANDIDATES="code_search list_dir"` narrows C17 to specific names.

**Knobs:** `MODEL` pins `--model` (recommended; Jetski defaults to `auto`). `MCP_CONFIG` overrides the config path for C15.

---

## Done 2026-10-25: Phase 0 and the capability rounds

Results:
- AGY: `src/rnd/v0.0.1/evidence/2026.10.25-agy-capabilities-results.md`
- Jetski: `…/evidence/2026.10.18-jetski-capabilities-c11-c14-results.md`
- Claude: `…/evidence/2026.10.20-claude-round-results.md`

The Phase 1 build runs from `…/specs/2026.10.24-phase1-kernel-and-jetski-family-adapter-spec.md`.

**Status 2026-10-18.** Phase 0 (C1–C4, C9, C10) is done for AGY and Jetski. C11–C14 ran on Jetski in two rounds (results: `src/rnd/v0.0.1/evidence/2026.10.18-jetski-capabilities-c11-c14-results.md`). Claude round done 2026-10-20. **Next: the AGY round above.** Claude adapter testing is the last phase. Results docs: `src/rnd/v0.0.1/2026.10.15-phase0-part-a-agy-results.md` and `…-part-b-jetski-results.md`. The full capture list is in the framework's Section 14.

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

One command, one bundle. It measures what the planning-is-prompting layer and the voice asks need from Jetski (inventory Section 19.5).

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
| **C1 tool veto** | hook fired, `UHW_DENY_ME` call blocked, allowed call ran | see Section 5.1 before running anything else |
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

If none of these fire the hook, record "no hook route in headless mode". The fallback is the MCP-indirection veto in framework Section 14.3, and C2 and C3 still matter.

### 5.2 A run hangs

- A turn times out after 600 s, and `drive.py` always reaps its engine.
- If you press Ctrl-C, check for leftover engines:

    ```bash
    pgrep -fl -- "--input-format stream-json"      # any survivors?
    pkill -f -- "--input-format stream-json"       # clean them up
    ```

### 5.3 A turn ends empty

- An empty stdout with exit code 0 is the permission auto-deny (design doc, 10-12). The reason is in `frames.jsonl.stderr`.
- Usually it means `--dangerously-skip-permissions` was removed (see Section 5.1 step 2) without a matching allow rule.

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
- **Notes from this runbook:** which Section 5.1 step passed, the app directory, and the MCP config path.

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
| 1. names | Which model answered? Is `agentName` set? Do `parentConversationId`/`rootConversationId` mark a top-level session? | C9 numbers are per model; lineage replaces the bridge file for subagent governance (framework Section 8) |
| 2. `--agent` | Does Jetski take a named agent definition? | possible persona bootstrap route (framework Section 13) |
| 3. MCP | Where are MCP servers configured? Is the `mcpServers` format accepted? Then C3. | identity reaches cosa-voice through the inherited env (passed on AGY) |
| 4. Chrome flag | Is `--use_ls_chrome_devtools_mcp=false` accepted? | keep the default Chrome DevTools MCP server out of persona launches |

**How it behaves:**
- **Read-only, except for one file.** Section 3 adds a `uhw-probe` entry to the MCP config (default `~/.gemini/config/mcp_config.json`; override with `MCP_CONFIG=<path>`). It restores the original on exit and removes the file if it didn't exist.
- **If the format check fails,** the bundle includes `jetski mcp add --help` instead of C3. Paste it, and C3 gets switched to `mcp add`/`mcp remove`.
- **What it prints from the hook log:** only names, booleans and counts, never `lastUserInput` or payload text.

**Bring back:** `src/captures/out/jetski-followup-<timestamp>.txt`. Read it first, as in Section 6.

