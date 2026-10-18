#!/usr/bin/env bash
# capabilities_followup.sh [jetski|agy] -- C11-C14 in one run, one bundle to paste back (runbook §9).
#   C11 instruction and extension surfaces       about 5 min
#   C12 subagent tool, veto by name, --mode plan  about 3 min
#   C14 long MCP calls (45, 200, 620 s)           about 15 min; SKIP_WAIT=1 skips, WAITS="..." overrides
#   C13 pinned-model pyramid rerun                about 10 min per model; runs only when MODELS is set
# MODEL=<name> also pins --model for C11, C12 and C14.
source "$( dirname "$0" )/common.sh"
BIN=${1:-jetski}
command -v "$BIN" > /dev/null || { echo "$BIN is not on PATH on this machine"; exit 2; }
STAMP=$( date +%Y%m%dT%H%M%S ); mkdir -p "$HERE/out"; BUNDLE="$HERE/out/$BIN-capabilities-$STAMP.txt"
latest()  { ls -td "$HERE"/out/"$1"-"$BIN"-* 2> /dev/null | head -1; }
section() { printf '\n## %s\n' "$1" >> "$BUNDLE"; }
echo "# $BIN capabilities $STAMP · $( uname -sm ) · version $( "$BIN" --version < /dev/null 2>&1 | head -1 ) · MODEL=${MODEL:-unset} MODELS=${MODELS:-unset}" > "$BUNDLE"

echo "=== C11"; "$PY" "$HERE/c11_surfaces.py" "$BIN"
section "C11 surfaces"; cat "$( latest c11 )/verdict.txt" "$( latest c11 )/facts.json" >> "$BUNDLE" 2> /dev/null

echo "=== C12"; "$PY" "$HERE/c12_subagent_plan.py" "$BIN"
section "C12 subagent and plan mode"; cat "$( latest c12 )/verdict.txt" "$( latest c12 )/facts.json" >> "$BUNDLE" 2> /dev/null

section "C14 long MCP calls"
if [ "${SKIP_WAIT:-0}" = 1 ]; then echo "skipped (SKIP_WAIT=1)" >> "$BUNDLE"
else echo "=== C14 (about 15 minutes)"; "$PY" "$HERE/c14_mcp_wait.py" "$BIN"
     cat "$( latest c14 )/verdict.txt" "$( latest c14 )/facts.json" >> "$BUNDLE" 2> /dev/null; fi

echo "=== C13"; "$HERE/c13_pinned_model.sh" "$BIN"
section "C13 pinned model"; dir=$( latest c13 ); cat "$dir/verdict.txt" >> "$BUNDLE"
for file in "$dir"/results-*.tsv "$dir"/spoken-*.txt; do [ -e "$file" ] && { echo "--- ${file##*/}"; cat "$file"; } >> "$BUNDLE"; done

echo; echo "Paste back: $BUNDLE"
