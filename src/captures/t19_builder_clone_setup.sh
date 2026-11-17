#!/usr/bin/env bash
# t19_builder_clone_setup.sh — make, or check, the Phase 1 builder's clone (row 87 of
# "Outstanding actions"; D45, Phase 1 code location and write locations, as amended 2026-11-17).
#
#   t19_builder_clone_setup.sh <path>            make the clone at <path>, then check it
#   t19_builder_clone_setup.sh --check <path>    check an existing clone; exit 1 on any failure
#   t19_builder_clone_setup.sh --self-test       both, on a bare copy in a temporary folder
#
# Environment (all optional): BUILDER_REMOTE, the URL cloned (default: the `origin` of the
# checkout this script is in); BUILDER_BRANCH (default: that checkout's branch).
#
# What "made" means, as ruled:
#   - a clone of the one branch, in a folder whose name is not the planning checkout's
#     (AH4L names a session's project after the folder)
#   - sparse checkout that leaves planning's two root loaders, CLAUDE.md and AGENTS.md, out of
#     the tree; every other tracked file is present
#   - an untracked, git-ignored CLAUDE.local.md at the root holding one line, the import of
#     the builder's loader, src/rnd/v0.0.1/03-builder-loader.md
#
# Zero tokens. Making refuses a path that already exists and deletes nothing. An Antigravity
# session opened in the clone finds no AGENTS.md and so no loader: the builder is a Claude Code
# session, and nothing is built for the other case.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
source_checkout="$(cd "$here/../.." && pwd)"
loader="src/rnd/v0.0.1/03-builder-loader.md"
import_line="@$loader"
patterns=$'/*\n!/CLAUDE.md\n!/AGENTS.md'

make_clone() {   # $1 = path, $2 = remote, $3 = branch
  [ -e "$1" ] && { echo "refused: $1 exists" >&2; return 2; }
  git clone --quiet --branch "$3" "$2" "$1" || return 2
  git -C "$1" config core.sparseCheckout true
  git -C "$1" config core.sparseCheckoutCone false
  mkdir -p "$1/.git/info"; printf '%s\n' "$patterns" > "$1/.git/info/sparse-checkout"
  git -C "$1" read-tree -mu HEAD || return 2
  printf '%s\n' "$import_line" > "$1/CLAUDE.local.md"
}

check_clone() {  # $1 = path, $2 = branch, $3 = planning checkout's folder name; prints one line per check
  local failed=0 result
  line() { printf '%-44s %s\n' "$1" "$2"; [ "$2" = ok ] || failed=1; }
  verdict() { if "$@" >/dev/null 2>&1; then echo ok; else echo FAILS; fi; }
  line is_a_git_checkout "$(verdict git -C "$1" rev-parse --git-dir)"
  [ $failed = 0 ] || return 1
  line "on_branch[$2]" "$(verdict test "$(git -C "$1" rev-parse --abbrev-ref HEAD)" = "$2")"
  line folder_name_differs_from_planning "$(verdict test "$(basename "$1")" != "$3")"
  line sparse_checkout_on "$(verdict test "$(git -C "$1" config core.sparseCheckout)" = true)"
  line sparse_patterns_as_ruled "$(verdict test "$(cat "$1/.git/info/sparse-checkout" 2>/dev/null)" = "$patterns")"
  line planning_claude_loader_absent "$(verdict test ! -e "$1/CLAUDE.md")"
  line planning_agents_loader_absent "$(verdict test ! -e "$1/AGENTS.md")"
  line no_other_root_loader "$(verdict test -z "$(ls -A "$1" | grep -E '^(GEMINI\.md|\.agents)$'; ls "$1/.claude" 2>/dev/null | grep -E '^(CLAUDE\.md|rules)$')")"
  result="$(git -C "$1" ls-files | while read -r f; do case "$f" in CLAUDE.md|AGENTS.md) ;; *) [ -e "$1/$f" ] || echo "$f";; esac; done | wc -l)"
  line every_other_tracked_file_present "$( [ "$result" = 0 ] && echo ok || echo "FAILS ($result missing)")"
  line builder_loader_import_exact "$(verdict test "$(cat "$1/CLAUDE.local.md" 2>/dev/null)" = "$import_line")"
  line builder_loader_import_ignored_by_git "$(verdict git -C "$1" check-ignore -q CLAUDE.local.md)"
  line builder_loader_text_present "$(verdict test -s "$1/$loader")"
  line root_loaders_unmodified_in_index "$(verdict test -z "$(git -C "$1" status --porcelain -- CLAUDE.md AGENTS.md)")"
  line commit_identity_is_noreply "$(verdict sh -c "git -C '$1' config user.email | grep -q 'users.noreply.github.com\$'")"
  return $failed
}

self_test() {
  local tmp failures=0; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  expect() { if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1 (expected $2, got $3)"; failures=$((failures+1)); fi; }
  export GIT_AUTHOR_NAME=trial GIT_AUTHOR_EMAIL=trial@users.noreply.github.com GIT_COMMITTER_NAME=trial GIT_COMMITTER_EMAIL=trial@users.noreply.github.com
  export GIT_CONFIG_GLOBAL="$tmp/gitconfig"; git config --global user.email trial@users.noreply.github.com; git config --global user.name trial
  local branch; branch="$(git -C "$source_checkout" rev-parse --abbrev-ref HEAD)"
  git clone --quiet --bare "$source_checkout" "$tmp/origin.git"
  git clone --quiet --branch "$branch" "$tmp/origin.git" "$tmp/unified-headless-wrapper"
  if [ ! -s "$tmp/unified-headless-wrapper/$loader" ]; then      # the loader not yet committed: a stand-in
    mkdir -p "$(dirname "$tmp/unified-headless-wrapper/$loader")"; echo "# stand-in" > "$tmp/unified-headless-wrapper/$loader"
    git -C "$tmp/unified-headless-wrapper" add "$loader"; git -C "$tmp/unified-headless-wrapper" commit --quiet -m "stand-in loader"; git -C "$tmp/unified-headless-wrapper" push --quiet
  fi
  local b="$tmp/unified-headless-wrapper-builder"
  make_clone "$b" "$tmp/origin.git" "$branch"; expect "make succeeds" 0 $?
  check_clone "$b" "$branch" unified-headless-wrapper >/dev/null; expect "a made clone passes the check" 0 $?
  expect "tree is clean" 0 "$(git -C "$b" status --porcelain | wc -l)"
  make_clone "$b" "$tmp/origin.git" "$branch" 2>/dev/null; expect "making over an existing path is refused" 2 $?
  echo "amended" >> "$tmp/unified-headless-wrapper/CLAUDE.md"; git -C "$tmp/unified-headless-wrapper" commit --quiet -am "planning amends a loader"; git -C "$tmp/unified-headless-wrapper" push --quiet
  git -C "$b" pull --quiet --rebase; expect "pull after planning amends a loader" 0 $?
  check_clone "$b" "$branch" unified-headless-wrapper >/dev/null; expect "still passes after that pull" 0 $?
  check_clone "$tmp/unified-headless-wrapper" "$branch" unified-headless-wrapper >/dev/null; expect "the planning clone fails the check" 1 $?
  echo "extra" >> "$b/CLAUDE.local.md"; check_clone "$b" "$branch" unified-headless-wrapper >/dev/null; expect "an edited import fails" 1 $?
  printf '%s\n' "$import_line" > "$b/CLAUDE.local.md"
  rm "$b/CLAUDE.local.md"; check_clone "$b" "$branch" unified-headless-wrapper >/dev/null; expect "a missing import fails" 1 $?
  printf '%s\n' "$import_line" > "$b/CLAUDE.local.md"
  git -C "$b" sparse-checkout disable >/dev/null 2>&1; check_clone "$b" "$branch" unified-headless-wrapper >/dev/null; expect "sparse checkout switched off fails" 1 $?
  git clone --quiet --branch "$branch" "$tmp/origin.git" "$tmp/other/unified-headless-wrapper" && printf '%s\n' "$import_line" > "$tmp/other/unified-headless-wrapper/CLAUDE.local.md"
  check_clone "$tmp/other/unified-headless-wrapper" "$branch" unified-headless-wrapper >/dev/null; expect "a clone made by hand fails" 1 $?
  check_clone "$tmp/absent" "$branch" unified-headless-wrapper >/dev/null; expect "a path that is no checkout fails" 1 $?
  unset GIT_CONFIG_GLOBAL
  echo "self-test: $failures failed"; [ "$failures" = 0 ]
}

branch="${BUILDER_BRANCH:-$(git -C "$source_checkout" rev-parse --abbrev-ref HEAD)}"
case "${1:-}" in
  --self-test) self_test ;;
  --check)     path="${2:?usage: t19_builder_clone_setup.sh --check <path>}"
               check_clone "$(cd "$path" 2>/dev/null && pwd || echo "$path")" "$branch" "$(basename "$source_checkout")" ;;
  ""|-*)       echo "usage: t19_builder_clone_setup.sh <path> | --check <path> | --self-test" >&2; exit 2 ;;
  *)           remote="${BUILDER_REMOTE:-$(git -C "$source_checkout" remote get-url origin)}"
               make_clone "$1" "$remote" "$branch" || exit 2
               check_clone "$(cd "$1" && pwd)" "$branch" "$(basename "$source_checkout")" ;;
esac
