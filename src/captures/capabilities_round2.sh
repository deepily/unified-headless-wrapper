#!/usr/bin/env bash
# capabilities_round2.sh [jetski] -- what the first C11-C14 run (2026-10-18 14:08) left open, one bundle to paste back.
#   C13  pinned-model pyramid rerun on four models    about 40 min (MODELS overrides, MODELS=none skips)
#   C11b workflows with tools allowed, global skill paths, agent tool grants, format field names   about 5 min
#   C14b one 200 s MCP call with a per-server "timeout" of 15 min in the config: is 180 s configurable?   about 4 min
source "$( dirname "$0" )/common.sh"
BIN=${1:-jetski}
export MODELS=${MODELS-"opus-5.5-high gemini-3.8-flash-high gemini-launch-candidate-high gemini-flash-next"}
command -v "$BIN" > /dev/null || { echo "$BIN is not on PATH on this machine"; exit 2; }
STAMP=$( date +%Y%m%dT%H%M%S ); mkdir -p "$HERE/out"; BUNDLE="$HERE/out/$BIN-round2-$STAMP.txt"
latest()  { ls -td "$HERE"/out/"$1"-"$BIN"-* 2> /dev/null | head -1; }
section() { printf '\n## %s\n' "$1" >> "$BUNDLE"; }
echo "# $BIN round 2 $STAMP · $( uname -sm ) · version $( "$BIN" --version < /dev/null 2>&1 | head -1 ) · MODELS=$MODELS" > "$BUNDLE"

echo "=== C11b"; "$PY" "$HERE/c11b_followups.py" "$BIN"
section "C11b"; cat "$( latest c11b )/verdict.txt" "$( latest c11b )/facts.json" >> "$BUNDLE" 2> /dev/null

echo "=== C14b (about 4 minutes)"; WAITS=200 MCP_TIMEOUT_MS=900000 "$PY" "$HERE/c14_mcp_wait.py" "$BIN"
section "C14b"; cat "$( latest c14 )/verdict.txt" >> "$BUNDLE" 2> /dev/null

echo "=== C13 (about 10 minutes per model)"; "$HERE/c13_pinned_model.sh" "$BIN"
section "C13"; dir=$( latest c13 ); cat "$dir/verdict.txt" >> "$BUNDLE"
for file in "$dir"/results-*.tsv "$dir"/spoken-*.txt; do [ -e "$file" ] && { echo "--- ${file##*/}"; cat "$file"; } >> "$BUNDLE"; done

echo; echo "Paste back: $BUNDLE"
