#!/usr/bin/env bash
# agy_round.sh -- every Jetski capability capture (C11-C14, C11b, C11c, C14b) rerun on AGY, plus C13 on AGY's models.
# Run on the test VM from the repo root. About 75 min. Results land in src/captures/out/ (verdicts and facts are tracked).
#   MODELS="a b"  overrides the four default models; MODELS=none skips C13; SKIP_WAIT=1 skips the 15-min C14
source "$( dirname "$0" )/common.sh"
command -v agy > /dev/null || { echo "agy is not on PATH on this machine"; exit 2; }
STAMP=$( date +%Y%m%dT%H%M%S ); mkdir -p "$HERE/out"; BUNDLE="$HERE/out/agy-round-$STAMP.txt"
latest()  { ls -td "$HERE"/out/"$1"-agy-* 2> /dev/null | head -1; }
section() { printf '\n## %s\n' "$1" >> "$BUNDLE"; }

# same model ids as Jetski (`agy models` == `jetski models`), so AGY and Jetski C13 compare directly
MODELS=${MODELS-"opus-5.5-high gemini-3.8-flash-high gemini-launch-candidate-high gemini-flash-next"}
export MODELS=${MODELS:-none}
echo "# AGY round $STAMP · $( uname -sm ) · agy $( agy --version < /dev/null 2>&1 | head -1 ) · MODELS=$MODELS" > "$BUNDLE"

echo "=== C11 C12 C14";  SKIP_WAIT=${SKIP_WAIT:-0} MODELS=none "$HERE/capabilities_followup.sh" agy
for label in c11 c12 c14; do section "$label"; cat "$( latest $label )/verdict.txt" >> "$BUNDLE" 2> /dev/null; done
echo "=== C11b";         "$PY" "$HERE/c11b_followups.py" agy;  section "c11b"; cat "$( latest c11b )/verdict.txt" >> "$BUNDLE"
echo "=== C11c";         "$PY" "$HERE/c11c_final.py" agy;      section "c11c"; cat "$( latest c11c )/verdict.txt" >> "$BUNDLE"
if [ "${SKIP_WAIT:-0}" != 1 ]; then
    echo "=== C14b";     WAITS=200 MCP_TIMEOUT_MS=900000 "$PY" "$HERE/c14_mcp_wait.py" agy; section "c14b"; cat "$( latest c14 )/verdict.txt" >> "$BUNDLE"
fi
echo "=== C13 ($MODELS)"; UHW_RULES=v2 "$HERE/c13_pinned_model.sh" agy; section "c13"; cat "$( latest c13 )/verdict.txt" >> "$BUNDLE"
echo; echo "Done. Commit and push: git add src/captures && git commit -m 'AGY round results' && git push"
