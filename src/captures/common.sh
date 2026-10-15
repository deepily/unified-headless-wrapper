# common.sh -- sourced by every capture script. Nothing here touches global engine config.
set -u
HERE=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
PY=$( command -v python3 )

new_out() {                      # $1 = capture label; sets OUT
    OUT="$HERE/out/$1-$( date +%Y%m%dT%H%M%S )"; mkdir -p "$OUT"; echo "output: $OUT"
}

jetski_engine() {                # $1 = jetski|agy; sets ENGINE (the harness's own launch shape)
    ENGINE=( "$1" --input-format stream-json --output-format stream-json --dangerously-skip-permissions )
    [ "$1" = agy ] && ENGINE+=( --print-timeout 0 )
    { "$1" --version < /dev/null 2>&1 || true; } > "$OUT/version.txt"
}

claude_engine() {                # $1 = pinned session id; sets ENGINE with the D4 isolation flags
    ENGINE=( claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages
             --setting-sources project,local --strict-mcp-config --session-id "$1" )
    { claude --version < /dev/null 2>&1 || true; } > "$OUT/version.txt"
}

write_hooks() {                  # $1 = workspace. Project-level hooks only; HOOKS_FORMAT=A (named set, default) or B ("hooks")
    mkdir -p "$1/.agents"
    "$PY" - "$1/.agents/hooks.json" "$PY" "$HERE/probe_hook.py" "${HOOKS_FORMAT:-A}" <<'EOF'
import json, sys
path, python, hook, form = sys.argv[ 1: ]
entry  = lambda event: [ { "matcher": "*", "hooks": [ { "type": "command", "command": f"{python} {hook} {event}", "timeout": 10 } ] } ]
events = { "PreToolUse": entry( "pre_tool" ), "PostToolUse": entry( "post_tool" ) }
json.dump( { "uhw-probe": events } if form == "A" else { "hooks": events }, open( path, "w" ), indent=1 )
EOF
    cp "$1/.agents/hooks.json" "$OUT/hooks.json"
}

new_uuid() { "$PY" -c 'import uuid; print( uuid.uuid4() )'; }

limited() {                      # limited SECONDS cmd ...  (macOS has no timeout unless coreutils is installed)
    local seconds=$1; shift
    if command -v timeout > /dev/null; then timeout "$seconds" "$@"
    elif command -v gtimeout > /dev/null; then gtimeout "$seconds" "$@"
    else "$@"; fi
}
