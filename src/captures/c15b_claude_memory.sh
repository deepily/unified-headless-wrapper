#!/usr/bin/env bash
# C15b -- does ~/.claude/CLAUDE.md still load under the D4 launch flags?   run on a Claude host with AH4L installed
# Decides where planning-is-prompting's global mandates live on Claude (T11 spec Section 8): if the codeword comes back,
# ~/.claude/CLAUDE.md is a live surface under --setting-sources project,local; if not, the mandates join layer 5.
# A codeword is appended to ~/.claude/CLAUDE.md and removed on exit; nothing else is touched. Tools are denied by a
# generated --settings file, so the codeword can only come from what the engine loaded.
source "$( dirname "$0" )/common.sh"
new_out "c15b-claude"; { claude --version < /dev/null 2>&1 || true; } > "$OUT/version.txt"
MEMORY=~/.claude/CLAUDE.md; CODE="UHWCODE-GLOBALMEMORY"
[ -f "$MEMORY" ] && cp "$MEMORY" "$OUT/CLAUDE.md.backup"
restore() { if [ -f "$OUT/CLAUDE.md.backup" ]; then cp "$OUT/CLAUDE.md.backup" "$MEMORY"; else rm -f "$MEMORY"; fi; }
trap restore EXIT INT TERM HUP
mkdir -p ~/.claude; printf '\n\nThe global memory codeword is %s.\n' "$CODE" >> "$MEMORY"
cat > "$OUT/deny-all.json" <<JSON
{ "hooks": { "PreToolUse": [ { "matcher": "", "hooks": [ { "type": "command", "timeout": 5,
    "command": "printf '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"C15b denies every tool\"}}'" } ] } ] } }
JSON
WS=$( mktemp -d ); cd "$WS"
PROMPT='Do not use any tools. List every codeword of the form UHWCODE-<letters> in your instructions or context, separated by spaces, or NONE.'
reply() {                        # $1 = label; the rest = claude flags
    local text; text=$( limited 180 claude -p "$PROMPT" --output-format json --dangerously-skip-permissions "${@:2}" 2> "$OUT/$1.err" | jq -r '.result // empty' )
    printf '%-28s %s\n' "$1" "$( grep -o "$CODE" <<< "$text" > /dev/null && echo loaded || echo MISSING )" | tee -a "$OUT/verdict.txt"
    printf '%s\n' "$text" > "$OUT/$1.reply"
}
reply "A baseline"             --settings "$OUT/deny-all.json"
reply "B D4 flags"             --setting-sources project,local --settings "$OUT/deny-all.json" --strict-mcp-config
reply "C D4 + append prompt"   --setting-sources project,local --settings "$OUT/deny-all.json" --strict-mcp-config --append-system-prompt "You are a probe persona."
echo "VERDICT c15b: see the three rows above; B decides the T11 spec Section 8 question" | tee -a "$OUT/verdict.txt"
