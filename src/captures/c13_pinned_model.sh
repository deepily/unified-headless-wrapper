#!/usr/bin/env bash
# C13 -- C9/C10 rerun with a pinned model.   usage: MODELS="<model> [<model> ...]" c13_pinned_model.sh jetski|agy
# Part B ran with model "auto", so its C9/C10 numbers aren't tied to one model. For each model:
#   1. one tool-using turn with hooks, to confirm --model reached the engine (modelName in the hook payload)
#   2. the pyramid probe, REPEAT times (default 3), with the persona launch argv plus --model
#   3. the spoken lines of every reply, so compliance can be read, not just counted (Part A caveat 2)
source "$( dirname "$0" )/common.sh"
BIN=${1:?usage: MODELS="<model> ..." c13_pinned_model.sh jetski|agy}; new_out "c13-$BIN"
if [ -z "${MODELS:-}" ]; then
    { echo "skipped: MODELS not set. Available models:"; "$BIN" models < /dev/null 2>&1 | head -40; } | tee "$OUT/verdict.txt"
    exit 0
fi
for model in $MODELS; do
    label="$BIN-$( printf '%s' "$model" | tr -c 'A-Za-z0-9.-' '_' )"
    jetski_engine "$BIN"; ENGINE+=( --model "$model" ); [ "$BIN" = jetski ] && ENGINE+=( --use_ls_chrome_devtools_mcp=false )
    WS=$( mktemp -d ); write_hooks "$WS"
    UHW_PROBE_LOG="$OUT/hook-$label.jsonl" "$PY" "$HERE/drive.py" --family jetski --cwd "$WS" --out "$OUT/frames-$label.jsonl" \
        --turn 'Run the shell command `ls` once, then say done.' -- "${ENGINE[@]}" > "$OUT/summary-$label.jsonl"
    seen=$( grep -ho '"modelName": "[^"]*"' "$OUT/hook-$label.jsonl" 2> /dev/null | sort -u | cut -d '"' -f 4 | tr '\n' ' ' )
    echo "model $model -> modelName in hook payload: ${seen:-none} · status: $( grep -o '"status": "[^"]*"' "$OUT/summary-$label.jsonl" | head -1 )" | tee -a "$OUT/verdict.txt"
    UHW_LABEL="$label" "$PY" "$HERE/c9_c10_pyramid_probe.py" --family jetski --repeat "${REPEAT:-3}" -- "${ENGINE[@]}" | tail -2 | tee -a "$OUT/verdict.txt"
    pyramid=$( ls -td "$HERE"/out/pyramid-"$label"-* | head -1 )
    cp "$pyramid/results.tsv" "$OUT/results-$label.tsv"
    "$PY" - "$pyramid" > "$OUT/spoken-$label.txt" <<'EOF'
import json, sys
from pathlib import Path
for frames in sorted( Path( sys.argv[ 1 ] ).glob( "frames-*.jsonl" ), key=lambda p: [ int( n ) for n in p.stem.split( "-" )[ 1: ] ] ):
    final = ""
    for line in frames.read_text().splitlines():
        frame = json.loads( line )[ "frame" ]
        if frame.get( "event" ) == "result": final = frame.get( "result", {} ).get( "response" ) or ""
    spoken = final.split( "\n<<<" )[ 0 ].strip().splitlines()
    print( f"[{frames.stem[ 7: ]}] " + " | ".join( line.strip()[ :160 ] for line in spoken[ :4 ] ) )
EOF
done
echo "VERDICT c13: see per-model lines above; spoken-*.txt holds every reply's spoken lines" | tee -a "$OUT/verdict.txt"
