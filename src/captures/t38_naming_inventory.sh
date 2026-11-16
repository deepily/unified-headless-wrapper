#!/usr/bin/env bash
# T38 engine-neutral naming inventory (2026-11-15). No model call; reads a lupin checkout, writes nothing to it.
# Answers, for one checkout: how many names carry an engine's name (cc, claude_code, claude.code, claude-code,
# ClaudeCode) where a persona is meant, on which surface each sits (configuration key, route, socket name, wire
# field, environment variable, file on disk, browser name, file name, internal identifier), and how much of it
# goes away on its own because the T19 switch-over list deletes the file that holds it.
# Three scopes: "tracked" (every tracked text file under src/), "code" (tracked code files; tests, generated
# bundles, research, ephemera and documentation left out), "survivors" (code minus what the T19 list deletes).
# Rerun after each lupin rename; the "summary" block is the tracked count.
# Usage: t38_naming_inventory.sh <path to the lupin checkout> [--names] [--ceiling <occurrences>]
#   --names     print every distinct name, not the first forty
#   --ceiling   the ratchet of D71 (engine-neutral naming): exit 1 when the survivors' occurrences exceed the number
set -u
LUPIN=${1:?usage: t38_naming_inventory.sh <path to the lupin checkout> [--names] [--ceiling <occurrences>]}; shift
ALL_NAMES=''; CEILING=''
while [ $# -gt 0 ]; do
    case "$1" in
        --names)   ALL_NAMES=--names; shift ;;
        --ceiling) CEILING=${2:?--ceiling needs a number}; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
HERE=$( cd "$( dirname "$0" )" && pwd )
T19="$HERE/t19_switch_over_inventory.sh"
INI="$LUPIN/src/conf/lupin-app.ini"
WORK=$( mktemp -d ); trap 'rm -rf "$WORK"' EXIT
hr()  { printf '\n== %s ==\n' "$1"; }
val() { printf '%-46s %s\n' "$1" "$2"; }

# One pattern for "an engine's name inside an identifier", and one that lifts the whole identifier out.
TOKEN='(^|[^A-Za-z0-9])cc[_-][a-z{$]|[_-]cc[_-]|[_-]cc([^A-Za-z0-9_-]|$)|claude[_.-]code|(^|[^A-Za-z0-9])CC_[A-Z]|_CC_|ClaudeCode|(^|[^A-Za-z0-9])C[Cc][A-Z][a-z]'
NAME='[A-Za-z0-9_.-]*(cc[_-]|[_-]cc|claude[_.-]code|CC_|ClaudeCode|C[Cc][A-Z][a-z])[A-Za-z0-9_.-]*'
CODE_EXT='\.(py|js|ts|tsx|sh|css|html|ini|sql|service|json|yml|yaml|toml|template)$'
NOT_CODE='/tests?/|/test_[^/]*$|_test\.py$|conftest\.py$|\.test\.[jt]s$|\.spec\.[jt]s$|/static/dist/|\.min\.|\.map$|main\.dart\.js$|^src/(rnd|ephemera|docs|resources)/|test_baseline\.json$'

cd "$LUPIN" || exit 2
git ls-files src > "$WORK/tracked"
grep -E "$CODE_EXT" "$WORK/tracked" | grep -vE "$NOT_CODE" > "$WORK/code"
# What the T19 list deletes: its file and dir rows whose disposition is Delete.
if [ -f "$T19" ]; then
    grep -E '^(file|dir)\|[a-z]+\|Delete\|' "$T19" | cut -d'|' -f1,4 > "$WORK/t19_delete"
else : > "$WORK/t19_delete"; fi
: > "$WORK/doomed_pattern"
while IFS='|' read -r KIND TARGET; do
    [ "$KIND" = dir ] && printf '^%s/\n' "$TARGET" >> "$WORK/doomed_pattern" || printf '^%s$\n' "$TARGET" >> "$WORK/doomed_pattern"
done < "$WORK/t19_delete"
if [ -s "$WORK/doomed_pattern" ]; then grep -vEf "$WORK/doomed_pattern" "$WORK/code" > "$WORK/survivors"; else cp "$WORK/code" "$WORK/survivors"; fi

files_with() { tr '\n' '\0' < "$2" | xargs -0 -r grep -IlE -- "$1" 2>/dev/null | wc -l; }
hits()       { tr '\n' '\0' < "$2" | xargs -0 -r grep -IhoE -- "$1" 2>/dev/null | wc -l; }
names()      { tr '\n' '\0' < "$2" | xargs -0 -r grep -IhoE -- "$1" 2>/dev/null; }

hr "checkout"
val host "$( hostname )"
val clock "$( TZ=America/New_York date '+%Y-%m-%d %H:%M:%S %Z' )"
val lupin_head "$( git rev-parse --short=9 HEAD 2>/dev/null || echo 'no git' )"
val configuration_file "$( git diff --quiet -- src/conf/lupin-app.ini 2>/dev/null && echo 'as committed' || echo 'MODIFIED in the working tree' )"
val t19_delete_rows "$( wc -l < "$WORK/t19_delete" ) (file and dir rows read from $( basename "$T19" ))"
val tracked_files "$( wc -l < "$WORK/tracked" )"
val code_files "$( wc -l < "$WORK/code" )"
val survivor_files "$( wc -l < "$WORK/survivors" )"

hr "any engine name, by scope (files | occurrences)"
for SCOPE in tracked code survivors; do
    val "$SCOPE" "$( files_with "$TOKEN" "$WORK/$SCOPE" ) | $( hits "$TOKEN" "$WORK/$SCOPE" )"
done
grep -E '\.md$' "$WORK/tracked" > "$WORK/markdown"
grep -E '/tests?/|/test_[^/]*$|_test\.py$|conftest\.py$|\.test\.[jt]s$|\.spec\.[jt]s$|test_baseline\.json$' "$WORK/tracked" | grep -vE '\.md$' > "$WORK/tests"
grep -vxFf "$WORK/survivors" "$WORK/code" > "$WORK/doomed"
val "code deleted by the T19 list" "$( files_with "$TOKEN" "$WORK/doomed" ) | $( hits "$TOKEN" "$WORK/doomed" )"
val "tests (inside tracked)" "$( files_with "$TOKEN" "$WORK/tests" ) | $( hits "$TOKEN" "$WORK/tests" )"
val "  claude_code in tests" "$( files_with 'claude_code' "$WORK/tests" ) | $( hits 'claude_code' "$WORK/tests" )"
val "markdown (inside tracked)" "$( files_with "$TOKEN" "$WORK/markdown" ) | $( hits "$TOKEN" "$WORK/markdown" )"

hr "the register's tokens (files | occurrences): code, then survivors"
for PATTERN in 'claude_code' 'claude\.code@' 'claude-code' 'ClaudeCode' 'cc_session_id' 'cc_pid' 'cc-listener-' 'cc-buffer-' 'cc_meta'; do
    val "$PATTERN" "$( files_with "$PATTERN" "$WORK/code" ) | $( hits "$PATTERN" "$WORK/code" )   survivors $( files_with "$PATTERN" "$WORK/survivors" ) | $( hits "$PATTERN" "$WORK/survivors" )"
done

hr "survivors by directory and extension (files holding any engine name)"
tr '\n' '\0' < "$WORK/survivors" | xargs -0 -r grep -IlE -- "$TOKEN" 2>/dev/null \
    | awk -F/ '{ n = split( $NF, part, "." ); print $2 " ." part[n] }' | sort | uniq -c | sort -rn

hr "surface 1: configuration keys (lupin-app.ini)"
grep -E '^[^#;=]*(^|[^a-z])(cc|claude code)( |$)[^=]*=' "$INI" | sed -E 's/ *=.*$//' | sort -u > "$WORK/keys"
val distinct_keys "$( wc -l < "$WORK/keys" )"
val "  cc session voice persona …" "$( grep -cE '^cc session voice persona ' "$WORK/keys" )"
val "  cc session … (other)" "$( grep -E '^cc session ' "$WORK/keys" | grep -cvE '^cc session voice persona ' )"
val "  cc transcript …" "$( grep -cE '^cc transcript ' "$WORK/keys" )"
val "  claude code job …" "$( grep -cE '^claude code job ' "$WORK/keys" )"
val "  none of the four" "$( grep -cvE '^(cc session|cc transcript|claude code job) ' "$WORK/keys" )"
grep -vE '^cc session voice persona ' "$WORK/keys" | sed 's/^/    /'
grep -E '^cc session voice persona ' "$WORK/keys" | awk '{ if ( NF <= 6 ) print "    " $0; else print "    cc session voice persona <name> " $(NF-1) " " $NF }' | sort | uniq -c | sort -rn | head -12

hr "surface 2: routes and socket names (survivors; string literals)"
names '"/[A-Za-z0-9_{}/-]*(cc-|claude-code)[A-Za-z0-9_{}/-]*"' "$WORK/survivors" | sort | uniq -c | sort -rn
val "cc-listener- (files | occurrences)" "$( files_with 'cc-listener-' "$WORK/survivors" ) | $( hits 'cc-listener-' "$WORK/survivors" )"

hr "surface 3: names inside string literals, survivors (wire fields, message kinds, stored values, storage keys)"
names "[\"'\`]$NAME[\"'\`]" "$WORK/survivors" | tr -d "\"'\`" | sort | uniq -c | sort -rn > "$WORK/quoted"
val distinct_quoted_names "$( wc -l < "$WORK/quoted" )"
if [ "$ALL_NAMES" = --names ]; then cat "$WORK/quoted"; else head -40 "$WORK/quoted"; fi

hr "surface 4: environment variables and upper-case constants (survivors)"
names '(^|[^A-Za-z0-9_])[A-Z][A-Z0-9_]*(CC_|CLAUDE_CODE)[A-Z0-9_]*|(^|[^A-Za-z0-9_])CC_[A-Z0-9_]+' "$WORK/survivors" | sed -E 's/^[^A-Z]//' | sort | uniq -c | sort -rn > "$WORK/upper"
val distinct_upper_names "$( wc -l < "$WORK/upper" )"
val "  the engine's own (CLAUDE_CODE_…)" "$( grep -cE ' CLAUDE_CODE_' "$WORK/upper" )"
if [ "$ALL_NAMES" = --names ]; then cat "$WORK/upper"; else head -25 "$WORK/upper"; fi

hr "surface 5: names on disk (survivors; patterns that end in a file extension)"
names "cc-[A-Za-z{}\$*_-]*\.(jsonl|json|log|pid|lock|txt)" "$WORK/survivors" | sort | uniq -c | sort -rn | head -20

hr "surface 6: browser names (survivors)"
grep -E '\.css$' "$WORK/survivors" > "$WORK/css"
names '\.(cc|claude-code)-[a-z0-9-]+' "$WORK/css" | sort -u > "$WORK/classes"
val distinct_css_classes "$( wc -l < "$WORK/classes" )"
sed -E 's/^\.((cc|claude-code)-[a-z]+).*/\1/' "$WORK/classes" | sort | uniq -c | sort -rn | sed 's/^/    /'
grep -E '\.(js|ts|tsx|html)$' "$WORK/survivors" > "$WORK/browser"
val browser_files_with_any "$( files_with "$TOKEN" "$WORK/browser" ) | $( hits "$TOKEN" "$WORK/browser" )"

hr "surface 7: file and directory names (tracked code paths that carry an engine name)"
grep -E '(^|/)[^/]*(cc[_-]|[_-]cc[_.-]|claude[_-]code)[^/]*(/|$)' "$WORK/code" > "$WORK/named_paths"
val named_paths "$( wc -l < "$WORK/named_paths" )"
val "  deleted by the T19 list" "$( [ -s "$WORK/doomed_pattern" ] && grep -cEf "$WORK/doomed_pattern" "$WORK/named_paths" || echo 0 )"
if [ -s "$WORK/doomed_pattern" ]; then grep -vEf "$WORK/doomed_pattern" "$WORK/named_paths" > "$WORK/named_survivors"; else cp "$WORK/named_paths" "$WORK/named_survivors"; fi
val "  surviving" "$( wc -l < "$WORK/named_survivors" )"
sed -E 's|/[^/]*$||' "$WORK/named_survivors" | sort | uniq -c | sort -rn | sed 's/^/    /' | head -20

hr "surface 8: internal identifiers (survivors; not inside a string literal)"
names "$NAME" "$WORK/survivors" | sort | uniq -c | sort -rn > "$WORK/every"
val distinct_names_all_surfaces "$( wc -l < "$WORK/every" )"
val occurrences_all_surfaces "$( awk '{ total += $1 } END { print total + 0 }' "$WORK/every" )"
[ "$ALL_NAMES" = --names ] && cat "$WORK/every"

hr "the sender address (claude.code@), survivors"
val "claude.code literal (files | occurrences)" "$( files_with 'claude\.code' "$WORK/survivors" ) | $( hits 'claude\.code' "$WORK/survivors" )"
tr '\n' '\0' < "$WORK/survivors" | xargs -0 -r grep -IlE -- 'claude\.code' 2>/dev/null | awk -F/ '{ print $2 }' | sort | uniq -c | sed 's/^/    /'

hr "rename families: where each is read (survivors; files | occurrences)"
family() { val "$1" "$( files_with "$2" "$WORK/survivors" ) | $( hits "$2" "$WORK/survivors" )"; }
family "voice persona keys"                 'cc session voice persona'
family "worker voice mode key"              'cc session worker default voice mode'
family "transcript keys"                    'cc transcript (backlog|block|coalesce|poll|watcher)'
family "transcript route"                   'cc-transcript'
family "transcript message kinds"           'cc_transcript_(watch|unwatch|state|append)'
family "transcript field cc_session_id"     'cc_session_id'
family "broadcast route"                    'broadcast-to-cc-sessions'
family "listener socket name"               'cc-listener-'
family "  of which prefix tests"            'startswith\( *.cc-listener-'
family "shared key file name"               'notification-api-claude-code|claude_code_simple_key'
family "hooks virtual environment variable" '(^|[^A-Z_])(LUPIN_)?CC_VENV'
family "browser storage keys"               'notifications_cc_(focus_state|hide_inactive_strip)'
family "element ids (notifications-cc-…)"   'notifications-cc-[a-z-]+'
family "element ids (multiplexer-cc-…)"     'multiplexer-cc-[a-z-]+'
family "the Claude job (ClaudeCodeJob, …)"  'ClaudeCode(Job|Dispatcher)|claude code job|agents[./]claude_code|orchestration[./]claude_code'
val "legacy notifications.js alone"         "$( grep -IcE -- "$TOKEN" src/lupin_app/static/js/notifications.js 2>/dev/null || echo absent ) lines"

hr "summary"
val survivors_files_occurrences "$( files_with "$TOKEN" "$WORK/survivors" ) | $( hits "$TOKEN" "$WORK/survivors" )"
val configuration_keys "$( wc -l < "$WORK/keys" )"
val quoted_names "$( wc -l < "$WORK/quoted" )"
val upper_case_names "$( wc -l < "$WORK/upper" )"
val css_classes "$( wc -l < "$WORK/classes" )"
val named_paths_surviving "$( wc -l < "$WORK/named_survivors" )"
if [ -n "$CEILING" ]; then
    NOW=$( hits "$TOKEN" "$WORK/survivors" )
    if [ "$NOW" -le "$CEILING" ]; then val ratchet "ok  $NOW at or under the ceiling $CEILING"; else val ratchet "FAILED  $NOW over the ceiling $CEILING"; exit 1; fi
fi
