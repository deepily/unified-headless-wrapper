#!/usr/bin/env bash
# jetski_followup.sh [jetski|agy] -- Part B follow-up, one bundle to paste back:
#   1. model, agent and lineage fields from the latest C1 hook log (names and booleans only, never payload text)
#   2. whether --agent exists (persona bootstrap route)
#   3. where MCP servers are configured, a format check, then C3 if the format is accepted
#   4. whether --use_ls_chrome_devtools_mcp=false is accepted (persona launch argv)
# MCP_CONFIG overrides the config path (default ~/.gemini/config/mcp_config.json). Any change to it is restored on exit.
source "$( dirname "$0" )/common.sh"
BIN=${1:-jetski}
command -v "$BIN" > /dev/null || { echo "$BIN is not on PATH on this machine"; exit 2; }
STAMP=$( date +%Y%m%dT%H%M%S ); mkdir -p "$HERE/out"; BUNDLE="$HERE/out/$BIN-followup-$STAMP.txt"
say()     { printf '%s\n' "$*" | tee -a "$BUNDLE"; }
section() { say ""; say "## $1"; }
say "# $BIN follow-up $STAMP · $( uname -sm ) · version $( "$BIN" --version < /dev/null 2>&1 | head -1 )"

section "1. names from the latest C1 hook log"
C1=$( ls -td "$HERE"/out/c1-"$BIN"-* 2> /dev/null | head -1 )
if [ -s "$C1/hook.jsonl" ]; then
    say "source: ${C1##*/}"
    "$PY" - "$C1/hook.jsonl" <<'EOF' | tee -a "$BUNDLE"
import json, sys
rows  = [ json.loads( line )[ "payload" ] for line in open( sys.argv[ 1 ] ) if line.strip() ]
first = rows[ 0 ]
shape = lambda value: sorted( value ) if isinstance( value, dict ) else value
for key in ( "modelName", "agentName", "isBattleMode" ):
    print( f"{key}: {sorted( { str( row.get( key ) ) for row in rows } )}" )
print( f"callerContext: {shape( first.get( 'callerContext' ) )}" )
print( f"executionId distinct values across {len( rows )} hook calls: {len( { row.get( 'executionId' ) for row in rows } )}" )
print( f"parentConversationId empty: {not first.get( 'parentConversationId' )} · equals conversationId: {first.get( 'parentConversationId' ) == first.get( 'conversationId' )}" )
print( f"rootConversationId equals conversationId: {first.get( 'rootConversationId' ) == first.get( 'conversationId' )}" )
EOF
else
    say "no C1 hook log found: run src/captures/run_engine.sh $BIN first"
fi

section "2. --agent and agent definitions"
"$BIN" --help < /dev/null 2>&1 | grep -n -i -A1 -E -- '--agent|agents? ' | tee -a "$BUNDLE" || say "no --agent lines in --help"

section "3. MCP configuration"
CONFIG=${MCP_CONFIG:-$HOME/.gemini/config/mcp_config.json}
say "$ $BIN mcp list"; "$BIN" mcp list < /dev/null 2>&1 | tee -a "$BUNDLE"
say "candidate files:"; find "$HOME/.gemini" -maxdepth 3 -iname '*mcp*' 2> /dev/null | tee -a "$BUNDLE"
say "config under test: $CONFIG (exists: $( [ -e "$CONFIG" ] && echo yes || echo no ))"
BACKUP=$( mktemp ); EXISTED=no; [ -e "$CONFIG" ] && { cp "$CONFIG" "$BACKUP"; EXISTED=yes; }
restore() { if [ "$EXISTED" = yes ]; then cp "$BACKUP" "$CONFIG"; else rm -f "$CONFIG"; fi; }
trap restore EXIT
"$PY" - "$CONFIG" "$PY" "$HERE/probe_mcp.py" <<'EOF'
import json, os, sys
path, python, probe = sys.argv[ 1: ]
config = json.load( open( path ) ) if os.path.exists( path ) and os.path.getsize( path ) else {}
config.setdefault( "mcpServers", {} )[ "uhw-probe" ] = { "command": python, "args": [ probe ] }
os.makedirs( os.path.dirname( path ), exist_ok=True ); json.dump( config, open( path, "w" ), indent=1 )
EOF
if "$BIN" mcp list < /dev/null 2>&1 | grep -q uhw-probe; then
    restore
    say "format check: PASS ($BIN mcp list shows uhw-probe from $CONFIG)"
    section "3b. C3"
    MCP_CONFIG="$CONFIG" "$HERE/c3_mcp_identity.sh" "$BIN" > /dev/null 2>&1
    cat "$( ls -td "$HERE"/out/c3-"$BIN"-* | head -1 )/verdict.txt" | tee -a "$BUNDLE"
else
    restore
    say "format check: FAIL ($BIN mcp list does not show uhw-probe). Help for the registration route:"
    "$BIN" mcp add --help < /dev/null 2>&1 | head -30 | tee -a "$BUNDLE"
fi

section "4. --use_ls_chrome_devtools_mcp=false"
REPLY=$( limited 120 "$BIN" -p "Reply with the single word ok." --use_ls_chrome_devtools_mcp=false < /dev/null 2>&1 | tail -3 )
say "reply: $REPLY"

echo; echo "Paste back: $BUNDLE"
