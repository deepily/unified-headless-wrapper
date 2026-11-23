#!/usr/bin/env bash
# t19_builder_launch_facts.sh — what this host holds that decides how the Phase 1 builder's
# session is launched, for row 95 of "Outstanding actions" (T19 spec, the amendment of
# 2026-11-17, row 87, "Not established"; widened by rows 93 and 116 on 2026-11-22).
#
#   t19_builder_launch_facts.sh [builder's clone] [lupin root]
#       defaults: /mnt/lupin-data/unified-headless-wrapper-builder; $LUPIN_ROOT or /mnt/lupin-data/lupin
#
# Seven parts, one line per fact, `name value`:
#
#   (a) the launcher            lupin's script that starts Claude Code inside tmux, and its flags
#   (b) the engine              versions, and what the account-wide settings give every session
#   (c) the folder              the builder's clone, and the project name lupin derives from it
#   (d) the voice               the one tool server, the instance it calls, the project's account
#   (e) the task store's tools  whether they come with that same server
#   (f) the persona             the pool, the roster of declared managers, what past sessions got
#   (g) tmux                    whether a server runs, and what the launcher needs from systemd
#
# Read-only: `grep`, `wc`, `ls`, `git -C`, two GET requests for /health, and python that only
# reads (run with -B, so no byte-code file is written into lupin; lupin's own modules are imported
# under the interpreter the hooks use, $LUPIN_CC_VENV). No value of a password, a
# key or an email address is printed: sections and keys are named, never their values.
# It does NOT run the launcher, not even with --dry-run: the dry run starts a throwaway tmux
# session to measure the command's length, and on a host with no tmux server that starts one.
# Zero tokens, a few seconds.
# Output is meant for src/captures/out/t19-builder-launch-facts-<host>-<date>.txt.

set -u
builder="${1:-/mnt/lupin-data/unified-headless-wrapper-builder}"
lupin="${2:-${LUPIN_ROOT:-/mnt/lupin-data/lupin}}"
here="$(cd "$(dirname "$0")/../.." && pwd)"
launcher="$lupin/src/scripts/start-cc-with-tmux.sh"
tool_server="$lupin/src/lupin_mcp/cosa_voice_mcp.py"
credentials="$HOME/.lupin/config"
roster="$HOME/.claude/fleet-roster.env"
say() { printf '%-46s %s\n' "$1" "$2"; }
yes_no() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
hook_venv="${LUPIN_CC_VENV:-$HOME/.venv-lupin-mcp}"
can_import() { yes_no env PYTHONPATH="$lupin/src" "$1" -B -c 'import requests; from cosa.agents.utils.sender_id import detect_project'; }
has_flag() { yes_no grep -qE "^[[:space:]]*$1[[:space:]]*\)" "$launcher"; }

echo "# (a) the launcher"
say host "$(hostname)"
say read_at "$(TZ=America/New_York date '+%Y-%m-%d %H:%M %Z')"
say lupin_head "$(git -C "$lupin" log --oneline -1 2>/dev/null | cut -c1-10)"
say launcher "$launcher"
say launcher_present "$(yes_no test -r "$launcher")"
say launcher_lines "$(wc -l < "$launcher" 2>/dev/null)"
say alias_cctmx "$(grep -c "^alias cctmx=.*start-cc-with-tmux.sh" "$HOME/.bash_aliases" 2>/dev/null)"
for flag in --work-dir --headless --prompt --vertex --dry-run; do
  say "flag[$flag]" "$(has_flag "$flag")"
done
say first_positional_is_tmux_session_name "$(yes_no grep -q '^SESSION_NAME="${POSITIONALS\[0\]' "$launcher")"
say dry_run_starts_a_tmux_session "$(yes_no grep -q 'Brief-length probe (dry_run ONLY)' "$launcher")"
say sources_fleet_roster "$(yes_no grep -q 'source "$FLEET_ROSTER_ENV"' "$launcher")"
say runs_fleet_cap_admission "$(yes_no grep -q 'lupin_mcp.fleet_cap_admission' "$launcher")"
say memory_ceiling_default "$(grep -oE 'CC_MEM_LIMIT:-[0-9A-Za-z]+' "$launcher" | head -1 | cut -d- -f2)"
say lupin_venv_activate_present "$(yes_no test -r "$lupin/.venv/bin/activate")"
# The hooks run under ${LUPIN_CC_VENV:-$LUPIN_ROOT/.venv}; they import `cosa`, which needs `requests`.
say hooks_interpreter_variable_set_in_this_shell "$(yes_no test -n "${LUPIN_CC_VENV:-}")"
say launcher_forwards_that_variable "$(yes_no grep -q 'LUPIN_CC_VENV' "$launcher")"
say "hooks_can_import[lupin's .venv]" "$(can_import "$lupin/.venv/bin/python3")"
say "hooks_can_import[the variable's venv]" "$(can_import "$hook_venv/bin/python3")"
say "launch_guard_can_import[lupin's .venv]" "$(yes_no env PYTHONPATH="$lupin/src" "$lupin/.venv/bin/python3" -B -c 'from cosa.utils.vertex_env import pane_guard')"

echo "# (b) the engine"
say claude_code "$(claude --version 2>/dev/null | head -1)"
say tmux "$(tmux -V 2>/dev/null)"
say systemd_run "$(yes_no command -v systemd-run)"
say xdg_runtime_dir_set "$(yes_no test -n "${XDG_RUNTIME_DIR:-}")"
python3 -B - <<'PY'
import json, os
def say(name, value): print('%-46s %s' % (name, value))
home = os.path.expanduser('~')
try:
    settings = json.load(open(home + '/.claude/settings.json'))
except Exception as error:
    settings = {}; say('settings_unreadable', type(error).__name__)
hooks = settings.get('hooks', {})
say('settings_hook_events', '%d (%s)' % (len(hooks), ', '.join(sorted(hooks))))
say('settings_hooks_run_from_lupin', sum('LUPIN_ROOT' in json.dumps(v) for v in hooks.values()))
environment = settings.get('env', {})
say('settings_route_to_vertex', environment.get('CLAUDE_CODE_USE_VERTEX', 'unset'))
say('settings_model', settings.get('model', 'unset'))
say('settings_opus_model', environment.get('ANTHROPIC_DEFAULT_OPUS_MODEL', 'unset'))
permissions = settings.get('permissions', {})
say('settings_permission_mode', permissions.get('defaultMode', 'unset'))
say('settings_allow_rules', len(permissions.get('allow', [])))
say('settings_allows_tool_server', 'yes' if 'mcp__cosa-voice' in permissions.get('allow', []) else 'no')
say('settings_time_zone', environment.get('TZ', 'unset'))
PY

echo "# (c) the folder"
say builder_clone "$builder"
say builder_clone_present "$(yes_no test -d "$builder/.git")"
say builder_head "$(git -C "$builder" log --oneline -1 2>/dev/null | cut -c1-7)"
say planning_head "$(git -C "$here" log --oneline -1 2>/dev/null | cut -c1-7)"
say builder_local_loader "$(head -1 "$builder/CLAUDE.local.md" 2>/dev/null)"
say builder_clone_checks_ok "$("$here/src/captures/t19_builder_clone_setup.sh" --check "$builder" 2>/dev/null | grep -c ' ok$') of 14"
say builder_has_kernel_package "$(yes_no test -d "$builder/src/uhw_kernel")"
BUILDER="$builder" PLANNING="$here" python3 -B - <<'PY'
import json, os
def say(name, value): print('%-46s %s' % (name, value))
home = os.path.expanduser('~')
state = json.load(open(home + '/.claude.json'))
projects = state.get('projects', {})
for label, path in (('builder', os.environ['BUILDER']), ('planning', os.environ['PLANNING'])):
    entry = projects.get(path)
    say('claude_knows_folder[%s]' % label, 'no' if entry is None else 'yes, trust accepted: %s' % entry.get('hasTrustDialogAccepted'))
    transcripts = home + '/.claude/projects/' + path.replace('/', '-')
    say('claude_transcripts[%s]' % label, len([f for f in os.listdir(transcripts) if f.endswith('.jsonl')]) if os.path.isdir(transcripts) else 'no folder')
PY
detect() {
  ( cd "$1" 2>/dev/null && PYTHONPATH="$lupin/src" "$hook_venv/bin/python3" -B -c '
from cosa.agents.utils.sender_id import detect_project
from cosa.utils.notification_utils import is_known_project
name = detect_project()
print( name, "(in lupin'"'"'s short list)" if is_known_project( name ) else "(from the folder'"'"'s name)" )' 2>/dev/null ) || echo "not derived"
}
builder_project="$(detect "$builder")"
planning_project="$(detect "$here")"
say project_name[builder] "$builder_project"
say project_name[planning] "$planning_project"
say project_aliases_in_lupin "$(sed -n '/^_PROJECT_ALIASES = {/,/^}/p' "$lupin/src/cosa/agents/utils/sender_id.py" | grep -c ':')"

echo "# (d) the voice"
python3 -B - <<'PY'
import json, os
def say(name, value): print('%-46s %s' % (name, value))
state = json.load(open(os.path.expanduser('~/.claude.json')))
servers = state.get('mcpServers', {})
say('tool_servers_account_wide', '%d (%s)' % (len(servers), ', '.join(sorted(servers))))
voice = servers.get('cosa-voice', {})
say('voice_server_script', (voice.get('args') or ['?'])[-1])
say('voice_server_environment_keys', ', '.join(sorted(voice.get('env', {}))))
say('voice_server_names_an_instance', 'yes' if any(k in voice.get('env', {}) for k in ('LUPIN_APP_SERVER_URL', 'LUPIN_API_URL')) else 'no')
PY
say shell_names_an_instance "$(if [ -n "${LUPIN_APP_SERVER_URL:-}${LUPIN_API_URL:-}" ]; then echo yes; else echo no; fi)"
say instance_when_none_is_named "$(grep -oE 'getenv\( "LUPIN_APP_SERVER_URL", "[^"]+"' "$tool_server" | head -1 | grep -oE 'http[^"]+')"
for port in 7999 8000; do
  say "health[$port]" "$(curl -s -o /dev/null -m 4 -w '%{http_code}' "http://localhost:$port/health" 2>/dev/null)"
  say "container[$port]" "$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -E "0\.0\.0\.0:$port->" | cut -d' ' -f1)"
done
say credentials_file_present "$(yes_no test -r "$credentials")"
say credentials_project_sections "$(grep -cE '^\[' "$credentials" 2>/dev/null) sections in all"
for section in unified-headless-wrapper unified-headless-wrapper-builder owner; do
  say "credentials_section[$section]" "$(yes_no grep -qxF "[$section]" "$credentials")"
done
say account_lookup_collapses_a_worktree "$(yes_no grep -q 'def _main_checkout_name' "$lupin/src/lupin_cli/claude_code/hooks/lib/hook_credentials.py")"

echo "# (e) the task store's tools"
say tools_on_the_voice_server "$(grep -c '^@mcp.tool' "$tool_server")"
say task_store_tools_among_them "$(grep -cE '^def task_' "$tool_server")"
say task_store_tool_names "$(grep -oE '^def task_[a-z_]+' "$tool_server" | cut -c5- | tr '\n' ' ')"
say task_store_tools_call "$(grep -c 'api_base_url *= _get_server_url()' "$tool_server") of them the instance of part (d)"
say write_gate_module_present "$(yes_no test -r "$lupin/src/lupin_cli/claude_code/hooks/lib/manager_figure.py")"

echo "# (f) the persona"
pool="$(grep -E '^cc session voice persona pool +=' "$lupin/src/conf/lupin-app.ini" | head -1 | cut -d= -f2-)"
say persona_pool_size "$(printf '%s' "$pool" | tr ',' '\n' | grep -c .)"
say persona_pool "$(printf '%s' "$pool" | sed 's/^ *//')"
say roster_file_present "$(yes_no test -r "$roster")"
say roster_projects_with_a_manager "$(grep -oE '^COSA_VOICE_MANAGERS__[A-Z0-9_]+' "$roster" 2>/dev/null | sed 's/COSA_VOICE_MANAGERS__//' | tr '\n' ' ')"
say roster_managers_named "$(grep -E '^COSA_VOICE_MANAGERS__' "$roster" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr ',' '\n' | sed 's/^ *//' | sort -u | tr '\n' ' ')"
for key in UNIFIED_HEADLESS_WRAPPER UNIFIED_HEADLESS_WRAPPER_BUILDER; do
  say "roster_key[$key]" "$(yes_no grep -qE "^COSA_VOICE_MANAGERS__$key=" "$roster")"
done
PLANNING="$here" BUILDER="$builder" python3 -B - <<'PY'
import glob, json, os
def say(name, value): print('%-46s %s' % (name, value))
found = {'planning': [], 'builder': []}
for path in sorted(glob.glob(os.path.expanduser('~/.claude/sessions/cc-[0-9]*.json'))):
    try: bridge = json.load(open(path))
    except Exception: continue
    for label in found:
        if bridge.get('cwd') == os.environ[label.upper()]:
            found[label].append('%s persona=%s manager=%s' % (
                (bridge.get('idle_detection') or {}).get('last_interaction_at', '?')[:10],
                bridge.get('voice_persona', 'absent'), bridge.get('manager_figure_implicit', 'absent')))
for label, rows in found.items():
    say('past_claude_sessions[%s]' % label, len(rows))
    for row in rows: say('  session', row)
PY

echo "# (g) tmux"
say tmux_server_running "$(yes_no tmux list-sessions)"
say tmux_sessions "$(tmux list-sessions 2>/dev/null | wc -l)"
say tmux_processes "$(pgrep -x tmux 2>/dev/null | wc -l)"
say memory_slices_left_behind "$(systemctl --user list-units --all 2>/dev/null | grep -c 'ccworker-.*\.slice')"
