#!/usr/bin/env bash
# C4 -- can a Jetski conversation id be chosen before spawn?   usage: c4_pin_conversation.sh jetski|agy
# Not blocking: the harness keys identity on the persona id, which is known before spawn; this only decides
# whether the conversation id must be learned from the init frame and stored.
source "$( dirname "$0" )/common.sh"
BIN=${1:?usage: c4_pin_conversation.sh jetski|agy}; new_out "c4-$BIN"; jetski_engine "$BIN"
{ "$BIN" --help < /dev/null 2>&1 | grep -n -i -E 'conversation|session' > "$OUT/discovery.txt"; } || true
WANT=$( new_uuid ); WS=$( mktemp -d )
"$PY" "$HERE/drive.py" --family jetski --cwd "$WS" --out "$OUT/frames-1.jsonl" \
    --turn 'Remember the word PELICAN. Reply only OK.' -- "${ENGINE[@]}" --conversation "$WANT" | tee "$OUT/summary-1.jsonl"
GOT=$( "$PY" -c 'import json,sys; print( next( ( json.loads( l ).get( "session" ) or "" ) for l in open( sys.argv[ 1 ] ) if "results" in l ) )' "$OUT/summary-1.jsonl" )
"$PY" "$HERE/drive.py" --family jetski --cwd "$WS" --out "$OUT/frames-2.jsonl" \
    --turn 'What word did I ask you to remember? One word.' -- "${ENGINE[@]}" --conversation "${GOT:-$WANT}" | tee "$OUT/summary-2.jsonl"
"$PY" "$HERE/facts.py" "$OUT" --check c4 --pinned "$WANT"
