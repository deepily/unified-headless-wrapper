#!/usr/bin/env bash
# t19_builder_clone_check.sh — what the test VM holds for the Phase 1 builder's clone and its
# loader, and how three ways of keeping planning's root loaders out of that clone behave under
# git (row 87 of "Outstanding actions"; D45, Phase 1 code location and write locations, as
# amended 2026-11-17 by row 85, rulings 5 and 6).
#
#   t19_builder_clone_check.sh [UHW checkout]        defaults to the checkout this script is in
#
# Three parts, one line per fact, `name value`:
#
#   (a) the host      git and engine versions; whether the Claude Code binary carries the names
#                     `claudeMdExcludes`, `CLAUDE.local.md`, `--append-system-prompt-file`; the
#                     root loaders and what git tracks or ignores beside them; the host's global
#                     mandates file against the kit's; AH4L's hooks; how many commit subjects
#                     open with the bracketed project prefix; the commit identity and
#                     where it is set; whether the remote answers and a push would be accepted;
#                     the checkout's size and the free space beside it
#   (b) the trials    in a temporary folder, on a bare copy of the checkout, never on the checkout
#                     or its remote: a second clone with (1) the two root loaders left out by
#                     sparse checkout, (2) the two overwritten and marked skip-worktree, (3) left
#                     as they are; in each, whether an ignored `CLAUDE.local.md` and
#                     `.claude/settings.local.json` leave the tree clean, and whether a pull
#                     succeeds after planning changes a root loader and a file under `src/rnd/`
#   (c) two writers   the builder pulls, commits under `src/uhw_kernel/` and pushes while the
#                     planning clone holds an uncommitted edit under `src/rnd/`; then planning
#                     pulls, plainly and with `--autostash`
#
# Read-only on the checkout and its remote (one `ls-remote`, one `push --dry-run`), zero tokens,
# a few seconds. Output is meant for src/captures/out/t19-builder-clone-check-<host>-<date>.txt.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
checkout="$(cd "${1:-$here/../..}" && pwd)" || exit 2
say() { printf '%-52s %s\n' "$1" "$2"; }
yes_no() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
git_q() { git -c advice.detachedHead=false "$@" >/dev/null 2>&1; }

echo "# (a) the host"
say host "$(hostname)"
say read_at "$(TZ=America/New_York date '+%Y-%m-%d %H:%M %Z')"
say checkout "$checkout"
say checkout_head "$(git -C "$checkout" rev-parse --short HEAD) on $(git -C "$checkout" rev-parse --abbrev-ref HEAD)"
say git_version "$(git --version | awk '{print $3}')"
claude_bin="$(command -v claude || true)"; agy_bin="$(command -v agy || true)"
say claude_code_version "$( [ -n "$claude_bin" ] && claude --version 2>/dev/null | awk '{print $1}' || echo absent)"
say agy_version "$( [ -n "$agy_bin" ] && agy --version 2>/dev/null | head -1 || echo absent)"
if [ -n "$claude_bin" ]; then
  real="$(readlink -f "$claude_bin")"
  for name in claudeMdExcludes CLAUDE.local.md append-system-prompt-file; do
    say "claude_binary_mentions[$name]" "$(grep -a -c -- "$name" "$real")"
  done
fi
for f in CLAUDE.md AGENTS.md; do
  say "root_loader[$f]" "$(wc -c < "$checkout/$f") bytes, tracked $(yes_no git -C "$checkout" ls-files --error-unmatch "$f")"
done
say tracked_loader_files_anywhere "$(git -C "$checkout" ls-files | grep -c -E '(^|/)(CLAUDE|AGENTS|GEMINI)(\.local)?\.md$')"
for f in CLAUDE.local.md .claude/settings.local.json .claude/CLAUDE.md .claude/rules/builder.md .agents/rules/builder.md; do
  say "git_ignores[$f]" "$(yes_no git -C "$checkout" check-ignore -q "$f")"
done
say checkout_has_dot_claude "$(yes_no test -d "$checkout/.claude")"
say kernel_package_exists "$(yes_no test -d "$checkout/src/uhw_kernel")"
say tests_folder_exists "$(yes_no test -d "$checkout/tests")"
global="$HOME/.claude/CLAUDE.md"
say host_global_mandates "$( [ -f "$global" ] && echo "$(wc -c < "$global") bytes, modified $(TZ=America/New_York date -r "$global" +%Y-%m-%d)" || echo absent)"
kit="$(dirname "$checkout")/planning-is-prompting/global/CLAUDE.md"
if [ -f "$kit" ] && [ -f "$global" ]; then
  say kit_global_mandates "$(wc -c < "$kit") bytes, modified $(TZ=America/New_York date -r "$kit" +%Y-%m-%d)"
  say host_global_equals_kit "$(yes_no cmp -s "$global" "$kit")"
fi
say host_user_commands_folder "$(yes_no test -d "$HOME/.claude/commands")"
say host_user_skills_folder "$(yes_no test -d "$HOME/.claude/skills")"
settings="$HOME/.claude/settings.json"
if [ -f "$settings" ]; then
  say ah4l_hook_commands "$(python3 - "$settings" <<'PY'
import json, sys
hooks = json.load( open( sys.argv[ 1 ] ) ).get( "hooks", {} )
commands = [ h.get( "command", "" ) for entries in hooks.values() for e in entries for h in e.get( "hooks", [] ) ]
print( f"{len( commands )} over {len( hooks )} events, {sum( 'lupin_cli/claude_code/hooks' in c for c in commands )} from lupin's hooks tree" )
PY
)"
fi
say commit_identity "$(git -C "$checkout" config user.name) <$(git -C "$checkout" config user.email)>"
say commits_with_bracket_prefix "$(git -C "$checkout" log --format=%s | grep -c '^\[UHW\]') of $(git -C "$checkout" rev-list --count HEAD)"
say commit_identity_set_in "$(git -C "$checkout" config --show-scope user.email | awk '{print $1}')"
say credential_helper "$(git -C "$checkout" config --show-scope --get-all credential.helper | tr '\t\n' '  ')"
say remote "$(git -C "$checkout" remote get-url origin)"
say remote_answers "$(GIT_TERMINAL_PROMPT=0 timeout 10 git -C "$checkout" ls-remote origin HEAD >/dev/null 2>&1 && echo yes || echo no)"
say push_dry_run "$(GIT_TERMINAL_PROMPT=0 timeout 10 git -C "$checkout" push --dry-run 2>&1 | tail -1)"
say checkout_size "$(du -sh "$checkout" | cut -f1), .git $(du -sh "$checkout/.git" | cut -f1)"
say free_beside_checkout "$(df -h --output=avail "$(dirname "$checkout")" | tail -1 | tr -d ' ')"
say worktrees "$(git -C "$checkout" worktree list | wc -l)"

echo
echo "# (b) the trials, in a temporary folder"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=trial GIT_AUTHOR_EMAIL=trial@invalid GIT_COMMITTER_NAME=trial GIT_COMMITTER_EMAIL=trial@invalid
branch="$(git -C "$checkout" rev-parse --abbrev-ref HEAD)"
git_q clone --bare "$checkout" "$tmp/origin.git"

planning_changes() {   # $1 = label: planning commits a root loader change and a document change, and pushes
  git_q -C "$tmp/planning" pull --rebase
  echo "changed for $1" >> "$tmp/planning/CLAUDE.md"; echo "changed for $1" >> "$tmp/planning/AGENTS.md"
  mkdir -p "$tmp/planning/src/rnd"; echo "$1" >> "$tmp/planning/src/rnd/trial.md"
  git_q -C "$tmp/planning" add -A; git_q -C "$tmp/planning" commit -m "planning: $1"; git_q -C "$tmp/planning" push
}
local_files() {        # $1 = clone: the builder's untracked loader and its engine setting
  mkdir -p "$1/.claude"
  echo '@src/uhw_kernel/BUILDER.md' > "$1/CLAUDE.local.md"
  echo '{ "claudeMdExcludes": [ "**/CLAUDE.md" ] }' > "$1/.claude/settings.local.json"
}
report() {             # $1 = trial name, $2 = clone
  say "$1.status_lines_after_local_files" "$(git -C "$2" status --porcelain | wc -l)"
  planning_changes "$1"
  say "$1.pull_after_planning_changes_a_root_loader" "$(git -C "$2" pull --rebase >/dev/null 2>&1 && echo succeeds || echo FAILS)"
  say "$1.has_planning_document_change" "$(yes_no grep -q "$1" "$2/src/rnd/trial.md")"
  say "$1.status_lines_after_pull" "$(git -C "$2" status --porcelain | wc -l)"
}
git_q clone -b "$branch" "$tmp/origin.git" "$tmp/planning"

# (1) sparse checkout: the two root loaders are not in the builder's tree at all
git_q clone -b "$branch" "$tmp/origin.git" "$tmp/sparse"
git -C "$tmp/sparse" sparse-checkout init >/dev/null 2>&1
printf '/*\n!/CLAUDE.md\n!/AGENTS.md\n' > "$tmp/sparse/.git/info/sparse-checkout"
git_q -C "$tmp/sparse" read-tree -mu HEAD
local_files "$tmp/sparse"
say sparse.root_loaders_present_in_tree "$(ls "$tmp/sparse" | grep -c -E '^(CLAUDE|AGENTS)\.md$')"
say sparse.other_tracked_files_missing "$(( $(git -C "$tmp/sparse" ls-files | wc -l) - 2 - $(git -C "$tmp/sparse" ls-files | while read -r f; do [ -e "$tmp/sparse/$f" ] && echo x; done | wc -l) ))"
report sparse "$tmp/sparse"
say sparse.root_loaders_present_after_pull "$(ls "$tmp/sparse" | grep -c -E '^(CLAUDE|AGENTS)\.md$')"

# (2) skip-worktree: the two root files are overwritten in place and git is told not to look
git_q clone -b "$branch" "$tmp/origin.git" "$tmp/skip"
for f in CLAUDE.md AGENTS.md; do echo "builder's own loader" > "$tmp/skip/$f"; git_q -C "$tmp/skip" update-index --skip-worktree "$f"; done
local_files "$tmp/skip"
report skip_worktree "$tmp/skip"
say skip_worktree.loader_still_the_builders "$(yes_no grep -q "builder's own loader" "$tmp/skip/CLAUDE.md")"

# (3) nothing done in git: the root loaders stay, and only the engine setting hides them
git_q clone -b "$branch" "$tmp/origin.git" "$tmp/plain"
local_files "$tmp/plain"
say plain.root_loaders_present_in_tree "$(ls "$tmp/plain" | grep -c -E '^(CLAUDE|AGENTS)\.md$')"
report plain "$tmp/plain"

echo
echo "# (c) two writers on one branch, disjoint paths (builder = the sparse clone)"
echo "uncommitted" >> "$tmp/planning/src/rnd/trial.md"
say builder_pull_before_it_starts "$(git -C "$tmp/sparse" pull --rebase >/dev/null 2>&1 && echo succeeds || echo FAILS)"
mkdir -p "$tmp/sparse/src/uhw_kernel"; echo "x = 1" > "$tmp/sparse/src/uhw_kernel/trial.py"
git_q -C "$tmp/sparse" add src/uhw_kernel/trial.py; git_q -C "$tmp/sparse" commit -m "builder: trial"
say builder_commit_touches_root_loaders "$(git -C "$tmp/sparse" show --stat --format= HEAD | grep -c -E '^ (CLAUDE|AGENTS)\.md')"
say builder_push "$(git -C "$tmp/sparse" push >/dev/null 2>&1 && echo succeeds || echo FAILS)"
say planning_pull_with_uncommitted_edit "$(git -C "$tmp/planning" pull --rebase >/dev/null 2>&1 && echo succeeds || echo FAILS)"
say planning_pull_with_autostash "$(git -C "$tmp/planning" pull --rebase --autostash >/dev/null 2>&1 && echo succeeds || echo FAILS)"
say planning_has_builder_file "$(yes_no test -f "$tmp/planning/src/uhw_kernel/trial.py")"
say planning_root_loaders_intact "$(ls "$tmp/planning" | grep -c -E '^(CLAUDE|AGENTS)\.md$')"
say planning_edit_survives "$(yes_no grep -q uncommitted "$tmp/planning/src/rnd/trial.md")"
