#!/usr/bin/env bash
# C6 -- what does a control_request interrupt return, and does the Claude process survive it?   run after C5 passes
source "$( dirname "$0" )/common.sh"
new_out "c6-claude"; PIN=$( new_uuid ); claude_engine "$PIN"; WS=$( mktemp -d )
"$PY" "$HERE/drive.py" --family claude --cwd "$WS" --out "$OUT/frames.jsonl" --interrupt-after-deltas 15 \
    --turn 'count from 1 to 300, one number per line, nothing else.' \
    --turn 'What was the last number you wrote? Answer with the number only.' \
    -- "${ENGINE[@]}" | tee "$OUT/summary.jsonl"
"$PY" "$HERE/facts.py" "$OUT" --check c6 --pinned "$PIN"
