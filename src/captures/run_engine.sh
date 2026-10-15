#!/usr/bin/env bash
# run_engine.sh agy|jetski -- every Jetski-family capture for one engine, one bundle to paste back.
#   Part A (local, now):        ./run_engine.sh agy
#   Part B (work laptop, later): ./run_engine.sh jetski
# Runs C1, C2, C4 and C9/C10 always; C3 only when MCP_CONFIG is set (otherwise it records the --help discovery and skips).
# Each capture is independent: a failure is recorded and the next one still runs.
source "$( dirname "$0" )/common.sh"
BIN=${1:?usage: run_engine.sh agy|jetski}
command -v "$BIN" > /dev/null || { echo "$BIN is not on PATH on this machine"; exit 2; }
STAMP=$( date +%Y%m%dT%H%M%S ); BUNDLE="$HERE/out/$BIN-bundle-$STAMP.txt"; mkdir -p "$HERE/out"
STREAM=( "$BIN" --input-format stream-json --output-format stream-json --dangerously-skip-permissions )
[ "$BIN" = agy ] && STREAM+=( --print-timeout 0 )

{ echo "# $BIN capture bundle $STAMP · $( uname -sm )"; echo "version: $( "$BIN" --version < /dev/null 2>&1 | head -1 )"; } > "$BUNDLE"
section() { printf '\n## %s\n' "$1" >> "$BUNDLE"; }
latest()  { ls -td "$HERE"/out/"$1"-"$BIN"-* 2>/dev/null | head -1; }

for capture in c1_tool_veto c2_tool_names c4_pin_conversation; do
    echo "=== $capture"; "$HERE/$capture.sh" "$BIN"
    label=${capture%%_*}; dir=$( latest "$label" ); section "$label"
    cat "$dir/verdict.txt" "$dir/facts.json" >> "$BUNDLE" 2>/dev/null || echo "no output (see $dir)" >> "$BUNDLE"
    [ "$label" = c2 ] && cat "$dir/tool-map.tsv" >> "$BUNDLE" 2>/dev/null
done

echo "=== c3_mcp_identity"; section "c3"
if [ -n "${MCP_CONFIG:-}" ]; then
    "$HERE/c3_mcp_identity.sh" "$BIN"; dir=$( latest c3 ); cat "$dir/verdict.txt" "$dir/facts.json" >> "$BUNDLE" 2>/dev/null
else
    "$HERE/c3_mcp_identity.sh" "$BIN" > /dev/null; dir=$( latest c3 )
    { echo "skipped: MCP_CONFIG not set. MCP-related --help lines:"; cat "$dir/discovery.txt"; } >> "$BUNDLE"
fi

echo "=== c9_c10_pyramid_probe"; section "c9/c10"
UHW_LABEL="$BIN" "$PY" "$HERE/c9_c10_pyramid_probe.py" --family jetski --repeat "${REPEAT:-1}" -- "${STREAM[@]}" | tail -2 >> "$BUNDLE"
cat "$( ls -td "$HERE"/out/pyramid-$BIN-* | head -1 )/results.tsv" >> "$BUNDLE"

echo; echo "Paste back: $BUNDLE"
