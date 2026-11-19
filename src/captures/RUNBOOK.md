# Capture runbook

## Done 2026-11-18: which lupin tree serves which port on the test VM, and the two standing checks of row 96, zero tokens. Nothing here is owed

**Result** (the row 96 session, 2026-11-18 13:28 US Eastern; `src/captures/out/t19-lupin-trees-lupin-host-test-20261118.txt`): ports 7999 and 8000 are two containers of one image with one code mount, `/mnt/lupin-data/lupin/src`; that tree's only remote is a bundle file; 60 GB free. Read in the T19 spec's amendment of 2026-11-18.

**On the test VM, at any later time** (read-only: `docker ps`, `docker inspect`, `git -C`, `df`, `du`, `grep`; it prints no environment value):
```bash
cd /mnt/lupin-data/unified-headless-wrapper && git pull --rebase
src/captures/t19_lupin_trees_test_vm.sh
```

**The two checks, on any host with this checkout** (each exits 1 with a line saying why):
```bash
src/captures/t19_move_reading_sweep.py --check       # every lower-case "the move" has a reading; run at every recording
src/rnd/v0.0.1/charts/check_phase_chart.py           # the phase chart is drawn from the record as it stands; run at every close
src/rnd/v0.0.1/charts/check_phase_chart.py --self-test
```

When the chart's check fails: edit `src/rnd/v0.0.1/charts/build_phase_chart.py`, then from `src/rnd/v0.0.1/charts/` run `python3 build_phase_chart.py build-phases-and-drivers.html build-phases-and-drivers.svg`, and set `SOURCES_DIGEST` in the generator to what `check_phase_chart.py --digest` prints.

## Done 2026-11-17: the Phase 1 builder's clone made on the test VM, zero tokens (rows 87 and 91). Nothing here is owed; the `--check` line below is for any later time

**Result** (the row 87 session, 2026-11-17 22:45 US Eastern): the clone is at `/mnt/lupin-data/unified-headless-wrapper-builder`, at `d9a81f9`, fourteen checks `ok`.

**As it was run on the test VM**, from planning's checkout (on another host, the same three lines):
```bash
cd /mnt/lupin-data/unified-headless-wrapper && git pull --rebase && chmod +x src/captures/*.sh
src/captures/t19_builder_clone_setup.sh --self-test
src/captures/t19_builder_clone_setup.sh /mnt/lupin-data/unified-headless-wrapper-builder
```

The last line clones the branch from GitHub, leaves the root `CLAUDE.md` and `AGENTS.md` out of the new tree by sparse checkout, writes the one-line `CLAUDE.local.md` that imports `src/rnd/v0.0.1/03-builder-loader.md`, and prints fourteen checks, each `ok`. It refuses a path that exists and deletes nothing. It must run after the push, because the loader's text reaches the clone from the remote.

**At any later time**, to see that the clone has not drifted (exit 1 and a `FAILS` line if it has):
```bash
/mnt/lupin-data/unified-headless-wrapper/src/captures/t19_builder_clone_setup.sh --check /mnt/lupin-data/unified-headless-wrapper-builder
```

**Done 2026-11-17, nothing owed:** `src/captures/t19_builder_clone_check.sh` (the host's facts and the three mechanisms tried in a temporary folder; `src/captures/out/t19-builder-clone-check-lupin-host-test-20261117.txt`; read in the row 87 narrative).

## Done 2026-11-17: what the surviving files take from the Python files deleted outside the hooks tree, zero tokens (row 76). Nothing here is owed

**Result** (a UHW session on the test VM, lupin at `27e646d0ed`; `src/captures/out/t19-outside-import-symbols-lupin-host-test-20261117.txt` before the rows, `…-after-rows.txt` after; `t19-hook-import-survivors-lupin-host-test-20261117-after-row76.txt`; `t19-inventory-lupin-host-test-20261117-after-row76.txt`; read in the row 76 narrative and the T19 spec's amendment of 2026-11-17, row 76): before the rows, 15 unmapped surviving files held 35 imports of 12 deleted files. After them the inventory has 193 rows, none unknown; the check exits 1, with 34 surviving files importing a deleted tree module and 16 importing 17 of the 63 Python files the list deletes or renames outside the tree. It stays 1 until lupin changes (rows 75 and 80 of "Outstanding actions").

**On any host with a lupin checkout** (optional on the development server; it is the same branch):
```bash
git pull --rebase && chmod +x src/captures/*.sh
src/captures/t19_outside_import_symbols.sh --self-test && src/captures/t19_hook_import_survivors.sh --self-test
src/captures/t19_outside_import_symbols.sh ../lupin | tee src/captures/out/t19-outside-import-symbols-$( hostname )-$( TZ=America/New_York date +%Y%m%d ).txt
src/captures/t19_hook_import_survivors.sh ../lupin --check | tee src/captures/out/t19-hook-import-survivors-$( hostname )-$( TZ=America/New_York date +%Y%m%d ).txt
```

The first script lists, for each deleted or renamed file, every import of it by a surviving file with the names taken and the size of each. The second is the Delete clock's condition; a Python file with a Rename row now counts as removed at its old path.

## Done 2026-11-17: what the surviving files take from the hooks tree, and the widened Delete check, zero tokens (row 66). Nothing here is owed

**Result** (a UHW session on the test VM, lupin at `27e646d0ed`; `src/captures/out/t19-survivor-import-symbols-lupin-host-test-20261117.txt` before the rows, `…-after-rows.txt` after; `t19-hook-import-survivors-lupin-host-test-20261117-after-row66.txt`; `t19-inventory-lupin-host-test-20261117.txt`; read in the row 66 narrative and the T19 spec's amendment of 2026-11-17): before the rows, 44 surviving files and 2 kept tree modules imported 14 deleted modules in 70 statements. After them the inventory has 184 rows, none unknown; the check exits 1, with 34 surviving files importing a deleted tree module and 18 importing a Python file deleted outside the tree. It stays at 1 until lupin changes.

**On any host with a lupin checkout** (optional on the development server; it is the same branch):
```bash
git pull --rebase && chmod +x src/captures/*.sh
src/captures/t19_survivor_import_symbols.sh --self-test && src/captures/t19_hook_import_survivors.sh --self-test
src/captures/t19_survivor_import_symbols.sh ../lupin | tee src/captures/out/t19-survivor-import-symbols-$( hostname )-$( TZ=America/New_York date +%Y%m%d ).txt
src/captures/t19_hook_import_survivors.sh ../lupin --check | tee src/captures/out/t19-hook-import-survivors-$( hostname )-$( TZ=America/New_York date +%Y%m%d ).txt
```

Read-only. The first prints, per deleted module, each import statement of a surviving file (class, line, top of file or inside a function, guarded or not, the names taken and how often each is read), then the Python files deleted outside the tree that a survivor imports. The second is the Delete clock's condition, now also reading the kept tree modules and those outside files.

## Done 2026-11-16: what a re-read of the settings file costs, zero tokens (row 60). Nothing here is owed

**Result** (a UHW session on the test VM, lupin at `27e646d0ed`; `src/captures/out/t15-configuration-reread-lupin-host-test-20261116.txt`; read in the row 60 narrative, "Where the record stands"): `lupin-app.ini` is 2,750 lines, six blocks, 967 distinct keys, 51 of them defined in more than one block, no `kernel …` key yet; one `stat` 0.003 ms, one whole ConfigurationManager build 17.5 ms, 22.6 ms with the key dictionary; `init()` refreshes in place with no flag, drops launch overrides unless they are passed again, and prints 26 lines unless silenced.

**On any host with a lupin checkout and its `.venv`** (optional on the development server; only the timings would differ):
```bash
git pull --rebase && chmod +x src/captures/*.sh
src/captures/t15_configuration_reread.sh ../lupin | tee src/captures/out/t15-configuration-reread-$( hostname )-$( TZ=America/New_York date +%Y%m%d ).txt
```

Read-only on the checkout; the manager's behavior is probed on a fixture in a temporary folder. A second argument names the block (default `Lupin: Development`).

## Done 2026-11-16: the files that survive the Delete and import what it removes, zero tokens (row 28). Nothing here is owed

**Result** (a UHW session on the test VM, lupin at `27e646d0ed`; `src/captures/out/t19-hook-import-survivors-lupin-host-test-20261116.txt`, and `…-after-rows.txt` once the list had its new rows): 60 files outside `src/lupin_cli/claude_code` import it; the list deletes 14; 44 of the 46 survivors import a module the Delete removes. Read in `src/rnd/v0.0.1/narratives/2026.11.16-row28-switch-over-list-two-rows.md`.

**On any host with a lupin checkout** (optional on the development server; it is the same branch):
```bash
git pull --rebase && chmod +x src/captures/*.sh
src/captures/t19_hook_import_survivors.sh --self-test
src/captures/t19_hook_import_survivors.sh ../lupin | tee src/captures/out/t19-hook-import-survivors-$( hostname )-$( TZ=America/New_York date +%Y%m%d ).txt
```

**At the Delete clock** (exits non-zero while a Delete row is present, a Keep row is gone, or a surviving file imports a deleted module): `src/captures/t19_switch_over_inventory.sh ../lupin --clock delete`. The survivors' condition alone: `src/captures/t19_hook_import_survivors.sh ../lupin --check`.

## Done 2026-11-16: the T16 account reach on the development server, zero tokens (row 39). Nothing here is owed

**Result** (Rick, commit `d541d8b`; `src/captures/out/t16-account-reach-dual-rtx-4090s-20261116.txt`; read in the row 39 narrative, "What the host check found"): `rruiz` is user 1001 and owns the checkouts and the containers' writable mounts; its home holds Google, GitHub, SSH, registry and engine sign-ins; the development container mounts the Google sign-in folder read-only and the test container does not; no LXD socket exists; a libvirt socket does, not writable by `rruiz`; the projects folder is mode 744 and `~/.lupin` 775.

The narrative for the unprivileged account (`src/rnd/v0.0.1/narratives/2026.11.16-row39-unprivileged-account.md`) rests on four facts about the development server that were read from a compose file on the test VM, or inferred, and not from the host: the numeric identifier of `rruiz`; which kinds of credential sit in its home; what the running containers mount from that home and which user they run as; whether the LXD socket is live. This script reads them. It makes no model call, writes nothing, and prints paths, names, modes and counts, never a file's content.

**On the development server, as `rruiz`:**
```bash
git pull --rebase && chmod +x src/captures/*.sh
src/captures/t16_account_reach.sh ../lupin | tee src/captures/out/t16-account-reach-$( hostname )-$( TZ=America/New_York date +%Y%m%d ).txt
```

Run from this repository's root; `../lupin` is the lupin checkout beside it (give its path if it is elsewhere). A few seconds.

**What to paste back (or commit and push):** the whole output. The lines that decide things: under (a), `uid_gid`, the login accounts and the group members; under (b), which credential paths are present; under (c), which sockets read `writable=yes`; under (d), each container's `user | privileged` line and its `from this home or a socket` lines; under (e), `lupin_checkout_owner` and the user units.

**Read the output with these limits in mind:** (b) checks a fixed list of twenty paths, so a credential kept elsewhere is not seen; (d) lists running containers only; the script was run once on the test VM as a shakedown (`src/captures/out/t16-account-reach-lupin-host-test-20261116.txt`) and has not run on the development server.

---

## Done 2026-11-16: the T16 account inventory on the development server, zero tokens (row 20). Nothing here is owed; a rerun with the repaired script is optional

**Result** (Rick, commit `40b2916`; `src/captures/out/t16-account-inventory-dual-rtx-4090s-20261116.txt`; read in the T16 spec's last amendment): the fleet runs as `rruiz`, in `docker` and `lxd`, with no passwordless `sudo` but for one named program; 703 direct `docker` calls and about 233 script runs driving Docker on the host in 30 days, `sudo` unused; thirteen repositories, none group-shared, none needing a mode repair. The script was repaired afterwards (remote shells marked, worktree copies merged, a misread redirection); the block below is as it was run.

D59 (the fleet) part 9 puts the kernel and the engines under a dedicated account with no `sudo` and no `docker` membership on a production host, at the switch-over. This inventory sizes that account's two known costs before any detail is ruled: the repositories that must become group-writable, and the short `sudoers` list for the scripts that drive Docker. It reads the account's groups and `sudo` rules, the last 30 days of the old harness's hook logs and of the Claude transcripts under `~/.claude/projects`, and the owner and mode of every `.git` the fleet works in. It writes nothing, makes no model call, and prints program names, subcommands, script paths and counts, never a command line. Run it **as the account the fleet runs under**. The test VM's run (a shakedown; no fleet runs there) took 15 seconds: `src/captures/out/t16-account-inventory-lupin-host-test-20261116.txt`.

**On the development server:**
```bash
git pull --rebase && chmod +x src/captures/*.sh src/captures/*.py
src/captures/t16_account_inventory.sh --self-test
src/captures/t16_account_inventory.sh ../lupin | tee src/captures/out/t16-account-inventory-$( hostname )-$( TZ=America/New_York date +%Y%m%d ).txt
```

Run from this repository's root; `../lupin` is the lupin checkout beside it (give its path if it is elsewhere). A second argument changes the window (`… ../lupin 60`); any further arguments name repositories to list that neither the records nor `lupin-app.ini` reach.

**What to paste back (or commit and push):** the whole output. The lines that decide things: under (a), `groups`, the `sudo` rules and `members_of_docker`; under (b), the two "called directly" lists, the two lists of scripts whose own text calls `sudo` or `docker`, and the table of lupin scripts with its two run counts (a script with runs is a candidate for the `sudoers` list; a script with none is not); under (c), each repository's `.git owner:group mode`, `core.sharedRepository` and its "not group-writable" count; then the `summary` block. If the hook-log section reads `ABSENT` or zero calls, say where the hook logs are on that host (`LUPIN_HOOK_LOG_DIR=<directory>` before the command reads them there).

**Read the output with these limits in mind:** a call hidden behind a variable or an alias is not seen; the lupin table lists shell scripts only, so a Python test driver that starts a container shows under "scripts run" but not in the table; the transcripts are every Claude session of that account, the operator's own included.

Still owed from the blocks below: the T38 naming inventory, the T36 identity inventory and the T35 persona-name inventory on the development server, the T22 engine-account inventory on both hosts, C20 and the T31 dry run on the test VM, the T19 inventory on both hosts.

---

## Done 2026-11-16 on both engines: `manage_task`'s argument names, one turn each (row 53, `Tools-6`). Nothing here is owed; the next owed block is the T38 inventory below

D74 (the engines' built-in tools) gives the gate a shape for `manage_task`, the background-task tool, with argument names that are provisional (`Action`, `TaskId`, `Input`): the names the tool is declared with, not names read from a hook. This run reads them from a hook. **It is not a zero-token capture:** one launch and one turn on the flash model per engine, in which the model backgrounds a command with `run_command`, then lists it, reads its status, sends it a line and kills it. C17's script was repaired the same day; `PARTS=C` runs this part alone. If the model skips a step, the verdict says `INCOMPLETE` and names the missing action, and the run is repeated.

**Result on AGY 1.5.9 (test VM, 2026-11-16, Rick, `src/captures/out/c17-agy-20261116T221136/`):** all four actions called in the one turn and seen by the hook; `Action`, `TaskId`, `Input` agree with the provisional constants; the task identifier is `<conversation identifier>/task-<n>`; nothing left running. In the T14 spec, Section 13.

**On the test VM (AGY), done; kept for a later engine version:**
```bash
cd /mnt/lupin-data/unified-headless-wrapper && git pull --rebase
PARTS=C MODEL=gemini-3.8-flash-high python3 src/captures/c17_internal_tools.py agy
```

**Result on Jetski 2026.11.16 (cloud workstation, 2026-11-16, Rick, `src/captures/out/c17-jetski-20261116T221903/`):** the same: all four actions, seen by the hook, the three names agree. The engine had updated itself from 2026.11.13 at the capture's version call. In the T14 spec, Section 13 and its amendment.

**On the cloud workstation (Jetski), done; kept for a later engine version:**
```bash
git pull --rebase
PARTS=C MODEL=gemini-flash-next python3 src/captures/c17_internal_tools.py jetski
```

**What to paste back (or commit and push):** `verdict.txt` and `results-manage-task.tsv` from the new `src/captures/out/c17-<engine>-<time>/` directory (both are tracked, with `facts.json`). The lines that decide things: the three `C. … provisional …` lines (`agrees`, `DIFFERS` or `not observed`), `C. all four actions seen`, and `C. calls the hook saw` (if `manage_task` is absent there but present in `C. calls the driver saw in the frames`, the hook does not see the tool, which is itself a finding for the gate). A `DIFFERS` line means the constants in `builtin_tools.py` (T14 spec, Section 10) are corrected by the next session.

**Optional, zero tokens, on the cloud workstation only** (its frames never left that host): the repaired verdict of the 11-16 Jetski run, recomputed from its recorded files without starting an engine.
```bash
python3 src/captures/c17_internal_tools.py jetski --replay src/captures/out/c17-jetski-20261116T193513
```
The AGY run's is in: `src/captures/out/c17-agy-20261116T192214/replay/verdict.txt` (two delivered, two aliases, one launch error, five not delivered; 27 launches printing one 60-name list), which is the count the T14 spec's Section 2 states.

**The whole capture again** (not owed; up to 33 short turns): omit `PARTS`. Part B now repeats a turn with the name alone when the launch beside `read_file` fails, which is the only way to see what `view_file` delivers.

## Then: the T38 naming inventory on the development server, zero tokens (2026-11-15)

D71 (engine-neutral naming) renames what says `cc` or `claude_code` where a persona is meant, family by family, and puts a ratchet on what is left. The test VM's reading is in (`src/captures/out/t38-naming-lupin-host-test-20261115.txt`, lupin `aabadd221`: 1,498 surviving occurrences in 184 code files, 636 more in files the switch-over list deletes, 87 configuration keys). The development server's checkout may be at a later commit and its `lupin-app.ini` is the production one, so its count is the one the ratchet's ceiling will be taken from at the Switch.

**On the development server:**
```bash
git pull --rebase && chmod +x src/captures/*.sh src/captures/*.py
src/captures/t38_naming_inventory.sh <path to the lupin checkout on the development server> | tee src/captures/out/t38-naming-$( hostname )-$( TZ=America/New_York date +%Y%m%d ).txt
```

**What to paste back (or commit and push):** the whole output. The lines that decide things: `lupin_head`, `configuration_file`, the `survivors` line, the count under `surface 1`, and the block `rename families`. Add `--names` for every distinct name. Later, in lupin, the ratchet is the same script with `--ceiling <occurrences>`, which exits 1 when the count has risen.

**Also on each host, no script:** `grep -nE '(^|_)CC_|CLAUDE_CODE' <the host's environment files and compose overrides>` and say whether anything appears that `src/conf/env-contract.tsv` does not list (T38 spec, Section 14).

Still owed from the blocks below: the T36 identity inventory and the T35 persona-name inventory on the development server, the T22 engine-account inventory on both hosts, C20 and the T31 dry run on the test VM, the T19 inventory on both hosts.

## Done 2026-11-16 on both engines (AGY on the test VM, Jetski on the cloud workstation): C17, the engines' internal tools; ruled as D74

**Result on AGY 1.5.9 (test VM, 2026-11-16, `src/captures/out/c17-agy-20261116T192214/`; about 2.5 minutes, `gemini-3.8-flash-high`):**
- **The verdict line overstates.** It reports ten names as existing because their launches were accepted. Read against the recorded frames, only two were called by name: `generate_image` (arguments `AspectRatio`, `ImageName`, `Prompt`; 76 seconds) and `search_web` (`query`).
- **Three old names resolve to current tools.** Allowed `write_to_file`, the model said no such tool exists and called `write_file`; allowed `replace_file_content`, it called `edit_file`; `tools: [view_file, read_file]` failed at launch with `tool name conflict: multiple tools resolved with name "read_file"`.
- **Five accepted names were not usable:** with `grep_search`, `find_by_name`, `list_dir`, `read_url_content` or `notebook_edit` allowed, the model said the tool was not available and that it had only `read_file` and `manage_task`.
- **`manage_task` was named by the model in every one of those replies** though no allow-list granted it.
- **Five names were refused at launch:** `code_search`, `view_code_item`, `view_file_outline`, `skill_search`, `browser_subagent`. Both controls behaved.
- **The `init` frame of every launch lists the same 60 tool names** whatever the allow-list (16 `browser_…` names and 44 others, among them `view_file`, `write_to_file`, `replace_file_content`, `grep_search`, `list_dir`, `call_mcp_tool`). What that list is has not been established.
- **Not established:** why an accepted name is unusable; whether the alias reading is right (it is inferred from three launches); anything about Jetski.

**Result on Jetski 2026.11.13 (cloud workstation, 2026-11-16, `src/captures/out/c17-jetski-20261116T193513/`, summary files only in the checkout; counted on the workstation by `src/captures/t14_internal_tools_inventory.sh jetski`, output `src/captures/out/t14-internal-tools-jetski-20261116.txt`):**
- Twelve names accepted, three refused (`view_code_item`, `view_file_outline`, `browser_subagent`); three called by name (`generate_image`, `search_web`, and `skill_search` with `query`, which AGY refuses).
- The same name conflict for `view_file` beside `read_file`; `write_to_file` and `replace_file_content` delivered `write_file` and `edit_file`.
- Six accepted names not delivered (AGY's five and `code_search`); `manage_task` named in all eight replies that listed the model's tools.
- The first frame lists 63 names in all 29 launches. Jetski's release notes say a retired tool's name stays "accepted as a no-op", which is the cause.
- The inventory script read no text from Jetski's binary (a launcher image).

**Ruled the same day as D74 (T14):** `specs/2026.11.16-t14-engine-internal-tools-spec.md`. **Still owed, not by Rick today:** the script's repair (row 53 of "Outstanding actions"), which must also record `manage_task`'s argument names from a hook on both engines (`Tools-6`, before Kernel-5); a rerun on each engine follows the repair.

**The zero-token inventory, either host** (reads the newest C17 run on that host, the binary, the shipped skills and the release notes):
```bash
src/captures/t14_internal_tools_inventory.sh agy      # or: jetski
```

C17 is what T14 (the last measure item) waits on, and it is part of row 13 of "Outstanding actions". It asks which built-in tools the engine has beyond the ones it lists, and what arguments each takes. **It is not a zero-token capture:** up to 32 short turns on the flash model (17 launches with every tool denied, then one turn per tool that exists).

**AGY, on the test VM, from the repo root:**
```bash
cd /mnt/lupin-data/unified-headless-wrapper
tmux new -s c17                                            # reattach later with: tmux attach -t c17
MODEL=gemini-3.8-flash-high python3 src/captures/c17_internal_tools.py agy
```

**What to paste back** (or say "done" to the session on the test VM, which reads the files itself):
```bash
cat src/captures/out/c17-agy-*/verdict.txt src/captures/out/c17-agy-*/tool-map.tsv
```

**Jetski, on the cloud workstation, when it is handy:**
```bash
git pull --rebase && chmod +x src/captures/*.sh src/captures/*.py
MODEL=gemini-flash-next python3 src/captures/c17_internal_tools.py jetski
cat src/captures/out/c17-jetski-*/verdict.txt src/captures/out/c17-jetski-*/tool-map.tsv
```

**Checked before this block was written (2026-11-16, after the T34 script hung on Jetski):**
- Every launch is bounded. The driver starts the engine with pipes and no terminal, in a session of its own; a turn that brings no result is abandoned at 180 seconds, standard input is closed, and 10 seconds later the process group is killed. A launch can cost about 190 seconds and no more.
- So the run cannot hang for good. If every launch stalled it would end in about 100 minutes; the 8 minutes the older block states is an estimate from 2026-11-03 that has never been measured.
- `gemini-3.8-flash-high` is a model AGY 1.5.9 lists (`agy models`). `gemini-flash-next` for Jetski was not rechecked.
- It writes only to throwaway workspaces and `src/captures/out/`; the script itself changes nothing under `~/.gemini/` (the engine keeps its usual record of each launch there).
- **Not checked:** the candidate names were chosen on 2026-11-03 against AGY 1.4.7. The run on 1.5.9 says which of them exist; it cannot find a tool that is not on its list. `CANDIDATES="name1 name2"` in front of the command overrides the list.
- A line reading `oracle calibrated … NO` in the verdict means the method no longer works on this version (a made-up tool name was accepted, or `run_command` refused); paste it as it is.

C15 and C16, the rest of row 13, are in the block "Then: C15–C17" below and do not hold up T14.

## Done 2026-11-16: the T34 deferred-capture readings on the cloud workstation (Jetski), zero tokens

**Done:** `src/captures/out/t34-deferred-captures-rickruiz.c.googlers.com-20261116.txt` (Jetski 2026.11.13); results in the T34 spec, Section 12. Kept for the record of the hung first run.

D73 (the deferred captures) closed every line of the October checklist without a capture run. The test VM's reading on AGY 1.5.9 is in (`src/captures/out/t34-deferred-captures-lupin-host-test-20261116.txt`: the data-directory flag hidden, `mcp(server/tool)` rules in the release notes, a `control_request` on standard input refused as "not supported yet"). Jetski's reading is the one thing owed. The script makes no model call: each engine reply it prints reports zero turns and zero tokens.

**Revised 2026-11-16, after the first Jetski run hung.** At step 3 (`jetski -p "/permissions"`) Jetski showed a permissions table and waited; the script's time limit did not end it, and Rick stopped it after ten minutes. The script now runs every engine launch with no terminal, kills it outright 5 seconds past its limit, writes output to files and not pipes, and **skips step 3 on any engine but AGY** (only AGY's release notes say print mode answers that line without a turn). The whole run is now bounded at about four minutes even if every launch stalls.

**First, on the cloud workstation, clear what the hung run left** (look before killing; the pattern is the script's own scratch directory):
```bash
pgrep -af 't34-probe|jetski .*-p /permissions'
```

**Then:**
```bash
git pull --rebase && chmod +x src/captures/*.sh src/captures/*.py
src/captures/t34_deferred_captures.sh jetski | tee src/captures/out/t34-deferred-captures-$( hostname )-$( TZ=America/New_York date +%Y%m%d ).txt
```

**What to paste back (or commit and push):** the whole output. The lines that decide things: `version`, `listed_in_help`, the `[version line]` lines, and `event_control_request` (if it no longer says "not supported yet", say so: that opens the item on the interrupt route). A line reading `(cut at N s: …)` means that launch stalled and was ended; paste it as it is. Also say, from memory of the hung run, whether the permissions table looked like an interactive screen or like a model's reply: the second would mean Jetski took the line as a prompt and spent a turn.

Still owed from the blocks below: the T38 naming inventory, the T36 identity inventory and the T35 persona-name inventory on the development server, the T22 engine-account inventory on both hosts, C20 and the T31 dry run on the test VM, the T19 inventory on both hosts.

## Still owed: the T36 identity inventory on the development server, zero tokens (2026-11-15)

D70 (proven persona identity) has the kernel sign one grant per request with a key held only in its memory, and raises Lupin's slow key check as a lupin ticket. The test VM's reading is in (`src/captures/out/t36-identity-seams-lupin-host-test-20261115.txt`: 18 routers behind the account door, 8 naming a sender; shared-key send sites 7, 5 and 10; one bcrypt check about 345 ms; 2 active keys on the test database; `ptrace_scope` 1; the account privileged). The development server holds the production numbers.

**On the development server:**
```bash
git pull --rebase && chmod +x src/captures/*.sh src/captures/*.py
src/captures/t36_identity_seam_inventory.sh <path to the lupin checkout on the development server> | tee src/captures/out/t36-identity-seams-$( hostname )-$( TZ=America/New_York date +%Y%m%d ).txt
```

**What to paste back (or commit and push):** the whole output. The lines that decide things: `ptrace_scope`, `passwordless_sudo` and `docker_group` (can the kernel's memory be kept from a persona there), the `ed25519` line of each Lupin container, `one bcrypt check`, and the `active | all | cost` line (if the production database is not a local container the line is absent; then say how many active rows `api_keys` holds).

**Also for Rick, no script:** file the lupin ticket whose text is in the T36 spec, Section 12 (the key check: a SHA-256 column on `api_keys`, filled on first use).

Still owed from the blocks below: the T35 persona-name inventory on the development server, the T22 engine-account inventory on both hosts, C20 and the T31 dry run on the test VM, the T19 inventory on both hosts.

## Still owed: the T35 persona-name inventory on the development server, zero tokens (2026-11-15)

D69 (canonical persona name) rewrites `lupin-app.ini` into key form and puts a check on every stored persona-name column. The test VM's reading is in (`src/captures/out/t35-name-seams-lupin-host-test-20261115.txt`: 7 of 14 pool entries and 32 key names not in key form, one file normalizing outside the shared module, five raw-comparison lines), but its `lupin-app.ini` is modified in the working tree, so the development server's file is read on its own. The script reads the lupin checkout and writes nothing to it.

**On the development server:**
```bash
git pull --rebase && chmod +x src/captures/*.sh src/captures/*.py
src/captures/t35_name_seam_inventory.sh <path to the lupin checkout on the development server> | tee src/captures/out/t35-name-seams-$( hostname )-$( date +%Y%m%d ).txt
```

**What to paste back (or commit and push):** the whole output. The lines that decide things: `configuration_file` (as committed, or modified), every `NOT_KEY_FORM` pool entry, the section of configuration keys not in key form (is `Arnold` there too?), the raw-comparison lines, and the `summary` block. Rerun it after each lupin change on the D69 list (T35 spec, Section 13); Name-4 passes when both `…not_key_form` lines read 0, Name-8 when the local copies are gone.

Still owed from the blocks below: the T22 engine-account inventory on both hosts, C20 and the T31 dry run on the test VM, the T19 inventory on both hosts.

## Still owed: the T22 engine-account inventory, zero tokens (2026-11-11, third session)

D68 (engine sign-in and quota) rests on four facts only the hosts hold: where AGY keeps its sign-in today and how old it is, whether a process started from a systemd user unit with no terminal can read the usage meter (with and without `GEMINI_FORCE_FILE_STORAGE=true`), the meter's real field names on Linux, and the two overage settings as found. The script prints no secret, token or email. It makes no model call; AGY itself may write one log per call to a scratch directory that is removed. Its `systemd-run` lines have never run (the laptop sandbox has no systemd), so a failure there is a script defect to report, not a host finding.

**On the test VM and on the development server, as the persona account:**
```bash
git pull --rebase && chmod +x src/captures/*.sh src/captures/*.py
src/captures/t22_engine_account_inventory.sh | tee src/captures/out/t22-account-$( hostname )-$( date +%Y%m%d ).txt
```

**What to paste back (or commit and push):** the whole output. The lines that decide things: `token_file`, `keyring_entry`, the four `*_exit` lines under the meter sections, the bucket lines (group name, window, `extra_keys`), the `useG1Credits` / `useAiCredits` lines, and the `count:` lines at the end. Results land in the T22 spec's Section 18.

Still owed from the earlier block below: C20 and the T31 dry run on the test VM, the T19 inventory on both hosts.

## Still owed, zero tokens (2026-11-11, after the probe and inventory runs)

The probe and the inventory are in from both hosts (`descriptor_store ok` twice; T25 spec Section 15). Three zero-token checks remain; C20 is the only one Kernel-2 waits on. Each has its detail block below.

**On the test VM, as the persona account:**
```bash
git pull --rebase && chmod +x src/captures/*.sh src/captures/*.py
MODEL=gemini-3.8-flash-high src/captures/c20_relaunch_tree.sh agy
python3 src/captures/t31_switch_over.py --self-test
python3 src/captures/t31_switch_over.py snapshot ~/.claude/sessions --out src/captures/out/t31-roster-$( hostname )-$( date +%Y%m%d ).json
python3 src/captures/t31_switch_over.py archive  src/captures/out/t31-roster-$( hostname )-$( date +%Y%m%d ).json
src/captures/t19_switch_over_inventory.sh <path to the lupin checkout on the VM> | tee src/captures/out/t19-inventory-$( hostname )-$( date +%Y%m%d ).txt
```

**On the development server:**
```bash
git pull --rebase && chmod +x src/captures/*.sh src/captures/*.py
python3 src/captures/t31_switch_over.py --self-test
python3 src/captures/t31_switch_over.py snapshot ~/.claude/sessions --out src/captures/out/t31-roster-$( hostname )-$( date +%Y%m%d ).json
python3 src/captures/t31_switch_over.py archive  src/captures/out/t31-roster-$( hostname )-$( date +%Y%m%d ).json
src/captures/t19_switch_over_inventory.sh ../lupin | tee src/captures/out/t19-inventory-$( hostname )-$( date +%Y%m%d ).txt
```

**What to paste back (or commit and push, as on 11-11):** `verdict.txt` from `src/captures/out/c20-*`; the T31 snapshot's summary and per-seat lines and the archive plan's `missing` list; the T19 output's last line and every non-`present` row.

**Not needed again:** the T25 inventory. Its script lost two defects on 11-11 (a 790-line property dump after `oomd_root_swap`, a doubled `systemd_oomd` line); the data lines of the 11-11 runs are good.

## Done 2026-11-11 on both hosts: descriptor-store probe and the revised T25 inventory

Zero tokens. The probe starts a throwaway user service, parks a pipe in systemd's descriptor store, restarts the service and reads the pipe back: the mechanism the kernel's restart rests on (D65), not yet seen working on either host. The inventory gained four lines after the development server's first run: the probe scope's `memory.max`, the `NOTIFY_SOCKET` value, oomd's limits, and whether each engine binary honors `NODE_OPTIONS`.

**On the development server and on the test VM, as the persona account:**
```bash
git pull --rebase && chmod +x src/captures/*.sh src/captures/*.py
src/captures/t08_descriptor_store_probe.sh | tee src/captures/out/t08-store-probe-$( hostname )-$( date +%Y%m%d ).txt
src/captures/t25_host_inventory.sh | tee src/captures/out/t25-inventory-$( hostname )-$( date +%Y%m%d ).txt
```

**What to paste back:** both outputs whole. The lines that matter: `descriptor_store ok`, `scope_probe` (expect `memory.max=67108864 memory.swap.max=0`), `notify_socket_probe` (a path), `agy.node_options`, `oomd_pressure_limit`. C20 on the test VM is unchanged, below.

## Detail, still owed: T31 switch-over snapshot, dry run (2026-11-10)

Zero tokens, read-only. The Switch clock's first steps for one fleet host (D64): `snapshot` lists the seats that pass lupin's liveness rule with their names, roles, lineage and ledger cursors; `check` says whether each is drained (exit 1 while any is not); `archive` without `--apply` prints the plan. Nothing it does today changes the host; the real run is switch-over week, rehearsed first on the test VM (Switch-4). Run the self-test, then a snapshot and a dry-run archive on each host where lupin is installed (the development server and the test VM), and keep the output.

**On either host, as the persona account:**
```bash
git pull --rebase && chmod +x src/captures/*.sh src/captures/*.py
python3 src/captures/t31_switch_over.py --self-test
python3 src/captures/t31_switch_over.py snapshot ~/.claude/sessions --out src/captures/out/t31-roster-$( hostname )-$( date +%Y%m%d ).json
python3 src/captures/t31_switch_over.py check src/captures/out/t31-roster-$( hostname )-$( date +%Y%m%d ).json --api-key-file <the fleet key file>   # exit 1 while a seat is not quiet; the `undelivered?job_id=` route exists only after D55 lands, so expect that count to read 0 or the route to 404 today
python3 src/captures/t31_switch_over.py archive  src/captures/out/t31-roster-$( hostname )-$( date +%Y%m%d ).json              # dry run; prints members and what is missing
```

**What to paste back:** the snapshot's summary line and its per-seat lines (`persona_id  name  role  manager  buffer`), the check's verdict, and the archive plan's `missing` list.

## Detail, still owed: T19 switch-over inventory (2026-11-10)

Zero tokens, read-only. The list of what goes at the switch-over (T19 spec Section 5, D63) in machine form: 142 rows, each a file, tree, symbol, INI key, route or systemd unit in lupin, with its clock (move, switch, delete) and disposition. The script prints `present <lines>`, `gone` or `unknown` per row; `unknown` is a defect in the list. Run it against the lupin checkout on each host before each clock, and keep the output.

**On the development server (lupin checkout beside this one):**
```bash
git pull --rebase && chmod +x src/captures/*.sh
src/captures/t19_switch_over_inventory.sh ../lupin | tee src/captures/out/t19-inventory-$( hostname )-$( date +%Y%m%d ).txt
```

**At a clock** (exits non-zero when a Delete row is still present or a Keep row is gone): `src/captures/t19_switch_over_inventory.sh ../lupin --clock move`. **During a proof workload** (Switch-2; both counts must be zero): `src/captures/t19_switch_over_inventory.sh ../lupin --trace <kernel pid> ~/.claude/sessions`.

**What to paste back:** the last line (`# rows=142 unknown=0`) and every non-`present` row. Today, on the laptop clone at `82fdc0182`, the only `gone` row is `kernel grant required`, a key T36 has not added yet.

## Detail: T25 host inventory (done 11-11) and C20 (still owed on the test VM) (2026-11-10)

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

