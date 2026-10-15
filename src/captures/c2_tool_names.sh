#!/usr/bin/env bash
# C2 -- which tool names and argument keys does Jetski emit, in the stream and in hook payloads?   usage: c2_tool_names.sh jetski|agy
# Result: out/c2-*/tool-map.tsv, the input for the Jetski <-> Claude tool-name mapping in the tool gate.
source "$( dirname "$0" )/common.sh"
BIN=${1:?usage: c2_tool_names.sh jetski|agy}; new_out "c2-$BIN"; jetski_engine "$BIN"
WS=$( mktemp -d ); write_hooks "$WS"
printf 'the zebra is here\n' > "$WS/notes.txt"; mkdir -p "$WS/sub"; printf 'no animals\n' > "$WS/sub/other.txt"
export UHW_PROBE_LOG="$OUT/hook.jsonl" UHW_PROBE_TAG="c2-$BIN"
"$PY" "$HERE/drive.py" --family jetski --cwd "$WS" --out "$OUT/frames.jsonl" \
    --turn 'Do each step with the most specific tool you have, one tool call per step: 1) list the files in this directory, 2) read notes.txt, 3) search every file for the word zebra, 4) find all files named *.txt, 5) create new.txt containing hello, 6) edit new.txt to replace hello with goodbye, 7) run the shell command `echo done`, 8) fetch https://example.com. Then list the tool names you used.' \
    -- "${ENGINE[@]}" | tee "$OUT/summary.jsonl"
"$PY" "$HERE/facts.py" "$OUT" --check c2
column -t -s $'\t' "$OUT/tool-map.tsv" 2>/dev/null || cat "$OUT/tool-map.tsv"
