#!/usr/bin/env bash
# C20 (D60, 2026-11-10): does the AGY binary relaunch itself as a child under the kernel's launch line,
# and does GEMINI_CLI_NO_RELAUNCH=true + NODE_OPTIONS stop it? Two one-line prompts; ~zero tokens.
# Usage: MODEL=gemini-3.8-flash-high ./c20_relaunch_tree.sh agy     (jetski on the cloud workstation)
set -u
ENGINE="${1:-agy}"; MODEL="${MODEL:-}"
OUT="src/captures/out/c20-$( date +%Y%m%d-%H%M%S )"; mkdir -p "$OUT"
leg() {   # $1 = leg name, rest = environment assignments
  local name="$1"; shift
  echo "== leg $name: env $* ==" | tee -a "$OUT/verdict.txt"
  ( env "$@" "$ENGINE" ${MODEL:+--model "$MODEL"} --mode auto -p "Reply with the single word READY and nothing else." \
      > "$OUT/$name.stdout" 2> "$OUT/$name.stderr" ) &
  local pid=$!
  sleep 4
  { echo "-- process tree under $pid --"; pstree -p -a "$pid" 2>/dev/null || ps -o pid,ppid,rss,args --ppid "$pid" -p "$pid"; } | tee "$OUT/$name.tree" | tee -a "$OUT/verdict.txt"
  local nodes; nodes=$( pstree -p "$pid" 2>/dev/null | grep -o 'node([0-9]*)\|agy([0-9]*)\|gemini([0-9]*)' | wc -l )
  echo "engine-like processes under the launched pid: $nodes" | tee -a "$OUT/verdict.txt"
  { echo "-- heap limit seen by the engine's node --"; node -e 'console.log((require("v8").getHeapStatistics().heap_size_limit/1048576).toFixed(0)+" MiB")' 2>/dev/null; } | env "$@" bash | tee -a "$OUT/verdict.txt"
  wait "$pid"; echo "exit $? ; stdout: $( tr -d '\n' < "$OUT/$name.stdout" | cut -c1-120 )" | tee -a "$OUT/verdict.txt"
}
leg a-default   X_C20=1
leg b-norelaunch GEMINI_CLI_NO_RELAUNCH=true NODE_OPTIONS=--max-old-space-size=6144
echo; echo "Verdict in $OUT/verdict.txt — leg a with 2 engine-like processes and leg b with 1 confirms the relaunch and the switch (D60 part 6)."
