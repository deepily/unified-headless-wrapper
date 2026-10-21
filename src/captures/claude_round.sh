#!/usr/bin/env bash
# claude_round.sh -- the Claude side of Phase 0, plus the format probe v2 (Linux dev server, from the repo root).
#   C5  hook isolation: do the launch flags keep AH4L's user-scope hooks out?   (needs LUPIN_ROOT, jq)   about 3 min
#   C6  control_request interrupt: does the process survive?                                        about 1 min
#   C7  a message written mid-turn: absorbed, queued or dropped?                                    about 2 min
#   C9v2 format probe, rules v2, 3 repeats, on Claude Code (CLAUDE_MODEL, default opus)            about 10 min
#   C9v2 the same on AGY for comparison (SKIP_AGY=1 skips)                                          about 10 min
# Results land in src/captures/out/ and are committed (only verdicts, facts, tables and spoken lines are tracked).
source "$( dirname "$0" )/common.sh"
: "${LUPIN_ROOT:?set LUPIN_ROOT to your lupin checkout, e.g. export LUPIN_ROOT=~/projects/lupin}"
command -v claude > /dev/null || { echo "claude is not on PATH"; exit 2; }
command -v jq > /dev/null || { echo "jq is required for C5 (sudo apt install jq)"; exit 2; }
STAMP=$( date +%Y%m%dT%H%M%S ); mkdir -p "$HERE/out"; BUNDLE="$HERE/out/claude-round-$STAMP.txt"
latest()  { ls -td "$HERE"/out/"$1"-* 2> /dev/null | head -1; }
section() { printf '\n## %s\n' "$1" >> "$BUNDLE"; }
echo "# Claude round $STAMP · $( uname -sm ) · claude $( claude --version < /dev/null 2>&1 | head -1 ) · agy $( agy --version < /dev/null 2>&1 | head -1 )" > "$BUNDLE"

echo "=== C5 (run A is a real AH4L session: a listener may start and an 'anything else?' may be spoken)"
"$HERE/c5_hook_isolation.sh"; section "C5 hook isolation"; cat "$( latest c5-claude )/verdict.txt" >> "$BUNDLE"

for capture in c6_claude_interrupt c7_claude_midturn; do
    echo "=== $capture"; "$HERE/$capture.sh"; label=${capture%%_*}
    section "$label"; cat "$( latest "$label"-claude )/verdict.txt" >> "$BUNDLE"
done

echo "=== C9 v2 on Claude Code"
CLAUDE_STREAM=( claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages
                --setting-sources project,local --strict-mcp-config --dangerously-skip-permissions --model "${CLAUDE_MODEL:-opus}" )
UHW_RULES=v2 UHW_LABEL=claude-v2 "$PY" "$HERE/c9_c10_pyramid_probe.py" --family claude --repeat 3 -- "${CLAUDE_STREAM[@]}" | tail -2 > "$HERE/out/.c9-claude"
section "C9 v2 Claude Code (${CLAUDE_MODEL:-opus})"; cat "$HERE/out/.c9-claude" "$( latest pyramid-claude-v2 )/results.tsv" "$( latest pyramid-claude-v2 )/spoken.txt" >> "$BUNDLE"

if [ "${SKIP_AGY:-0}" != 1 ] && command -v agy > /dev/null; then
    echo "=== C9 v2 on AGY"
    UHW_RULES=v2 UHW_LABEL=agy-v2 "$PY" "$HERE/c9_c10_pyramid_probe.py" --family jetski --repeat 3 -- \
        agy --input-format stream-json --output-format stream-json --dangerously-skip-permissions --print-timeout 0 | tail -2 > "$HERE/out/.c9-agy"
    section "C9 v2 AGY"; cat "$HERE/out/.c9-agy" "$( latest pyramid-agy-v2 )/results.tsv" "$( latest pyramid-agy-v2 )/spoken.txt" >> "$BUNDLE"
fi
rm -f "$HERE"/out/.c9-*
echo; echo "Done. Commit and push: git add src/captures/out && git commit -m 'Claude round results' && git push"
