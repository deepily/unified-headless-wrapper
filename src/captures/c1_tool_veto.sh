#!/usr/bin/env bash
# C1 -- can a PreToolUse hook veto a real tool call in headless stream-json mode?   usage: c1_tool_veto.sh jetski|agy
# Project-level hooks in a throwaway workspace; nothing global is touched. HOOKS_FORMAT=B retries the other config shape.
source "$( dirname "$0" )/common.sh"
BIN=${1:?usage: c1_tool_veto.sh jetski|agy}; new_out "c1-$BIN"; jetski_engine "$BIN"
WS=$( mktemp -d ); write_hooks "$WS"
export UHW_PROBE_LOG="$OUT/hook.jsonl" UHW_PROBE_TAG="c1-$BIN"
"$PY" "$HERE/drive.py" --family jetski --cwd "$WS" --out "$OUT/frames.jsonl" \
    --turn 'Run these two shell commands as two separate tool calls, in this order: `touch allowed.marker`, then `touch UHW_DENY_ME.marker`. Then say which succeeded and quote any error you received.' \
    -- "${ENGINE[@]}" | tee "$OUT/summary.jsonl"
"$PY" "$HERE/facts.py" "$OUT" --check c1 --workspace "$WS"
