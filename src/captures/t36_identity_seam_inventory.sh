#!/usr/bin/env bash
# T36 persona-identity seam inventory (2026-11-15). No model call; reads a lupin checkout and the host,
# writes nothing to either. Answers, for one checkout and one host: which routers sit behind the
# account door (require_api_key_or_jwt) and how many of their routes take a sender; which code sends
# the fleet key (the persona's tool server, the old harness's hooks, services that are not personas);
# whether the key table can find a key without checking every active key; how many active keys there
# are and what one check costs; how many server workers Lupin runs (a single-use cache needs one);
# and whether the host can keep a signing key out of a persona's reach (ptrace scope, privilege,
# the Ed25519 library on both sides).
# Rerun on both hosts; the numbers under "summary" are the ones the T36 narrative and spec quote.
# Usage: t36_identity_seam_inventory.sh <path to the lupin checkout>
set -u
LUPIN=${1:?usage: t36_identity_seam_inventory.sh <path to the lupin checkout>}
SRC="$LUPIN/src"
ROUTERS="$SRC/cosa/rest/routers"
AUTH="$SRC/cosa/rest/middleware/api_key_auth.py"
FLEET_KEY='notification-api-claude-code-dev'
hr()  { printf '\n== %s ==\n' "$1"; }
val() { printf '%-44s %s\n' "$1" "$2"; }
not_tests() { grep -vE '/tests?/|/test_[^/]*\.py:|_test\.py:|conftest\.py:|/rnd/|/history/'; }

hr "checkout"
val host "$( hostname )"
val clock "$( TZ=America/New_York date '+%Y-%m-%d %H:%M:%S %Z' )"
val lupin_head "$( git -C "$LUPIN" rev-parse --short=9 HEAD 2>/dev/null || echo 'no git' )"

hr "the account door (cosa/rest/middleware/api_key_auth.py)"
val sweep_function "$( grep -nE '^def _validate_api_key_sync' "$AUTH" | cut -d: -f1 | sed 's/^/line /' )"
val bcrypt_check_inside_a_loop "$( grep -nE 'for key_obj in active_keys|bcrypt\.checkpw' "$AUTH" | cut -d: -f1 | tr '\n' ' ' )"
val key_format_check "$( grep -noE "ck_live_\[[^']*" "$AUTH" | head -1 )"
val key_table_columns "$( awk '/__tablename__ *= *"api_keys"/{on=1} on&&/Mapped\[/{sub(/:.*/,"");gsub(/ /,"");printf "%s ",$0} on&&/^class /&&!/ApiKey/{exit}' "$SRC/cosa/rest/postgres_models.py" )"
val key_prefix_column "$( awk '/__tablename__ *= *"api_keys"/{on=1} on&&/^class /{exit} on' "$SRC/cosa/rest/postgres_models.py" | grep -qiE 'prefix|key_id' && echo present || echo 'ABSENT (every active key is checked)' )"

hr "routers behind the account door: routes, door references, lines naming a sender"
printf '%-28s %7s %7s %9s\n' router routes door sender
total_routers=0; total_routes=0; sender_routers=0
for file in "$ROUTERS"/*.py; do
    door=$( grep -c 'require_api_key_or_jwt' "$file" )
    [ "$door" -eq 0 ] && continue
    routes=$( grep -cE '^@router\.(get|post|put|patch|delete)' "$file" )
    sender=$( grep -cE 'sender_id|created_by|sender_persona' "$file" )
    printf '%-28s %7s %7s %9s\n' "$( basename "$file" .py )" "$routes" "$door" "$sender"
    total_routers=$(( total_routers + 1 )); total_routes=$(( total_routes + routes ))
    [ "$sender" -gt 0 ] && sender_routers=$(( sender_routers + 1 ))
done
val routers_with_no_door_reference "$( for file in "$ROUTERS"/*.py; do grep -q 'require_api_key_or_jwt' "$file" || basename "$file" .py; done | grep -v '^__init__$' | tr '\n' ' ' )"

hr "code that sends the fleet key (an X-API-Key header), tests left out"
sites=$( grep -rnE --include='*.py' '"X-API-Key" *:' "$SRC" 2>/dev/null | not_tests | sed "s|^$SRC/||" | sort )
tool_server=$( printf '%s\n' "$sites" | grep -c '^lupin_mcp/' )
old_hooks=$( printf '%s\n' "$sites" | grep -cE '^lupin_cli/|^cosa/utils/hook_' )
services=$( printf '%s\n' "$sites" | grep -vcE '^lupin_mcp/|^lupin_cli/|^cosa/utils/hook_' )
printf '%s\n' "$sites" | cut -c1-110
hr "code that names the fleet key file"
grep -rnF --include='*.py' "$FLEET_KEY" "$SRC" 2>/dev/null | not_tests | sed "s|^$SRC/||" | cut -d: -f1 | sort | uniq -c

hr "Lupin's server workers (a single-use cache in memory needs exactly one)"
grep -nE 'workers *=' "$SRC/lupin_app/main.py" | cut -c1-140

hr "the Ed25519 library"
val lupin_lock_file "$( grep -A1 -E '^name = "cryptography"' "$LUPIN/uv.lock" 2>/dev/null | tr '\n' ' ' || echo 'not locked' )"
val lupin_direct_dependency "$( grep -qiE '"cryptography' "$LUPIN/pyproject.toml" && echo yes || echo 'no (present only through another package)' )"
val host_python "$( python3 -c 'import sys,cryptography;from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey;k=Ed25519PrivateKey.generate();k.public_key().verify(k.sign(b"x"),b"x");print("python",sys.version.split()[0],"cryptography",cryptography.__version__,"ed25519 sign and verify ok")' 2>&1 | tail -1 )"

hr "the host: can a persona reach the kernel's memory or its files"
val account "$( id -un )"
val ptrace_scope "$( cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null || echo 'no yama' ) (0 any same-account process may attach; 1 only a parent; 2 administrators; 3 nobody)"
val passwordless_sudo "$( sudo -n true 2>/dev/null && echo yes || echo no )"
val docker_group "$( id -nG | tr ' ' '\n' | grep -qx docker && echo yes || echo no )"
val systemd "$( systemctl --version 2>/dev/null | head -1 )"

hr "Lupin containers on this host (best effort; skipped without docker)"
if command -v docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1; then
    docker ps --format '{{.Names}}' | grep -iE 'lupin.*rest|rest.*lupin' | while read -r name; do
        val "$name: ed25519" "$( docker exec "$name" python3 -c 'import cryptography;from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey;k=Ed25519PrivateKey.generate();k.public_key().verify(k.sign(b"x"),b"x");print("cryptography",cryptography.__version__,"ok")' 2>&1 | tail -1 | cut -c1-90 )"
        val "$name: one bcrypt check" "$( docker exec "$name" python3 -c 'import bcrypt,time;h=bcrypt.hashpw(b"x",bcrypt.gensalt());t=time.perf_counter();[bcrypt.checkpw(b"y",h) for _ in range(5)];print(h[:7].decode(),"%.0f ms"%((time.perf_counter()-t)*200))' 2>&1 | tail -1 | cut -c1-90 )"
    done
    docker ps --format '{{.Names}}' | grep -iE 'pgvector|postgres' | while read -r name; do
        for database in $( docker exec "$name" sh -c 'psql -U "$POSTGRES_USER" -d postgres -Atc "select datname from pg_database where not datistemplate"' 2>/dev/null ); do
            docker exec "$name" sh -c "psql -U \"\$POSTGRES_USER\" -d $database -Atc \"select 1 from information_schema.tables where table_name = 'api_keys'\"" 2>/dev/null | grep -q 1 || continue
            val "$name/$database: active | all | cost" "$( docker exec "$name" sh -c "psql -U \"\$POSTGRES_USER\" -d $database -Atc \"select count(*) filter (where is_active), count(*), string_agg(distinct substr(key_hash,1,7), chr(44)) from api_keys\"" 2>&1 | tail -1 | cut -c1-90 )"
        done
    done
else
    val docker "not available to this account"
fi

hr "summary"
val routers_behind_the_account_door "$total_routers"
val routes_in_those_routers "$total_routes"
val of_those_routers_naming_a_sender "$sender_routers"
val fleet_key_send_sites_tool_server "$tool_server"
val fleet_key_send_sites_old_harness_hooks "$old_hooks"
val fleet_key_send_sites_other_services "$services"
