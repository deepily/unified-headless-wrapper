#!/usr/bin/env bash
# t19_lupin_trees_test_vm.sh: which lupin tree serves which port on this host (rows 96 and 97).
#
# Zero tokens, read-only: `docker ps`, `docker inspect`, `git -C` (status, log, remote), `df`, `du`, `grep`.
# It prints no environment value and no secret; it starts, stops and writes nothing but its own output file.
#
# Usage:
#   src/captures/t19_lupin_trees_test_vm.sh            # prints, and writes src/captures/out/t19-lupin-trees-<host>-<date>.txt
#   src/captures/t19_lupin_trees_test_vm.sh --stdout   # prints only
#
# Parts:
#   A  for each of ports 7999 and 8000: the container that publishes it, its image, when it was created,
#      the compose folder and files it was made from, its command, and the host folder mounted as the code
#   B  for each compose folder named in A: branch, HEAD, changed and untracked counts, remotes, .deployed-ref, size
#   C  the disk under the data mount
#   D  the count of lower-case "the move" lines the row 96 narrative states (problem 3)

set -u
here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
repo="$( cd "$here/../.." && pwd )"
host="$( hostname -s )"
day="$( TZ=America/New_York date +%Y%m%d )"
out="$here/out/t19-lupin-trees-${host}-${day}.txt"

report() {
    echo "t19_lupin_trees_test_vm.sh · host ${host} · $( TZ=America/New_York date '+%Y-%m-%d %H:%M %Z' ) · UHW $( git -C "$repo" rev-parse --short HEAD )"
    echo
    echo "== A. The container behind each port"
    folders=""
    for port in 7999 8000; do
        ids="$( docker ps -q --filter "publish=${port}" 2>/dev/null )"
        if [ -z "$ids" ]; then echo "port ${port}: no container publishes it"; echo; continue; fi
        for id in $ids; do
            echo "port ${port}:"
            docker inspect "$id" --format '  container        {{.Name}}
  image tag        {{.Config.Image}}
  image id         {{.Image}}
  created          {{.Created}}
  compose folder   {{index .Config.Labels "com.docker.compose.project.working_dir"}}
  compose files    {{index .Config.Labels "com.docker.compose.project.config_files"}}
  compose service  {{index .Config.Labels "com.docker.compose.service"}}
  command          {{json .Config.Cmd}}
{{range .Mounts}}{{if or (eq .Destination "/var/lupin") (eq .Destination "/var/lupin/src")}}  code mount       {{.Source}} -> {{.Destination}} (writable: {{.RW}})
{{end}}{{end}}'
            folders="$folders $( docker inspect "$id" --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' )"
        done
    done
    echo "other listeners on 8001 to 8009:"
    ss -ltn 2>/dev/null | grep -oE ':800[1-9]\b' | sort -u | sed 's/^/  port /' || true
    echo
    echo "== B. Each compose folder as a git tree"
    for folder in $( printf '%s\n' $folders | sort -u ); do
        echo "${folder}:"
        if ! git -C "$folder" rev-parse --git-dir >/dev/null 2>&1; then echo "  not a git tree"; continue; fi
        echo "  branch           $( git -C "$folder" rev-parse --abbrev-ref HEAD )"
        echo "  HEAD             $( git -C "$folder" rev-parse --short=10 HEAD ) ($( git -C "$folder" log -1 --format=%cI ))"
        echo "  tracked, changed $( git -C "$folder" status --porcelain | grep -vc '^??' )"
        git -C "$folder" status --porcelain | grep -v '^??' | sed 's/^/                   /'
        echo "  untracked        $( git -C "$folder" status --porcelain | grep -c '^??' )"
        echo "  work trees       $( git -C "$folder" worktree list | wc -l )"
        git -C "$folder" remote -v | sed -E 's#//[^@/]*@#//***@#; s/^/  remote           /'
        [ -f "$folder/.deployed-ref" ] && echo "  .deployed-ref    $( head -1 "$folder/.deployed-ref" )"
        echo "  size             $( du -sh "$folder" 2>/dev/null | cut -f1 )"
    done
    echo
    echo "== C. Disk"
    df -h /mnt/lupin-data 2>/dev/null | sed 's/^/  /'
    ls -d /mnt/lupin-data/lupin* /mnt/lupin-data/unified-headless-wrapper* 2>/dev/null | sed 's/^/  present: /'
    echo
    echo "== D. Lower-case \"the move\" (narrative, problem 3)"
    pattern='(before|after|at|from|until) the move\b'
    files="src/rnd/v0.0.1/01-framework.md src/rnd/v0.0.1/00-status.md src/rnd/v0.0.1/specs/*.md"
    echo "  pattern          ${pattern} (case-sensitive; the framework, the status page, the specs)"
    echo "  lines            $( cd "$repo" && grep -E "$pattern" $files | wc -l )"
    echo "  files            $( cd "$repo" && grep -lE "$pattern" $files | wc -l )"
    ( cd "$repo" && grep -cE "$pattern" $files | grep -v ':0$' | sed 's#.*v0.0.1/#    #' )
}

if [ "${1:-}" = "--stdout" ]; then report; else mkdir -p "$here/out"; report | tee "$out"; echo; echo "written: $out"; fi
