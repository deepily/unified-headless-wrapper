# Capture runbook: AGY (Part A) and Jetski (Part B)

How to run the Phase 0 captures on each machine, read the results, recover from the likely failures, and what to bring back. Background and the full capture list are in `src/rnd/v0.0.1/2026.10.14-uhw-implementation-planning-framework.md` §14.

Everything below runs from the **repo root**. Outputs go to `src/captures/out/` (gitignored).

---

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

1. Find the MCP config file. On AGY 1.3.3 it is `~/.gemini/config/mcp_config.json` (confirmed 10-15). It's empty when no servers are configured, and `agy mcp add|remove|list` manages it. Jetski probably uses the same path, so check that first.
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
    { "permissions.allow": [ "command(*)" ] }
    ```

    The rule syntax is unconfirmed; the design doc only saw `"permissions.allow"` as a flat dotted key. Then rerun C1 with the flag removed:

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
| local paths | the environment, beyond `UHW_*`, `LUPIN_*`, `CLAUDE_SESSION_ID`, `CLAUDE_PROJECT_DIR`, `PWD` |
| the model's replies to the probe prompts | |

Redact anything your work policy says shouldn't leave the laptop. The verdict lines alone carry most of the value.

## 7. Cleanup

```bash
rm -rf src/captures/out/*          # results, once you've pasted them
rm -rf "${TMPDIR:-/tmp}"/tmp.*     # throwaway workspaces from mktemp; check the listing before deleting
```

## Quick reference

| Task | Command |
|---|---|
| Everything for one engine | `src/captures/run_engine.sh agy\|jetski` |
| One capture | `src/captures/c1_tool_veto.sh jetski` (same pattern for c2, c4) |
| C3 | `MCP_CONFIG=<path> src/captures/c3_mcp_identity.sh jetski` |
| Format probe only | `UHW_LABEL=jetski src/captures/c9_c10_pyramid_probe.py --family jetski -- jetski --input-format stream-json --output-format stream-json --dangerously-skip-permissions` |
| Other hooks shape | `HOOKS_FORMAT=B src/captures/c1_tool_veto.sh jetski` |
| More repeats | `REPEAT=3 src/captures/run_engine.sh jetski` |
| AGY only | add `--print-timeout 0` to any manual engine command (the scripts do this already) |
