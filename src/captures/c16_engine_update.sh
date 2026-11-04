#!/usr/bin/env bash
# C16 -- how does the binary update itself, where does it live, what does --version cost?   usage: c16_engine_update.sh jetski|agy
# No model turn. Informational for D48: the vetting cache keys on inode and mtime; this records what those look like,
# what --help says about update/version/channel, which settings files mention updating, and whether a --version run
# or an idle launch changed the binary underneath us.
source "$( dirname "$0" )/common.sh"
BIN=${1:?usage: c16_engine_update.sh jetski|agy}; new_out "c16-$BIN"
stat_binary() {                  # prints path, resolved path, inode, mtime, size, owner, writable-by-me
    local path; path=$( command -v "$BIN" ); local real; real=$( readlink -f "$path" 2>/dev/null || python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$path" )
    if stat -f '%i %m %z %Su' "$real" > /dev/null 2>&1; then read -r ino mtime size owner < <( stat -f '%i %m %z %Su' "$real" )
    else read -r ino mtime size owner < <( stat -c '%i %Y %s %U' "$real" ); fi
    local writable=no; [ -w "$real" ] && writable=yes
    printf '{"path":"%s","real":"%s","inode":%s,"mtime":%s,"size":%s,"owner":"%s","writable":"%s"}' "$path" "$real" "$ino" "$mtime" "$size" "$owner" "$writable"
}
before=$( stat_binary )
start=$( date +%s.%N ); { "$BIN" --version < /dev/null 2>&1 || true; } > "$OUT/version.txt"; end=$( date +%s.%N )
version_seconds=$( python3 -c "print( round( $end - $start, 2 ) )" )
after_version=$( stat_binary )
{ "$BIN" --help < /dev/null 2>&1 || true; } > "$OUT/help.txt"
grep -n -i 'update\|version\|channel\|nightly\|release' "$OUT/help.txt" > "$OUT/help-update-lines.txt" || true
grep -rl -i 'update' ~/.gemini/*.json ~/.gemini/config ~/.gemini/jetski ~/.gemini/antigravity-cli 2>/dev/null | grep -v '/brain/\|/mcp/\|/conversations/' > "$OUT/settings-mentioning-update.txt" || true
# an idle launch: start the engine with an empty stdin and let it exit; does the binary change?
jetski_engine "$BIN"; WS=$( mktemp -d )
( cd "$WS" && limited 90 "${ENGINE[@]}" < /dev/null > "$OUT/idle-launch.out" 2>&1 || true )
after_launch=$( stat_binary )
python3 - "$OUT" "$before" "$after_version" "$after_launch" "$version_seconds" <<'PY'
import json, sys
out, before, after_version, after_launch, seconds = sys.argv[ 1: ]
b, v, l = ( json.loads( x ) for x in ( before, after_version, after_launch ) )
facts = { "before": b, "after_version": v, "after_launch": l, "version_seconds": float( seconds ),
          "version": open( f"{out}/version.txt" ).read().strip().splitlines()[ :1 ],
          "help_update_lines": open( f"{out}/help-update-lines.txt" ).read().splitlines(),
          "settings_mentioning_update": open( f"{out}/settings-mentioning-update.txt" ).read().splitlines() }
json.dump( facts, open( f"{out}/facts.json", "w" ), indent=1 )
same = lambda x, y: ( x[ "inode" ], x[ "mtime" ], x[ "size" ] ) == ( y[ "inode" ], y[ "mtime" ], y[ "size" ] )
lines = [ f"{'version':<40} {facts[ 'version' ]}",
          f"{'binary (real path, owner, writable)':<40} {b[ 'real' ]} {b[ 'owner' ]} writable={b[ 'writable' ]}",
          f"{'--version wall time (s)':<40} {seconds}",
          f"{'binary changed by --version':<40} {'no' if same( b, v ) else 'YES'}",
          f"{'binary changed by an idle launch':<40} {'no' if same( v, l ) else 'YES'}",
          f"{'--help lines on update/version/channel':<40} {len( facts[ 'help_update_lines' ] )} (help-update-lines.txt)",
          f"{'settings files mentioning update':<40} {facts[ 'settings_mentioning_update' ] or 'none'}",
          f"VERDICT c16: informational; D48 keys on inode+mtime; see facts.json" ]
open( f"{out}/verdict.txt", "w" ).write( "\n".join( lines ) + "\n" ); print( "\n".join( lines ) )
PY
