#!/usr/bin/env bash
# C3 -- does persona identity reach a stdio MCP server, one server per engine process?   usage: MCP_CONFIG=<path> c3_mcp_identity.sh jetski|agy
# Two engines run concurrently with different UHW_PROBE_TAG values. The probe server is registered in MCP_CONFIG
# (backed up first, restored on exit) with an env block, so one run answers: inheritance, env block, ${VAR} expansion.
source "$( dirname "$0" )/common.sh"
BIN=${1:?usage: MCP_CONFIG=<path> c3_mcp_identity.sh jetski|agy}; new_out "c3-$BIN"; jetski_engine "$BIN"
{ "$BIN" --help < /dev/null 2>&1; "$BIN" mcp --help < /dev/null 2>&1; } | grep -n -i -E 'mcp|server' > "$OUT/discovery.txt" || true
if [ -z "${MCP_CONFIG:-}" ]; then
    echo "MCP_CONFIG is not set. Where $BIN reads MCP servers from is unknown; candidates from --help are in $OUT/discovery.txt."
    echo "Re-run with MCP_CONFIG=<that file>. The script backs it up and restores it."; exit 2
fi
[ -e "$MCP_CONFIG" ] && cp "$MCP_CONFIG" "$OUT/mcp_config.backup"
restore() { if [ -e "$OUT/mcp_config.backup" ]; then cp "$OUT/mcp_config.backup" "$MCP_CONFIG"; else rm -f "$MCP_CONFIG"; fi; }
trap restore EXIT
export UHW_PROBE_MCP_LOG="$OUT/mcp.jsonl" UHW_PROBE_LOG="$OUT/hook.jsonl"
"$PY" - "$MCP_CONFIG" "$PY" "$HERE/probe_mcp.py" "$OUT/mcp.jsonl" <<'PYEOF'
import json, os, sys
path, python, probe, log = sys.argv[ 1: ]
config = json.load( open( path ) ) if os.path.exists( path ) and os.path.getsize( path ) else {}
config.setdefault( "mcpServers", {} )[ "uhw-probe" ] = { "command": python, "args": [ probe ],
    "env": { "UHW_PROBE_MCP_LOG": log, "UHW_PROBE_BLOCK": "block-static", "UHW_PROBE_EXPANDED": "${UHW_PROBE_TAG}" } }
os.makedirs( os.path.dirname( path ) or ".", exist_ok=True ); json.dump( config, open( path, "w" ), indent=1 )
PYEOF
PROMPT='Call the whoami tool from the uhw-probe MCP server exactly once and quote its output verbatim.'
for n in 1 2; do
    WS=$( mktemp -d ); write_hooks "$WS"
    UHW_PROBE_TAG="persona-$n" "$PY" "$HERE/drive.py" --family jetski --cwd "$WS" --out "$OUT/frames-$n.jsonl" \
        --turn "$PROMPT" -- "${ENGINE[@]}" > "$OUT/summary-$n.jsonl" &
done
wait
cat "$OUT"/summary-*.jsonl
"$PY" "$HERE/facts.py" "$OUT" --check c3
