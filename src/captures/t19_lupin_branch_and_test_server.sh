#!/usr/bin/env bash
# t19_lupin_branch_and_test_server.sh: what this host holds for rows 86, 100, 17 and 101 of "Outstanding actions":
# where a writable lupin clone could push, what a deploy does to the deployed tree, and what the server on port 8000 is.
#
# Zero tokens, read-only: `git -C` (status, log, remote), `git ls-remote`, `docker ps`, `docker inspect`,
# one `SELECT count(*)`, `curl /health`, `grep`, `stat`, `df`. It pushes nothing, not even as a dry run.
# It prints no secret: of a container's environment only six named, non-secret variables; of the credential store only
# host names. It starts, stops and writes nothing but its own output file.
#
# Usage:
#   src/captures/t19_lupin_branch_and_test_server.sh            # prints, and writes src/captures/out/t19-lupin-branch-and-test-server-<host>-<date>.txt
#   src/captures/t19_lupin_branch_and_test_server.sh --stdout   # prints only
#
# Parts:
#   A  the deployed tree: branch, HEAD, tracked files changed, remote, .deployed-ref, owner
#   B  what a deploy does to it: the lines of lupin's deploy script that say so, and the patches a deploy has saved
#   C  GitHub from this host: whether the stored credential reads lupin's repository, its branches, how far GitHub's
#      copy of the working branch is behind the deployed tree, the hooks the tree has installed and their interpreter
#   D  the server on port 8000: container, when created, compose project and folder, database, health, row counts
#   E  how the overlay names its paths, and how lupin-vm.sh names the tree
#   F  disk, and the folders beside the tree

set -u
here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
repo="$( cd "$here/../.." && pwd )"
host="$( hostname -s )"
day="$( TZ=America/New_York date +%Y%m%d )"
out="$here/out/t19-lupin-branch-and-test-server-${host}-${day}.txt"
tree="/mnt/lupin-data/lupin"
url="https://github.com/deepily/lupin.git"
script="$tree/src/scripts/lupin-vm.sh"
overlay="$tree/docker-compose.vm-test-overlay.yml"

eastern() { TZ=America/New_York date -d "$1" '+%Y-%m-%d %H:%M %Z' 2>/dev/null || echo "$1"; }

report() {
    echo "t19_lupin_branch_and_test_server.sh · host ${host} · $( TZ=America/New_York date '+%Y-%m-%d %H:%M %Z' ) · UHW $( git -C "$repo" rev-parse --short HEAD )"
    echo
    echo "== A. The deployed tree ($tree)"
    echo "  branch           $( git -C "$tree" rev-parse --abbrev-ref HEAD )"
    echo "  HEAD             $( git -C "$tree" log -1 --format='%h (%cI)' )"
    echo "  tracked, changed $( git -C "$tree" status --porcelain --untracked-files=no | wc -l )"
    echo "  untracked        $( git -C "$tree" status --porcelain | grep -c '^??' )"
    git -C "$tree" remote -v | sed 's/^/  remote           /'
    echo "  local branches   $( git -C "$tree" branch --format='%(refname:short)' | wc -l ) ($( git -C "$tree" branch --format='%(refname:short)' | grep -c '^promote/' ) named promote/…)"
    ref="$( cat "$tree/.deployed-ref" 2>/dev/null )"
    echo "  .deployed-ref    ${ref:-absent}"
    [ -n "$ref" ] && echo "  deployed at      $( eastern "$( echo "$ref" | awk '{print $2}' )" )"
    echo "  owner            $( stat -c 'uid %u, gid %g (%G), mode %a' "$tree" )"
    echo "  this account     uid $( id -u ), groups $( id -G | tr ' ' ',' )"
    echo
    echo "== B. What a deploy does to that tree (lupin: src/scripts/lupin-vm.sh, $( wc -l < "$script" ) lines)"
    grep -nE '^VM_ROOT=|^VM_DISCARD_DIR=' "$script" | cut -c1-200 | sed 's/^/  /'
    echo "  lines that reset the tree:"
    grep -nE 'reset --hard FETCH_HEAD' "$script" | cut -c1-12 | sed 's/^/    line /; s/:.*//'
    echo "  lines of the dirty-tree guard (comment):"
    grep -nE 'DIRTY-TREE GUARD|WITHOUT --discard-vm-changes|The two INI config files are exempt' "$script" | cut -c1-230 | sed 's/^/    /'
    echo "  patches a deploy has saved under /mnt/lupin-data/deploy-discards:"
    if [ -d /mnt/lupin-data/deploy-discards ]; then
        for f in /mnt/lupin-data/deploy-discards/*.diff; do
            [ -e "$f" ] || { echo "    none"; break; }
            echo "    $( basename "$f" ) · $( stat -c %s "$f" ) bytes · files: $( grep -c '^diff --git' "$f" )"
            grep '^diff --git' "$f" | sed 's|^diff --git a/\(.*\) b/.*|      \1|'
        done
    else
        echo "    the folder does not exist"
    fi
    echo
    echo "== C. GitHub from this host ($url)"
    echo "  credential helper  $( git config --get credential.helper || echo none )"
    echo "  stored hosts       $( cut -d@ -f2 ~/.git-credentials 2>/dev/null | sort -u | tr '\n' ' ' )"
    heads="$( GIT_TERMINAL_PROMPT=0 timeout 30 git ls-remote --heads "$url" 2>&1 )"; rc=$?
    if [ $rc -ne 0 ]; then
        echo "  read               FAILED (exit $rc): $( echo "$heads" | head -2 | tr '\n' ' ' )"
    else
        echo "  read               ok, $( echo "$heads" | wc -l ) branches ($( echo "$heads" | grep -c 'refs/heads/promote/' ) named promote/…)"
        echo "$heads" | awk '{print $2}' | grep -vE 'refs/heads/promote/' | sed 's|refs/heads/|    |'
        branch="$( git -C "$tree" branch --format='%(refname:short)' | grep '^wip-' | sort | tail -1 )"
        there="$( echo "$heads" | awk -v b="refs/heads/$branch" '$2==b {print substr($1,1,10)}' )"
        echo "  newest wip branch  $branch"
        echo "    on GitHub        ${there:-absent}"
        echo "    in the tree      $( git -C "$tree" rev-parse --short=10 "$branch" 2>/dev/null )"
    fi
    if [ -n "${there:-}" ] && git -C "$tree" cat-file -e "$there" 2>/dev/null; then
        echo "    GitHub is behind by $( git -C "$tree" rev-list --count "$there..$branch" ) commits (its head is dated $( git -C "$tree" log -1 --format=%cI "$there" ))"
    fi
    # No push is tried, not even a dry run: lupin's pre-push hook runs on a dry run too, and it writes into the tree
    # (a throwaway worktree under .claude/worktrees, compiled files). Tried once by hand on 2026-11-23; see the narrative.
    echo "  write              not tried (a push, even a dry run, runs the tree's pre-push hook)"
    echo "  hooks installed in the deployed tree:"
    for h in "$tree"/.git/hooks/*; do
        case "$h" in *.sample) continue ;; esac
        [ -e "$h" ] && echo "    $( basename "$h" ) -> $( readlink "$h" 2>/dev/null || echo 'a file' )"
    done
    echo "  the hook's interpreter  $tree/.venv/bin/python3: $( "$tree/.venv/bin/python3" --version 2>&1 )"
    echo "  other interpreters      python3: $( python3 --version 2>&1 ); $( for v in ~/.venvs/*/bin/python3; do [ -x "$v" ] && printf '%s: %s; ' "$( basename "$( dirname "$( dirname "$v" )" )" )" "$( "$v" --version 2>&1 )"; done )"
    echo
    echo "== D. The server on port 8000"
    id="$( docker ps -q --filter 'publish=8000' 2>/dev/null | head -1 )"
    if [ -z "$id" ]; then
        echo "  no container publishes port 8000"
    else
        docker inspect "$id" --format '  container        {{.Name}}
  image tag        {{.Config.Image}}
  restart policy   {{.HostConfig.RestartPolicy.Name}}
  compose project  {{index .Config.Labels "com.docker.compose.project"}}
  compose folder   {{index .Config.Labels "com.docker.compose.project.working_dir"}}
  health           {{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}'
        echo "  created          $( eastern "$( docker inspect "$id" --format '{{.Created}}' )" )"
        docker inspect "$id" --format '{{range .Config.Env}}{{println .}}{{end}}' \
            | grep -E '^(DB_HOST|DB_NAME|LUPIN_ENV|LUPIN_ROOT|LUPIN_CLOUD_BACKED|LUPIN_MODEL_SERVER_URL)=' | sort | sed 's/^/  env              /'
        docker inspect "$id" --format '{{range .Mounts}}{{if eq .Type "bind"}}{{println .Source}}{{end}}{{end}}' \
            | awk -v t="$tree" 'NF { n++; if (index($0, t)==1) m++ } END { printf "  bind mounts      %d, of which %d under %s\n", n, m, t }'
    fi
    for port in 8000 7999; do
        echo "  /health on $port   $( curl -fsS --max-time 5 "http://localhost:${port}/health" 2>&1 | cut -c1-120 )"
    done
    db="$( docker ps --format '{{.Names}}' | grep -x 'lupin-pgvector-test' )"
    if [ -n "$db" ]; then
        echo "  database         $db, created $( eastern "$( docker inspect "$db" --format '{{.Created}}' )" ), publishes $( docker inspect "$db" --format '{{len .NetworkSettings.Ports}}' ) port(s) inside the network, none on the host"
        docker exec "$db" psql -U lupin_dev -d lupin_db_test -Atc "select 'tables in public: ' || count(*) from information_schema.tables where table_schema='public' union all select 'rows in users: ' || count(*) from users" 2>&1 | sed 's/^/    /'
    else
        echo "  database         no container lupin-pgvector-test"
    fi
    echo
    echo "== E. How the paths are named"
    echo "  overlay ($( basename "$overlay" ), $( wc -l < "$overlay" ) lines):"
    echo "    mounts written relative to the compose folder (./…)   $( grep -cE '^\s+- \./' "$overlay" )"
    echo "    mounts written with a variable (\${…})                 $( grep -cE '^\s+- \$\{' "$overlay" )"
    echo "    mounts .git of the tree                                $( grep -cE '^\s+- \./\.git:' "$overlay" )"
    echo "  lupin-vm.sh:"
    grep -nE 'cd \$VM_ROOT && sudo docker compose -f \$COMPOSE_FILE -f \$TEST_COMPOSE_FILE' "$script" | cut -c1-40 | sed 's/^/    the test server is driven from $VM_ROOT at line /; s/:.*//'
    echo "    mentions of \$VM_ROOT                                   $( grep -c 'VM_ROOT' "$script" )"
    echo "    it is run from                                         $( grep -c 'gcloud compute ssh' "$script" ) \`gcloud compute ssh\` call sites (the development server drives the VM)"
    echo
    echo "== F. Disk, and the folders beside the tree"
    df -h /mnt/lupin-data | sed 's/^/  /'
    echo "  the tree         $( du -sh "$tree" 2>/dev/null | cut -f1 ) (its .git: $( du -sh "$tree/.git" 2>/dev/null | cut -f1 ))"
    ls -d /mnt/lupin-data/lupin* /mnt/lupin-data/unified-headless-wrapper* 2>/dev/null | sed 's/^/  present: /'
}

if [ "${1:-}" = "--stdout" ]; then
    report
else
    mkdir -p "$here/out"
    report | tee "$out"
    echo
    echo "written: $out"
fi
