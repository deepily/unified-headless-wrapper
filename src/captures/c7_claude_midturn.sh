#!/usr/bin/env bash
# C7 -- a user message written to stdin during a tool call: absorbed into the running turn, queued, or dropped?   run after C5
source "$( dirname "$0" )/common.sh"
new_out "c7-claude"; PIN=$( new_uuid ); claude_engine "$PIN"; WS=$( mktemp -d )
"$PY" "$HERE/drive.py" --family claude --cwd "$WS" --out "$OUT/frames.jsonl" --linger 60 \
    --inject-on-tool 'Also, at the very end of your reply, say the word BANANA.' \
    --turn 'Run the shell command `sleep 15 && echo slept`, then say the word APPLE.' \
    -- "${ENGINE[@]}" --replay-user-messages --dangerously-skip-permissions | tee "$OUT/summary.jsonl"
"$PY" "$HERE/facts.py" "$OUT" --check c7
