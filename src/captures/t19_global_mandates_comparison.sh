#!/usr/bin/env bash
# t19_global_mandates_comparison.sh — the test VM's deployed global mandates
# (`~/.claude/CLAUDE.md`) beside the convention kit's copy (`global/CLAUDE.md` in
# planning-is-prompting), for row 93 of "Outstanding actions": refresh the host's file from the
# kit, or let it stand (row 87, ruling 6: the Phase 1 builder works under the host's copy).
#
#   t19_global_mandates_comparison.sh [kit root] [host file]
#       defaults: $PLANNING_IS_PROMPTING_ROOT or /mnt/lupin-data/planning-is-prompting; ~/.claude/CLAUDE.md
#
# Seven parts, one line per fact, `name value`:
#
#   (a) the two files      size, lines, date, digest; whether the kit copy is a git checkout
#   (b) section by section which second-level sections are the same, changed, or in one file only
#   (c) the kit's tools    its drift detector's count, and whether its sync would write (dry run)
#   (d) rules by presence  named rules, in the host's copy and in the kit's
#   (e) what each names    files, commands and tools a mandate names, counted in each copy, and
#                          whether this host and the builder's clone have them
#   (f) who reads the file Claude Code project folders and live sessions on this host
#   (g) the stash guard    what AH4L's hook answers to the builder's ruled pull line (row 94)
#
# Read-only: it writes nothing, runs the kit's two scripts without `--write` and without
# byte-code files, and calls the stash guard as a function. Zero tokens, a few seconds.
# Output is meant for src/captures/out/t19-global-mandates-comparison-<host>-<date>.txt.

set -u
kit="${1:-${PLANNING_IS_PROMPTING_ROOT:-/mnt/lupin-data/planning-is-prompting}}"
host_file="${2:-$HOME/.claude/CLAUDE.md}"
kit_file="$kit/global/CLAUDE.md"
lupin="${LUPIN_ROOT:-/mnt/lupin-data/lupin}"
builder="/mnt/lupin-data/unified-headless-wrapper-builder"
say() { printf '%-52s %s\n' "$1" "$2"; }
yes_no() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
count() { grep -cE -- "$1" "$2" 2>/dev/null || true; }

echo "# (a) the two files"
say host "$(hostname)"
say read_at "$(TZ=America/New_York date '+%Y-%m-%d %H:%M %Z')"
for pair in "host:$host_file" "kit:$kit_file"; do
    name="${pair%%:*}"; file="${pair#*:}"
    [ -r "$file" ] || { say "${name}_file" "MISSING $file"; exit 2; }
    say "${name}_file" "$file"
    say "${name}_bytes" "$(wc -c < "$file")"
    say "${name}_lines" "$(wc -l < "$file")"
    say "${name}_modified" "$(TZ=America/New_York date -r "$file" '+%Y-%m-%d %H:%M %Z')"
    say "${name}_sha256" "$(sha256sum "$file" | cut -c1-16)"
done
say files_identical "$(yes_no cmp -s "$host_file" "$kit_file")"
say lines_only_in_host "$(diff "$host_file" "$kit_file" | grep -c '^<')"
say lines_only_in_kit "$(diff "$host_file" "$kit_file" | grep -c '^>')"
say kit_is_git_checkout "$(yes_no test -e "$kit/.git")"
say kit_newest_file "$(find "$kit" -type f -printf '%TY-%Tm-%Td\n' 2>/dev/null | sort | tail -1)"
say kit_readme_snapshot_line "$(grep -m1 -i 'Captured' "$kit/global/README.md" 2>/dev/null | cut -c1-110)"

echo
echo "# (b) section by section (second-level headings; lines of body, host then kit)"
python3 -B - "$host_file" "$kit_file" <<'PY'
import re, sys
def read_sections( path ):
    sections, order, current, body, fenced = {}, [], "(before the first heading)", [], False
    for line in open( path, encoding="utf-8" ).read().split( "\n" ):
        if line.startswith( "```" ): fenced = not fenced
        if not fenced and re.match( r"^#{1,2} ", line ):
            sections[ current ] = body; order.append( current ); current, body = line.strip(), []
        else:
            body.append( line )
    sections[ current ] = body; order.append( current )
    return sections, order
def normalize( heading ): return re.sub( r"[^A-Za-z0-9 ]", "", heading ).strip().lower()
host, host_order = read_sections( sys.argv[ 1 ] ); kit, kit_order = read_sections( sys.argv[ 2 ] )
host_keys = { normalize( h ): h for h in host_order }; kit_keys = { normalize( h ): h for h in kit_order }
tally = { "same": 0, "changed": 0, "host_only": 0, "kit_only": 0 }
for key, heading in host_keys.items():
    name = re.sub( r"[^A-Za-z0-9 .&/()-]", "", heading ).strip()[ :58 ]
    if key in kit_keys:
        a, b = host[ heading ], kit[ kit_keys[ key ] ]
        state = "same" if a == b else "changed"
        print( "%-9s %4d %4d  %s" % ( state, len( a ), len( b ), name ) )
    else:
        state = "host_only"; print( "%-9s %4d    -  %s" % ( state, len( host[ heading ] ), name ) )
    tally[ state ] += 1
for key, heading in kit_keys.items():
    if key not in host_keys:
        tally[ "kit_only" ] += 1
        print( "%-9s    - %4d  %s" % ( "kit_only", len( kit[ heading ] ), re.sub( r"[^A-Za-z0-9 .&/()-]", "", heading ).strip()[ :58 ] ) )
for state in ( "same", "changed", "host_only", "kit_only" ):
    print( "%-52s %d" % ( "sections_" + state, tally[ state ] ) )
PY

echo
echo "# (c) the kit's own tools, neither asked to write"
digest_before="$(sha256sum "$host_file" | cut -c1-16)"
detector="$kit/workflow/scripts/doc_deploy_parity.py"; sync="$kit/workflow/scripts/sync_deployed_claude_md.py"
if [ -r "$detector" ] && [ -r "$sync" ]; then
    report="$(cd "$kit" && python3 -B "$detector" --pair "row93::$kit_file::$host_file" 2>&1)"; code=$?
    say detector_exit "$code (0 none drifted, 1 drifted, 2 unreadable)"
    say detector_drifted_paragraphs "$(printf '%s\n' "$report" | grep -aoE '[0-9]+ DRIFTED' | head -1 | grep -oE '[0-9]+')"
    dry="$(cd "$kit" && python3 -B "$sync" --deployed "$host_file" 2>&1)"; code=$?
    say sync_dry_run_exit "$code (0 would write or nothing to do, 2 refused, 3 no input)"
    say sync_paragraphs_it_refuses "$(printf '%s\n' "$dry" | grep -ac 'syncing would DELETE')"
else
    say kit_tools "absent"
fi
say host_file_unchanged_by_this_part "$(yes_no test "$digest_before" = "$(sha256sum "$host_file" | cut -c1-16)")"

echo
echo "# (d) rules by presence (matching lines: host, kit)"
rule() { say "rule[$1]" "host $(count "$2" "$host_file")  kit $(count "$2" "$kit_file")"; }
rule "git stash is repo-global, do not use it" 'git stash.{0,6} is repo-global'
rule "a copy does not merge, it replaces" 'copy does not merge'
rule "no test or job touches a GPU" 'NO TEST OR JOB TOUCHES A GPU'
rule "manager context monitoring, the 10-minute tick" '10-MINUTE TICK'
rule "commit once green AND reviewed" 'green AND reviewed'
rule "push to origin stays gated" 'push to origin'
rule "never git add . or -A" 'git add (\.|-A)'
rule "curl prohibited for API testing" 'CURL is (absolutely )?prohibited'
rule "test ownership mandate" 'TEST OWNERSHIP MANDATE'
rule "the three acronyms recap at the end" 'THE THREE ACRONYMS'

echo
echo "# (e) what each copy names (matching lines: host, kit), and whether it is here"
rule "history.md" 'history\.md'
rule "TODO.md" 'TODO\.md'
rule "a /plan- command" '/plan-[a-z]'
rule "the task store (task_create, task_query)" 'task_(create|query)'
rule "the voice tools (cosa-voice, converse, notify)" 'cosa-voice|converse\(|notify\('
rule ".claude-session.md manifest" '\.claude-session\.md'
rule "stash_guard.py" 'stash_guard'
say host_has_global_commands "$(yes_no test -d "$HOME/.claude/commands")"
say host_has_global_skills "$(yes_no test -d "$HOME/.claude/skills")"
say builder_clone_present "$(yes_no test -d "$builder/.git")"
say builder_clone_has_commands "$(yes_no test -d "$builder/.claude/commands")"
say builder_clone_has_history_md "$(yes_no test -e "$builder/history.md")"
say builder_clone_has_todo_md "$(yes_no test -e "$builder/TODO.md")"
say global_settings_hook_events "$(python3 -B -c "import json,os;print(len(json.load(open(os.path.expanduser('~/.claude/settings.json'))).get('hooks',{})))" 2>/dev/null)"
say global_hooks_run_from_lupin "$(count 'LUPIN_ROOT/src/lupin_cli/claude_code/hooks' "$HOME/.claude/settings.json") commands"

echo
echo "# (f) who reads the host's file"
say claude_project_folders "$(ls -1 "$HOME/.claude/projects" 2>/dev/null | wc -l)"
ls -1 "$HOME/.claude/projects" 2>/dev/null | sed 's/^/    /'
say live_claude_processes "$(pgrep -fc '/bin/claude( |$)' 2>/dev/null || true)"
say backups_of_host_file "$(ls -1 "$HOME/.claude/" 2>/dev/null | grep -c '^CLAUDE\.md\.')"

echo
echo "# (g) AH4L's stash guard, called as a function on the git lines the builder may type"
guard="$lupin/src/lupin_cli/claude_code/hooks/lib/stash_guard.py"
if [ -r "$guard" ]; then
    say stash_guard_wired_into_pre_tool_use "$(yes_no grep -q stash_deny_reason "$lupin/src/lupin_cli/claude_code/hooks/pre_tool_use.py")"
    ( cd "$(dirname "$guard")" && env -u LUPIN_ALLOW_GIT_STASH python3 -B - <<'PY'
import stash_guard
for line in ( "git pull --rebase --autostash", "git pull --rebase", "git stash", "git stash pop", "git stash list" ):
    reason = stash_guard.stash_deny_reason( "Bash", { "command": line } )
    print( "%-52s %s" % ( "guard[" + line + "]", "denied" if reason else "allowed" ) )
PY
    )
else
    say stash_guard "absent at $guard"
fi
