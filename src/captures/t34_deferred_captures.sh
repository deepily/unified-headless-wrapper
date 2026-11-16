#!/usr/bin/env bash
# T34 deferred captures, read from the host at zero tokens (2026-11-16). No model call: every engine
# launch below either prints help, answers a print-mode slash command, or is refused before a turn starts
# (the result frame says num_turns 0 and total_tokens 0, and the script prints both).
# Answers, for one engine binary on one host:
#   1. per-persona data directory: is --app_data_dir a listed flag, and is the name in the binary at all;
#   2. interrupt latency: what the vendor's release notes say about interrupts and shutdown in print mode;
#   3. rule syntax for tool-server tools: the release-note lines, and the rule table the engine prints;
#   4. protocol interrupt: what the engine answers to a control_request on standard input, no turn in flight.
# It deliberately does NOT launch the engine with --app_data_dir: on AGY 1.5.9 that flag creates a
# directory under ~/.gemini/ before it refuses an absolute path (seen 2026-11-16, T34 session).
# Revised 2026-11-16 after the first Jetski run hung at step 3 on an interactive permissions table:
#   - every engine launch now runs in its own session with no terminal (setsid), so the engine cannot open
#     a screen or wait on a key; it is killed outright 5 seconds after its time limit; and its output goes
#     to a file, never a pipe, so a child process left behind cannot hold the script open;
#   - step 3 (the slash command) runs only where the vendor's release notes say print mode answers it
#     without a turn (AGY, since 1.1.12). On any other engine it is skipped unless --with-slash-commands
#     is given, because there the same line may open a screen or be taken as a prompt.
# Usage: t34_deferred_captures.sh [agy|jetski] [--with-slash-commands]      (default agy)
set -u
ENGINE=${1:-agy}
SLASH=${2:-}
BIN=$( command -v "$ENGINE" ) || { echo "no $ENGINE on PATH"; exit 2; }
REAL=$( readlink -f "$BIN" )
WORK=$( mktemp -d "${TMPDIR:-/tmp}/t34-probe.XXXXXX" )
trap 'rm -rf "$WORK"' EXIT
hr()  { printf '\n== %s ==\n' "$1"; }
# quiet_run <seconds> <output file> <standard input file> <command...>: no terminal, hard kill, output to a file.
quiet_run() {
    local limit=$1 out=$2 input=$3; shift 3
    ( cd "$WORK" && setsid -w timeout -k 5 "$limit" "$@" < "$input" > "$out" 2> "$out.err" )
    local code=$?
    if [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then echo "  (cut at ${limit} s: $*)"; fi
    return "$code"
}
val() { printf '%-44s %s\n' "$1" "$2"; }

hr "host and engine"
val host "$( hostname )"
val clock "$( TZ=America/New_York date '+%Y-%m-%d %H:%M:%S %Z' )"
val engine "$ENGINE"
val binary "$REAL"
quiet_run 20 "$WORK/version.txt" /dev/null "$BIN" --version
val version "$( cat "$WORK/version.txt" "$WORK/version.txt.err" 2>/dev/null | head -1 )"
quiet_run 20 "$WORK/help.txt" /dev/null "$BIN" --help
cat "$WORK/help.txt.err" >> "$WORK/help.txt" 2>/dev/null

hr "1. per-persona data directory"
val listed_in_help "$( grep -cE 'app[_-]data[_-]dir' "$WORK/help.txt" )"
val help_flag_count "$( grep -cE '^  -' "$WORK/help.txt" )"
val name_in_binary_app_data_dir "$( grep -a -c -- 'app_data_dir' "$REAL" )"
val flag_form_in_binary "$( grep -a -o -E -- '--app_data_dir=--cli_dir_name=' "$REAL" | head -1 )"
val default_directory "$( ls -d "$HOME"/.gemini/*/ 2>/dev/null | tr '\n' ' ' )"
val sign_in_file "$( ls "$HOME"/.gemini/*/*oauth* 2>/dev/null | tr '\n' ' ' )"

hr "2. and 3. the vendor's release notes ($ENGINE changelog)"
quiet_run 30 "$WORK/changelog.txt" /dev/null "$BIN" changelog
val changelog_lines "$( wc -l < "$WORK/changelog.txt" )"
val newest_version "$( grep -m1 -oE '^[0-9]+\.[0-9]+\.[0-9]+' "$WORK/changelog.txt" )"
awk '/^[0-9]+\.[0-9]+\.[0-9]+:/{ v = $1 }
     /mcp\(|finished_reason|never exiting after printing|canceled or interrupted calls|explicit deny rules still apply|control_request|protocol interrupt/ \
     { printf "[%s line %d] %s\n", v, NR, substr( $0, 1, 430 ) }' "$WORK/changelog.txt"
val lines_naming_control_request "$( grep -c 'control_request' "$WORK/changelog.txt" )"

hr "3. the rule table the engine prints (-p /permissions, no turn)"
if [ "$ENGINE" != agy ] && [ "$SLASH" != "--with-slash-commands" ]; then
    echo "skipped on $ENGINE: print mode is only known to answer /permissions without a turn on AGY."
    echo "To try it anyway (it may be taken as a prompt): add --with-slash-commands."
else
quiet_run 30 "$WORK/permissions.json" /dev/null "$BIN" -p "/permissions" --output-format json
python3 - "$WORK/permissions.json" <<'PY'
import json, sys
text = open( sys.argv[ 1 ], errors="replace" ).read()
try:
    reply = json.loads( text )
except Exception as problem:
    print( "unreadable:", problem, "| first 300 characters:", " ".join( text.split() )[ :300 ] ); sys.exit( 0 )
print( "%-44s %s" % ( "num_turns | total_tokens", "%s | %s" % ( reply.get( "num_turns" ), reply.get( "usage", {} ).get( "total_tokens" ) ) ) )
for scope in reply.get( "command", {} ).get( "data", {} ).get( "permissions", [] ):
    lists = { key: len( value ) for key, value in scope.items() if isinstance( value, list ) }
    forms = sorted( { rule.split( "(" )[ 0 ] for value in scope.values() if isinstance( value, list ) for rule in value } )
    print( "%-44s %s %s" % ( "scope " + scope.get( "scope", "?" ), lists or "no rules", forms ) )
PY
fi

hr "4. protocol interrupt: a control_request on standard input, no turn in flight"
probe() {  # $1 = label, $2 = one line of standard input
    printf '%s\n' "$2" > "$WORK/probe-$1.in"
    quiet_run 40 "$WORK/probe-$1.out" "$WORK/probe-$1.in" "$BIN" --input-format stream-json --output-format stream-json \
          --dangerously-skip-permissions
    code=$?
    python3 - "$WORK/probe-$1.out" "$WORK/probe-$1.out.err" "$1" "$code" <<'PY'
import json, sys
out, err, label, code = sys.argv[ 1: ]
result = None
for line in open( out, errors="replace" ):
    try:
        frame = json.loads( line )
    except Exception:
        continue
    if frame.get( "event" ) == "result":
        result = frame[ "result" ]
warning = " ".join( open( err, errors="replace" ).read().split() )[ :200 ]
if result:
    print( "%-44s exit %s | %s | %s | turns %s | tokens %s" % ( label, code, result.get( "status" ), result.get( "error" ),
           result.get( "num_turns" ), result.get( "usage", {} ).get( "total_tokens" ) ) )
else:
    print( "%-44s exit %s | no result frame | stderr: %s" % ( label, code, warning ) )
PY
}
probe "type_control_request"  '{"type":"control_request","request_id":"t34-probe","request":{"subtype":"interrupt"}}'
probe "event_control_request" '{"event":"control_request","request_id":"t34-probe","request":{"subtype":"interrupt"}}'
probe "event_interrupt"       '{"event":"interrupt"}'
val refusal_text_in_binary "$( grep -a -o -E 'stream input message event %q is not supported yet' "$REAL" | head -1 )"

hr "summary"
echo "Read: section 1 (listed_in_help 0 with name_in_binary above 0 = a hidden flag); the [version] lines"
echo "under sections 2 and 3; and the event_control_request line. 'is not supported yet' there means the"
echo "engine still has no protocol interrupt, so the adapter keeps interrupt_mode = signal."
