#!/usr/bin/env bash
# T14 internal tools, read from the host at zero tokens (2026-11-16). No model call and no engine launch
# that starts a turn: the engine is asked only for its version and its release notes. Everything else is
# read from files: a finished C17 run under src/captures/out/, the engine binary, and the skills the
# vendor ships beside it.
# Answers, for one engine binary on one host:
#   1. what the finished C17 run shows, counted from its frames rather than from its verdict line;
#   2. what the list of tool names in the engine's first frame is, set against what a launch accepts;
#   3. what the vendor's own record says the grantable built-in tools are, and what manage_task is;
#   4. how each built-in tool named in the role table fares against 1 to 3.
# Usage: t14_internal_tools_inventory.sh [agy|jetski] [C17 output directory]
#        (default agy; default directory: the newest src/captures/out/c17-<engine>-*)
set -u
ENGINE=${1:-agy}
HERE=$( cd "$( dirname "$0" )" && pwd )
RUN=${2:-$( ls -d "$HERE"/out/c17-"$ENGINE"-* 2>/dev/null | sort | tail -1 )}
BIN=$( command -v "$ENGINE" ) || { echo "no $ENGINE on PATH"; exit 2; }
REAL=$( readlink -f "$BIN" )
WORK=$( mktemp -d "${TMPDIR:-/tmp}/t14-probe.XXXXXX" )
trap 'rm -rf "$WORK"' EXIT
hr()  { printf '\n== %s ==\n' "$1"; }
val() { printf '%-46s %s\n' "$1" "$2"; }
# quiet_run <seconds> <output file> <command...>: no terminal, hard kill, output to a file (as in the T34 script).
quiet_run() {
    local limit=$1 out=$2; shift 2
    ( cd "$WORK" && setsid -w timeout -k 5 "$limit" "$@" < /dev/null > "$out" 2> "$out.err" )
}

hr "host and engine"
val host "$( hostname )"
val clock "$( TZ=America/New_York date '+%Y-%m-%d %H:%M:%S %Z' )"
val engine "$ENGINE"
val binary "$REAL"
quiet_run 20 "$WORK/version.txt" "$BIN" --version
val version "$( cat "$WORK/version.txt" "$WORK/version.txt.err" 2>/dev/null | head -1 )"
val c17_run "${RUN:-none found}"
[ -n "${RUN:-}" ] && [ -d "$RUN" ] && val c17_run_version "$( cat "$RUN/version.txt" 2>/dev/null )"

hr "1. and 2. the C17 run, counted from its frames"
if [ -n "${RUN:-}" ] && [ -d "$RUN" ]; then
python3 - "$RUN" "$WORK/init-names.txt" <<'PY'
import glob, json, os, re, sys
run, names_out = sys.argv[1], sys.argv[2]
def val( k, v ): print( "%-46s %s" % ( k, v ) )
facts = json.load( open( os.path.join( run, "facts.json" ) ) )
oracle, keys = facts["oracle"], facts["keys"]
controls = [ "run_command", "uhw_no_such_tool_7731" ]
candidates = [ n for n in oracle if n not in controls ]
refused  = [ n for n in candidates if not oracle[n]["exists"] ]
accepted = [ n for n in candidates if oracle[n]["exists"] ]
val( "candidates_probed", len( candidates ) )
val( "controls_behaved", oracle["run_command"]["exists"] and not oracle["uhw_no_such_tool_7731"]["exists"] )
val( "refused_at_launch", "%d  %s" % ( len( refused ), " ".join( refused ) ) )
val( "accepted_at_launch", "%d  %s" % ( len( accepted ), " ".join( accepted ) ) )
by_name  = [ n for n in accepted if keys[n]["called"] ]
other    = { n: keys[n]["all_calls"] for n in accepted if not keys[n]["called"] and keys[n]["all_calls"] }
failed   = [ n for n in accepted if "ERROR" in keys[n]["status"] ]
val( "called_by_its_own_name", "%d  %s" % ( len( by_name ), " ".join( "%s(%s)" % ( n, ",".join( keys[n]["argument_keys"] ) ) for n in by_name ) ) )
val( "second_launch_failed", "%d  %s" % ( len( failed ), " ".join( failed ) ) )
for n in failed:
    path = os.path.join( run, "frames-use-%s.jsonl.stderr" % n )
    err = open( path ).read().splitlines() if os.path.exists( path ) else [ "(error file not in this checkout: raw material stays on the host that ran the capture)" ]
    val( "  error_" + n, err[0][:150] if err else "" )
def reply( n ):
    text = ""
    path = os.path.join( run, "frames-use-%s.jsonl.summary" % n )
    if not os.path.exists( path ): return None
    for line in open( path ):
        try: o = json.loads( line )
        except ValueError: continue
        for r in o.get( "results", [] ): text += r.get( "text" ) or ""
    return text
replies = { n: reply( n ) for n in accepted if n not in failed }
have_replies = all( r is not None for r in replies.values() )
val( "reply_texts_in_this_checkout", have_replies )
replies = { n: r or "" for n, r in replies.items() }
# A name the model called something else for: only write or edit calls count (a read beside it is incidental).
alias = { n: [ c for c in calls if c != "read_file" ] for n, calls in other.items() }
alias = { n: c for n, c in alias.items() if c }
val( "model_called_another_tool_instead", "%d  %s" % ( len( alias ), " ".join( "%s->%s" % ( n, ",".join( sorted( set( c ) ) ) ) for n, c in alias.items() ) ) )
unusable = [ n for n in accepted if n not in by_name and n not in failed and n not in alias ]
val( "accepted_and_never_called", "%d  %s" % ( len( unusable ), " ".join( unusable ) ) )
for n in unusable:
    if have_replies: val( "  reply_" + n, " ".join( replies[n].split() )[:230] )
names_manage_task = [ n for n in replies if "manage_task" in replies[n] ]
val( "replies_naming_manage_task", "%d  %s" % ( len( names_manage_task ), " ".join( names_manage_task ) ) )
val( "replies_listing_only_read_file_manage_task", sum( 1 for n in replies if re.search( r"read_file`? and `?manage_task", replies[n] ) ) )
# The first frame's tool list.
lists = {}
for path in sorted( glob.glob( os.path.join( run, "frames-*.jsonl" ) ) ):
    for line in open( path ):
        try: o = json.loads( line )
        except ValueError: continue
        frame = o.get( "frame", {} ) if isinstance( o, dict ) else {}
        if frame.get( "event" ) == "init" and isinstance( frame.get( "init", {} ).get( "tools" ), list ):
            lists[os.path.basename( path )] = tuple( frame["init"]["tools"] ); break
distinct = set( lists.values() )
val( "launches_with_a_first_frame", len( lists ) )
val( "distinct_first_frame_tool_lists", len( distinct ) )
names = sorted( set().union( *distinct ) ) if distinct else []
open( names_out, "w" ).write( "\n".join( names ) + "\n" )
browser = [ n for n in names if "browser" in n ]
val( "names_in_first_frame_list", len( names ) )
val( "  of_them_starting_browser_", sum( 1 for n in names if n.startswith( "browser_" ) ) )
val( "  of_them_containing_browser", len( browser ) )
val( "in_list_yet_refused_at_launch", " ".join( n for n in refused if n in names ) or "-" )
val( "not_in_list_and_refused", " ".join( n for n in refused if n not in names ) or "-" )
val( "in_list_and_accepted", " ".join( n for n in accepted if n in names ) or "-" )
val( "accepted_yet_not_in_list", " ".join( n for n in accepted + [ "run_command" ] if n not in names ) or "-" )
current = [ "run_command", "read_file", "write_file", "edit_file", "search_web", "notebook_edit", "manage_task" ]
val( "current_names_absent_from_list", " ".join( n for n in current if n not in names ) or "-" )
print( "first_frame_list: " + " ".join( names ) )
PY
else
    echo "no C17 run for $ENGINE under $HERE/out; sections 1 and 2 skipped"
    : > "$WORK/init-names.txt"
fi

hr "3. the vendor's record: the binary"
strings -n 8 "$REAL" > "$WORK/strings.txt"
val manage_task_description "$( grep -o -m1 "Manage the background tasks of this conversation[^.]*\.[^.]*\." "$WORK/strings.txt" | head -1 | cut -c1-260 )"
val manage_task_source_files "$( grep -o -E 'third_party/[a-z_/]*manage_task[a-z_]*\.go' "$WORK/strings.txt" | sort -u | tr '\n' ' ' )"
val opt_out_names_in_binary "$( grep -a -o -E 'force_disable_fundamental_components|manage_task_force_disable' "$REAL" | sort | uniq -c | awk '{ printf "%s x%s  ", $2, $1 }' )"
for n in manage_task read_file write_file edit_file view_file write_to_file replace_file_content grep_search find_by_name list_dir read_url_content notebook_edit code_search view_code_item view_file_outline skill_search browser_subagent; do
    val "occurrences_$n" "$( grep -a -o -w -- "$n" "$REAL" | wc -l )"
done

hr "3. the vendor's record: the skills shipped beside the engine"
SKILLS=$( ls -d "$HOME"/.gemini/*/builtin/skills 2>/dev/null | head -1 )
val skills_directory "${SKILLS:-none}"
if [ -n "${SKILLS:-}" ]; then
    grep -rn -E 'omitted `tools`|read-only default|tools: \[|native tool names|`Bash` to|`Read`/|`Edit`/|`WebSearch`' "$SKILLS" 2>/dev/null \
        | sed "s|$SKILLS/||" | cut -c1-230
fi

hr "3. the vendor's record: the release notes ($ENGINE changelog)"
quiet_run 30 "$WORK/changelog.txt" "$BIN" changelog
val changelog_lines "$( wc -l < "$WORK/changelog.txt" )"
awk '/^[0-9]+\.[0-9]+\.[0-9]+/ { v = $1 }
     /manage_task|fundamental components|declarative agent|custom agent.*tools|tool name conflict|canonical tool name|read_url_content|grep_search|list_dir|find_by_name|notebook_edit|view_file|write_to_file|replace_file_content/ \
     { printf "[%s line %d] %s\n", v, NR, substr( $0, 1, 330 ) }' "$WORK/changelog.txt"

hr "4. the role table's built-in tools against the record"
MIGRATE=$( grep -rl 'native tool names' "$SKILLS" 2>/dev/null | head -1 )
printf '%-18s %-22s %-22s %s\n' "name" "in first-frame list" "in vendor's mapping" "role table"
while read -r name row; do
    in_list=no;   grep -qx -- "$name" "$WORK/init-names.txt" && in_list=yes
    in_skill=no;  [ -n "${MIGRATE:-}" ] && grep -q -- "\`$name\`\|\[$name,\| $name,\| $name\]" "$MIGRATE" && in_skill=yes
    printf '%-18s %-22s %-22s %s\n' "$name" "$in_list" "$in_skill" "$row"
done <<'ROWS'
run_command granted
read_file granted
write_file granted
edit_file granted
notebook_edit granted
search_web granted
invoke_subagent granted (chief of staff; never on AGY)
manage_task never listed
ask_question never listed
send_message never listed
schedule never listed
define_subagent never listed
manage_subagents never listed
swarm never listed
run_workflow never listed
ROWS
echo
echo "zero tokens: no turn was started; the engine was run only for --version and changelog"
