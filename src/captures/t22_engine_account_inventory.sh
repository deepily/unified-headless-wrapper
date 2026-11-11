#!/usr/bin/env bash
# T22 engine account inventory (2026-11-11). No model call; prints no secret, no token, no email.
# Answers, for one host: where AGY keeps its sign-in, whether a process started the way the kernel
# will start one (a systemd user unit, no terminal) can see that sign-in, what the usage meter
# returns, which settings bear on billing, and what quota and sign-in errors this host has already
# logged. Run as the persona account on the test VM and on the development server.
# Side effects, all AGY's own: one log file per call (written to a scratch directory and removed), an update check, a touched
# conversation_summaries.db. Usage: t22_engine_account_inventory.sh [agy]
set -u
ENGINE=${1:-agy}
APP_DIR="$HOME/.gemini/antigravity-cli"
OUT="$( cd "$( dirname "$0" )" && pwd )/out/t22-$( hostname )-$( date +%Y%m%d-%H%M%S )"
mkdir -p "$OUT"
LOG_SCRATCH=$( mktemp -d )   # the engine's own per-call logs can name the account; they are not kept
trap 'rm -rf "$LOG_SCRATCH"' EXIT
hr()  { printf '\n== %s ==\n' "$1"; }
val() { printf '%-38s %s\n' "$1" "$2"; }
is_set() { [ -n "${!1:-}" ] && echo set || echo unset; }
describe() {  # mode, size, age in hours; never the content
    if [ -e "$1" ]; then
        val "$2" "present mode=$( stat -c %a "$1" ) bytes=$( stat -c %s "$1" ) modified=$( date -d "@$( stat -c %Y "$1" )" '+%Y-%m-%d %H:%M %Z' ) age_hours=$(( ( $( date +%s ) - $( stat -c %Y "$1" ) ) / 3600 ))"
    else
        val "$2" absent
    fi
}

hr "host"
val host "$( hostname )"
val account "$( id -un ) uid=$( id -u )"
val clock "$( date '+%Y-%m-%d %H:%M:%S %Z' )"
BIN=$( command -v "$ENGINE" 2>/dev/null )
val engine_binary "${BIN:-absent}"
[ -z "$BIN" ] && { echo "no $ENGINE on PATH; stopping"; exit 1; }
val engine_version "$( timeout 60 "$BIN" --version 2>/dev/null | head -1 )"
val engine_processes_running "$( pgrep -x "$ENGINE" 2>/dev/null | wc -l )"

hr "environment that selects a sign-in route (set or unset only)"
for name in AGY_ADC_AUTH GEMINI_FORCE_FILE_STORAGE GEMINI_API_KEY GOOGLE_API_KEY ANTIGRAVITY_API_KEY \
            GOOGLE_APPLICATION_CREDENTIALS GOOGLE_CLOUD_PROJECT GOOGLE_CLOUD_QUOTA_PROJECT GOOGLE_CLOUD_LOCATION \
            GOOGLE_GENAI_USE_VERTEXAI DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR; do
    val "$name" "$( is_set "$name" )"
done
val AGY_ADC_AUTH_value "${AGY_ADC_AUTH:-}"
val GEMINI_FORCE_FILE_STORAGE_value "${GEMINI_FORCE_FILE_STORAGE:-}"

hr "where the sign-in is kept (presence, mode, age; never content)"
describe "$APP_DIR/antigravity-oauth-token"   token_file
describe "$APP_DIR/credentials.enc"           credentials_enc
describe "$HOME/.gemini/google_accounts.json" google_accounts_json
describe "$HOME/.config/gcloud/application_default_credentials.json" gcloud_adc_file
val app_dir_mode "$( stat -c %a "$APP_DIR" 2>/dev/null || echo absent )"
val other_oauth_named_files "$( find "$HOME/.gemini" -maxdepth 3 \( -iname '*oauth*' -o -iname '*credential*' -o -iname '*token*' \) 2>/dev/null | sed "s|$HOME|~|" | tr '\n' ' ' )"
if command -v secret-tool >/dev/null 2>&1; then
    if timeout 10 secret-tool search service gemini account antigravity >/dev/null 2>&1; then val keyring_entry found; else val keyring_entry "not found (or keyring unreachable)"; fi
else
    val keyring_entry "secret-tool not installed"
fi
val secret_service_on_bus "$( busctl --user list 2>/dev/null | grep org.freedesktop.secrets | wc -l )"

hr "settings that bear on billing and route (named keys only)"
python3 - "$APP_DIR/settings.json" "$HOME/.gemini/config/config.json" <<'PY'
import json, sys
KEYS = ( "modelProvider", "useG1Credits", "useAiCredits", "use_ai_credits", "enableAdc", "model", "agentMode" )
def walk( node, path="" ):
    if isinstance( node, dict ):
        for key, value in node.items():
            here = f"{path}.{key}" if path else key
            if key in KEYS: print( f"  {here} = {value!r}" )
            walk( value, here )
for name in sys.argv[ 1: ]:
    try:
        with open( name ) as handle: data = json.load( handle )
        print( f"{name}: readable" ); walk( data )
    except FileNotFoundError: print( f"{name}: absent" )
    except Exception as error: print( f"{name}: unreadable ({type( error ).__name__})" )
PY

usage_read() {  # label, then the command prefix that launches the engine
    local label=$1; shift
    local started=$( date +%s.%N )
    "$@" -p "/usage" --output-format json --log-file "$LOG_SCRATCH/usage-$label.log" </dev/null >"$OUT/usage-$label.json" 2>"$OUT/usage-$label.stderr"
    local code=$?
    val "${label}_exit" "$code"
    val "${label}_seconds" "$( awk "BEGIN { printf \"%.1f\", $( date +%s.%N ) - $started }" )"
    val "${label}_stderr" "$( head -c 200 "$OUT/usage-$label.stderr" | tr '\n' ' ' )"
    python3 - "$OUT/usage-$label.json" <<'PY'
import json, sys
try:
    with open( sys.argv[ 1 ] ) as handle: reply = json.load( handle )
except Exception as error:
    print( f"  not JSON ({type( error ).__name__})" ); sys.exit( 0 )
print( "  top-level keys:", sorted( reply ) )
print( "  status:", reply.get( "status" ), "| num_turns:", reply.get( "num_turns" ), "| total_tokens:", ( reply.get( "usage" ) or {} ).get( "total_tokens", reply.get( "total_tokens" ) ) )
command = reply.get( "command" ) or {}
print( "  command.name:", command.get( "name" ), "| command.data keys:", sorted( ( command.get( "data" ) or {} ) ) )
for group in ( command.get( "data" ) or {} ).get( "groups" ) or []:
    for bucket in group.get( "buckets" ) or []:
        print( f"  {group.get( 'name' )!r:28} {bucket.get( 'id' )!r:18} window={bucket.get( 'window' )!r:9} remaining={bucket.get( 'remaining_fraction' )} reset={bucket.get( 'reset_time' )} extra_keys={sorted( set( bucket ) - { 'id', 'window', 'remaining_fraction', 'reset_time' } )}" )
PY
}

hr "usage meter, from this shell (zero tokens; signed out exits 1 in under a second)"
usage_read shell timeout 60 "$BIN"

hr "usage meter, from a systemd user unit with no terminal (how the kernel will start engines)"
if systemctl --user show-environment >/dev/null 2>&1; then
    usage_read unit          timeout 90 systemd-run --user --quiet --wait --collect --pipe "$BIN"
    usage_read unit_file     timeout 90 systemd-run --user --quiet --wait --collect --pipe --setenv=GEMINI_FORCE_FILE_STORAGE=true "$BIN"
else
    val unit "no systemd user manager reachable from this shell"
fi

hr "usage meter, from this shell with file storage forced"
GEMINI_FORCE_FILE_STORAGE=true usage_read shell_file timeout 60 "$BIN"

hr "commands print mode answers itself, and the model list (zero tokens)"
timeout 60 "$BIN" -p "/help" --output-format json --log-file "$LOG_SCRATCH/help.log" </dev/null >"$OUT/help.json" 2>/dev/null
python3 - "$OUT/help.json" <<'PY'
import json, sys
try:
    with open( sys.argv[ 1 ] ) as handle: reply = json.load( handle )
    text = json.dumps( reply )
    print( "  mentions usage:", "usage" in text, "| quota:", "quota" in text, "| credits:", "credits" in text, "| num_turns:", reply.get( "num_turns" ) )
except Exception as error: print( f"  not JSON ({type( error ).__name__})" )
PY
timeout 60 "$BIN" models 2>/dev/null | sed 's/^/  /' | head -40

hr "what this host's engine logs already hold (counts, then the three newest of each kind)"
LOGS="$APP_DIR/log"
val log_files "$( ls "$LOGS" 2>/dev/null | wc -l )"
val oldest_log "$( ls "$LOGS" 2>/dev/null | head -1 )"
for pattern in "Individual quota reached" "RESOURCE_EXHAUSTED" "Resets in" "code 429" "authentication required" "attempt [0-9]+ failed" "code 503" "MODEL_CAPACITY_EXHAUSTED" "Eligibility check failed"; do
    count=$( grep -rhE -c "$pattern" "$LOGS" 2>/dev/null | awk '{ sum += $1 } END { print sum + 0 }' )
    val "count: $pattern" "$count"
done
for pattern in "Individual quota reached" "authentication required" "code 429"; do
    printf '  newest "%s":\n' "$pattern"
    grep -rhE "$pattern" "$LOGS" 2>/dev/null | tail -3 | cut -c1-260 | sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/<email>/g; s/ya29\.[A-Za-z0-9._-]+/<token>/g' | sed 's/^/    /'
done

hr "done"
val output_directory "$OUT"
echo "Paste this whole output back, or commit $OUT and push."
