#!/usr/bin/env bash
# C5 -- do the D4 launch flags keep the user-scope AH4L hooks out of a headless Claude child?   run from $LUPIN_ROOT
# Witness: every AH4L hook calls log_payload(), which writes {hook}-{ts}.json into $LUPIN_HOOK_LOG_DIR.
# Expected: A = full AH4L stack, B/C/D = nothing, E = pre_tool_use only, strict MCP = [].
# Run A is real: its SessionStart starts a notification listener and Stop may arm an "anything else?" ask.
source "$( dirname "$0" )/common.sh"
: "${LUPIN_ROOT:?set LUPIN_ROOT}"; new_out "c5-claude"; { claude --version < /dev/null 2>&1 || true; } > "$OUT/version.txt"
jq 'del(.hooks)' ~/.claude/settings.json > "$OUT/nohooks.json"
jq --slurpfile h "$LUPIN_ROOT/src/conf/claude-code-hooks.json" '. + {hooks: {PreToolUse: $h[0].hooks.PreToolUse}}' \
    "$OUT/nohooks.json" > "$OUT/guards.json"
PROMPT='Run the shell command `echo hi`, then reply with the single word done.'
probe() {                        # $1 = label; the rest = extra claude flags
    local witness; witness=$( mktemp -d ); mkdir -p "$witness/logs"
    LUPIN_HOOK_LOG_DIR=$witness/logs LUPIN_HOOK_SESSIONS_DIR=$witness/sessions HOOK_TTS_ENABLED=false \
        limited 180 claude -p "$PROMPT" --output-format json --dangerously-skip-permissions "${@:2}" > /dev/null 2> "$witness/err"
    printf '%-20s %s\n' "$1" "$( ls "$witness/logs" | sed -E 's/-[0-9].*//' | sort | uniq -c | xargs )" | tee -a "$OUT/verdict.txt"
}
probe "A baseline"
probe "B -user"          --setting-sources project,local
probe "C -user +base"    --setting-sources project,local --settings "$OUT/nohooks.json"
probe "D disableAll"     --settings '{"disableAllHooks":true}'
probe "E -user +guards"  --setting-sources project,local --settings "$OUT/guards.json"
printf '%-20s %s\n' "strict MCP" "$( claude -p hi --output-format stream-json --verbose --strict-mcp-config \
    | head -1 | jq -c '[.mcp_servers[]?.name]' )" | tee -a "$OUT/verdict.txt"
