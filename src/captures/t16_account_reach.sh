#!/usr/bin/env bash
# T16 account reach (2026-11-16; row 39 of "Outstanding actions"). No model call; reads the host and
# writes nothing. It follows t16_account_inventory.sh, which counted how the fleet uses sudo and docker.
# This one reads what the account that runs the fleet can reach beyond its own files, so that the
# narrative for the unprivileged account (D59, the fleet, part 9) states host facts and not readings
# of a compose file on another host. Five questions:
#   (a) the account: its numeric identifier, the other login accounts, the groups that give root's reach;
#   (b) which kinds of credential sit in its home (a path, a type, an owner and a mode; never a content);
#   (c) which daemon sockets it can write (Docker, LXD, Incus, libvirt);
#   (d) each running container: the user it runs as, whether it is privileged, how many of its mounts are
#       writable, and every mount whose source is under this home or is a daemon socket;
#   (e) what a second account would meet: who owns the checkouts, the user units, rootless Docker's needs.
# Prints paths, names, modes and counts. Never a file's content, a token, a key or an environment value.
# Usage: t16_account_reach.sh [path to the lupin checkout, default ../lupin]
set -u
LUPIN=${1:-../lupin}
hr()  { printf '\n== %s ==\n' "$1"; }
val() { printf '%-44s %s\n' "$1" "$2"; }
members() { getent group "$1" 2>/dev/null | awk -F: '{ print ( $4 == "" ? "(none)" : $4 ) }'; }

hr "host"
val host "$( hostname )"
val clock "$( TZ=America/New_York date '+%Y-%m-%d %H:%M:%S %Z' )"

hr "(a) the account and its neighbours"
val account "$( id -un )"
val uid_gid "$( id -u ):$( id -g )"
val home "$HOME"
val groups "$( id -nG )"
echo "login accounts (name, uid, shell), uid 1000 and above:"
getent passwd | awk -F: '$3 >= 1000 && $3 < 65000 { printf "    %-28s %-8s %s\n", $1, $3, $7 }'
echo "members of the groups that give root's reach, where the group exists:"
for g in sudo docker lxd incus-admin libvirt kvm disk adm; do
    getent group "$g" >/dev/null 2>&1 && printf '    %-14s %s\n' "$g" "$( members "$g" )"
done
echo "processes by account, uid 1000 and above (count, account):"
ps -eo uid=,user= | awk '$1 >= 1000 && $1 < 65000 { n[$2]++ } END { for ( u in n ) printf "    %6d  %s\n", n[u], u }'

hr "(b) credential kinds in this home (path, what is there; no content is read)"
describe() {   # path label
    if [ -e "$1" ]; then
        if [ -d "$1" ]; then
            printf '    %-44s directory  %s  %s entries\n' "$2" "$( stat -c '%U:%G %a' "$1" )" "$( ls -A "$1" 2>/dev/null | wc -l )"
        else
            printf '    %-44s file       %s  %s bytes\n' "$2" "$( stat -c '%U:%G %a' "$1" )" "$( stat -c %s "$1" )"
        fi
    else
        printf '    %-44s absent\n' "$2"
    fi
}
for p in .config/gcloud .config/gcloud/application_default_credentials.json .config/gcloud/credentials.db \
         .config/gcloud/legacy_credentials .config/gh/hosts.yml .git-credentials .netrc .docker/config.json \
         .ssh .gnupg .aws .kube .npmrc .pypirc .local/share/keyrings \
         .claude/.credentials.json .gemini .lupin .lupin/config .lora_env; do
    describe "$HOME/$p" "~/$p"
done
val ssh_private_keys "$( ls "$HOME/.ssh" 2>/dev/null | grep -c '^id_[a-z0-9_]*$' )"
val ssh_authorized_keys_lines "$( [ -r "$HOME/.ssh/authorized_keys" ] && grep -vc '^[[:space:]]*\(#\|$\)' "$HOME/.ssh/authorized_keys" || echo 0 )"
val ssh_agent_socket "$( [ -n "${SSH_AUTH_SOCK:-}" ] && echo set || echo unset )"
val git_credential_helper "$( git config --global --get-all credential.helper 2>/dev/null | awk '{ print $1 }' | paste -sd, - | sed 's/^$/unset/' )"
val lupin_config_owner_section "$( [ -r "$HOME/.lupin/config" ] && { grep -q '^\[owner\]' "$HOME/.lupin/config" && echo present || echo absent; } || echo 'no file' )"

hr "(c) daemon sockets this account can write"
for s in /var/run/docker.sock /var/snap/lxd/common/lxd/unix.socket /var/lib/lxd/unix.socket \
         /var/lib/incus/unix.socket /var/run/libvirt/libvirt-sock; do
    if [ -S "$s" ]; then printf '    %-44s %s  writable=%s\n' "$s" "$( stat -c '%U:%G %a' "$s" )" "$( [ -w "$s" ] && echo yes || echo no )"
    else printf '    %-44s absent\n' "$s"; fi
done
val lxd_daemon "$( systemctl is-active snap.lxd.daemon 2>/dev/null | head -1 ) / $( systemctl is-active lxd 2>/dev/null | head -1 )"
echo "sudo rules for this account (sudo -n -l; no password is ever offered):"
sudo -n -l 2>/dev/null | sed -n '/may run/,$p' | sed 's/^/    /' || true
for f in $( sudo -n -l 2>/dev/null | grep -o 'NOPASSWD: */[^ ,]*' | awk '{ print $2 }' ); do
    [ -e "$f" ] && val "passwordless program" "$f  $( stat -c '%U:%G %a' "$f" )"
done

hr "(d) running containers: user, privilege, and what each mounts from this home"
if docker info >/dev/null 2>&1; then
    val docker_server_version "$( docker version --format '{{.Server.Version}}' 2>/dev/null )"
    val docker_runtimes "$( docker info --format '{{range $k, $v := .Runtimes}}{{$k}} {{end}}' 2>/dev/null )"
    val docker_rootless "$( docker info --format '{{range .SecurityOptions}}{{.}} {{end}}' 2>/dev/null | grep -q rootless && echo yes || echo no )"
    val docker_authorization_plugins "$( docker info --format '{{range .Plugins.Authorization}}{{.}} {{end}}' 2>/dev/null | sed 's/^$/none/' )"
    for c in $( docker ps --format '{{.Names}}' ); do
        printf '\n%s\n' "$c"
        val "    user | privileged" "$( docker inspect "$c" --format '{{if .Config.User}}{{.Config.User}}{{else}}(image default){{end}} | {{.HostConfig.Privileged}}' )"
        val "    compose project | service" "$( docker inspect "$c" --format '{{index .Config.Labels "com.docker.compose.project"}} | {{index .Config.Labels "com.docker.compose.service"}}' )"
        val "    compose working directory" "$( docker inspect "$c" --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' )"
        val "    mounts | writable" "$( docker inspect "$c" --format '{{len .Mounts}}' ) | $( docker inspect "$c" --format '{{range .Mounts}}{{if .RW}}w{{end}}{{end}}' | tr -d '\n' | wc -c )"
        docker inspect "$c" --format '{{range .Mounts}}{{.Type}} {{if .RW}}rw{{else}}ro{{end}} {{.Source}} {{.Destination}}{{"\n"}}{{end}}' \
          | awk -v home="$HOME" '$3 != "" && ( index( $3, home "/" ) == 1 || $3 ~ /\.sock$/ ) { printf "    from this home or a socket: %s  %s  ->  %s\n", $2, $3, $4 }'
        docker inspect "$c" --format '{{range .Mounts}}{{if .RW}}{{if eq .Type "bind"}}{{.Source}}{{"\n"}}{{end}}{{end}}{{end}}' \
          | while read -r src; do [ -n "$src" ] && [ -e "$src" ] && stat -c '%U(uid=%u)' "$src"; done | sort | uniq -c \
          | awk '{ printf "    writable bind sources owned by: %s (%s)\n", $2, $1 }'
    done
else
    val docker "not reachable by this account"
fi

hr "(e) what a second account would meet"
if [ -d "$LUPIN" ]; then
    val lupin_checkout_owner "$( stat -c '%U:%G %a (uid %u)' "$LUPIN" )"
    val lupin_checkout_parent_owner "$( stat -c '%U:%G %a' "$LUPIN/.." )"
    val lupin_compose_user_lines "$( grep -c '^ *user: *"' "$LUPIN/docker-compose.yml" 2>/dev/null ) ($( grep -o '^ *user: *"[^"]*"' "$LUPIN/docker-compose.yml" 2>/dev/null | awk '{ print $2 }' | sort -u | paste -sd, - ))"
else
    val lupin_checkout "not found at $LUPIN"
fi
val linger "$( loginctl show-user "$( id -un )" --property=Linger 2>/dev/null || echo unknown )"
echo "user units running under this account (names):"
systemctl --user list-units --type=service --state=running --no-legend 2>/dev/null | awk '{ print "    " $1 }'
val crontab_lines "$( crontab -l 2>/dev/null | grep -vc '^[[:space:]]*\(#\|$\)' )"
val subuid_entry "$( grep -q "^$( id -un ):" /etc/subuid 2>/dev/null && echo present || echo absent )"
val newuidmap "$( command -v newuidmap >/dev/null 2>&1 && echo present || echo absent )"
val rootless_setup_tool "$( command -v dockerd-rootless-setuptool.sh >/dev/null 2>&1 && echo present || echo absent )"
val git_safe_directory_entries "$( git config --global --get-all safe.directory 2>/dev/null | wc -l )"
