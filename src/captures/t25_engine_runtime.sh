#!/usr/bin/env bash
# t25_engine_runtime.sh: what runtime each engine binary on this host is, and whether the heap
# setting of the host-capacity decision (D60, register item T25, parts 5 and 6) can reach it.
# Row 61 of "Outstanding actions".
#
# Zero tokens: it starts no engine turn. It reads each engine's binary on disk (type, size,
# counts of marker strings), the engine processes already running under this account (their
# executable and their children) and one settings file in the lupin checkout. It writes one file
# under src/captures/out/ and nothing else. It prints no secret, token or email address.
#
# Usage: src/captures/t25_engine_runtime.sh [path of the lupin checkout, default /mnt/lupin-data/lupin]

set -u
HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LUPIN="${1:-/mnt/lupin-data/lupin}"
STAMP="$( TZ=America/New_York date +%Y%m%d )"
OUT="$HERE/out/t25-engine-runtime-$( hostname -s )-$STAMP.txt"

count_marker() { grep -a -c -e "$2" "$1" 2>/dev/null || true; }

report_engine() {
  local engine="$1" found path
  found="$( command -v "$engine" 2>/dev/null || true )"
  if [ -z "$found" ]; then printf '%-34s %s\n' "$engine.binary" "not on PATH"; return; fi
  path="$( readlink -f "$found" )"
  printf '%-34s %s\n' "$engine.binary"                 "$path"
  printf '%-34s %s\n' "$engine.version"                "$( timeout 20 "$found" --version 2>/dev/null | head -1 )"
  printf '%-34s %s\n' "$engine.file"                   "$( file -b "$path" | cut -d, -f1-2 )"
  printf '%-34s %s\n' "$engine.size_bytes"             "$( stat -c %s "$path" )"
  printf '%-34s %s\n' "$engine.go_runtime_strings"     "$( count_marker "$path" 'runtime\.gopanic' )"
  printf '%-34s %s\n' "$engine.go_version_string"      "$( grep -a -o -m1 'go1\.[0-9]*\.[0-9]*' "$path" 2>/dev/null | head -1 )"
  printf '%-34s %s\n' "$engine.v8_strings"             "$( count_marker "$path" 'heap_size_limit\|V8_Fatal' )"
  printf '%-34s %s\n' "$engine.bun_strings"            "$( count_marker "$path" 'Bun v\|BUN_' )"
  printf '%-34s %s\n' "$engine.max_old_space_size"     "$( count_marker "$path" 'max-old-space-size' )"
  printf '%-34s %s\n' "$engine.node_options_string"    "$( count_marker "$path" 'NODE_OPTIONS' )"
  printf '%-34s %s\n' "$engine.no_relaunch_string"     "$( count_marker "$path" 'GEMINI_CLI_NO_RELAUNCH' )"
  local pid child running=0
  for pid in $( pgrep -u "$( id -u )" -x "$engine" 2>/dev/null ); do
    running=$(( running + 1 ))
    printf '%-34s %s\n' "$engine.live[$pid].executable" "$( basename "$( readlink "/proc/$pid/exe" 2>/dev/null )" )"
    printf '%-34s %s\n' "$engine.live[$pid].rss_kB"     "$( awk '/VmRSS/{ print $2 }' "/proc/$pid/status" 2>/dev/null )"
    printf '%-34s %s\n' "$engine.live[$pid].threads"    "$( awk '/Threads/{ print $2 }' "/proc/$pid/status" 2>/dev/null )"
    for child in $( pgrep -P "$pid" 2>/dev/null ); do
      printf '%-34s %s\n' "$engine.live[$pid].child" "$( cat "/proc/$child/comm" 2>/dev/null )"
    done
  done
  printf '%-34s %s\n' "$engine.live_processes" "$running"
}

{
  echo "# t25_engine_runtime.sh on $( hostname -s ), $( TZ=America/New_York date '+%Y-%m-%d %H:%M' ) US Eastern"
  echo "# A marker count is the number of lines of the binary that hold the string; 0 means the string is absent."
  for engine in agy jetski claude; do report_engine "$engine"; echo; done
  printf '%-34s %s\n' "node_processes_of_this_account"  "$( pgrep -u "$( id -u )" -x node 2>/dev/null | wc -l )"
  printf '%-34s %s\n' "NODE_OPTIONS_in_this_shell"      "${NODE_OPTIONS:-unset}"
  INI="$LUPIN/src/conf/lupin-app.ini"
  if [ -r "$INI" ]; then
    printf '%-34s %s\n' "lupin_ini.kernel_keys"         "$( grep -c -i '^kernel ' "$INI" || true )"
    printf '%-34s %s\n' "lupin_ini.heap_keys"           "$( grep -c -i 'heap mebibytes' "$INI" || true )"
    printf '%-34s %s\n' "lupin_ini.quota_keys"          "$( grep -c -i '^kernel engine quota' "$INI" || true )"
  else
    printf '%-34s %s\n' "lupin_ini"                     "not readable at $INI"
  fi
} | tee "$OUT"
echo "written: $OUT"
