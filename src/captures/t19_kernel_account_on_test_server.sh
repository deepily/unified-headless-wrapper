#!/usr/bin/env bash
# Row 129 (2026-11-23): which account can the kernel be on the destructive-test server (port 8000)?
# Zero tokens. Reads: `docker exec … psql` (select only) on the test server's database, `~/.lupin/config`
# (section names and service emails, never a password), the key file's mode, and one GET of
# `/api/tasks/approval-settings` on each port with the host's own key (the read the kernel makes at start, D50,
# credential exposure). Prints no key, no hash, no password; a login that is not a `deepily.ai` address is
# printed as `<a human account>`.
# Side effect, Lupin's own: a key that passes has its `last_used_at` stamped. Nothing else is written.
# Usage: t19_kernel_account_on_test_server.sh
set -u
HERE="$( cd "$( dirname "$0" )" && pwd )"
OUT="$HERE/out/t19-kernel-account-on-test-server-$( hostname )-$( date +%Y%m%d ).txt"
DATABASE_CONTAINER=lupin-pgvector-test
DATABASE=lupin_db_test
CONFIG="$HOME/.lupin/config"
exec > >( tee "$OUT" ) 2>&1

hr()      { printf '\n== %s ==\n' "$1"; }
eastern() { TZ=America/New_York date '+%Y-%m-%d %H:%M %Z'; }
query()   { docker exec "$DATABASE_CONTAINER" psql -U lupin_dev -d "$DATABASE" -At -F ' | ' -c "$1" 2>&1 | sed 's/^/  /'; }
MASK="case when email like '%deepily.ai' then email else '<a human account>' end"
STAMP="'YYYY-MM-DD HH24:MI'"

hr "host"
echo "  host     $( hostname )"
echo "  account  $( id -un )"
echo "  clock    $( eastern )"
docker ps --format '  container  {{.Names}}  {{.Status}}  {{.Ports}}' | grep -E 'lupin-rest|pgvector' | cut -c1-160

hr "users in $DATABASE (login | active | roles | created | last login, US Eastern)"
query "select $MASK, is_active, roles::text, to_char( created_at at time zone 'America/New_York', 'YYYY-MM-DD' ), coalesce( to_char( last_login_at at time zone 'America/New_York', $STAMP ), 'never' ) from users order by created_at"

hr "keys in $DATABASE (owner | active | description | created | last used, US Eastern; never the hash)"
query "select $MASK, k.is_active, coalesce( k.description, '' ), to_char( k.created_at at time zone 'America/New_York', 'YYYY-MM-DD' ), coalesce( to_char( k.last_used_at at time zone 'America/New_York', $STAMP ), 'never' ) from api_keys k join users u on u.id = k.user_id order by k.created_at"
query "select 'keys: ' || count(*) || ', active: ' || count(*) filter ( where is_active ) from api_keys"

hr "the stored approval settings in $DATABASE (key | updated by | updated)"
query "select key, case when updated_by like '%deepily.ai' then updated_by when updated_by is null then '' else '<a human account>' end, to_char( updated_ts at time zone 'America/New_York', $STAMP ) from approval_settings order by key"
query "select 'rows: ' || count(*) from approval_settings"

hr "this host's service logins ($CONFIG), and whether each is a user row in $DATABASE"
python3 - "$CONFIG" <<'PY' | while IFS='|' read -r section email; do
import configparser, sys
parser = configparser.ConfigParser(); parser.read( sys.argv[ 1 ] )
for section in parser.sections():
    if parser[ section ].get( "email" ): print( f"{section}|{parser[ section ][ 'email' ].strip()}" )
print( "owner_section|" + ( "PRESENT" if "owner" in parser else "absent" ), file=sys.stderr )
PY
    found=$( docker exec "$DATABASE_CONTAINER" psql -U lupin_dev -d "$DATABASE" -Atc "select case when is_active then 'user row, active' else 'user row, inactive' end from users where lower( email ) = lower( '$email' )" 2>/dev/null )
    printf '  %-36s %-58s %s\n' "[$section]" "$email" "${found:-no user row}"
done

hr "the host's key, sent to each port (GET /api/tasks/approval-settings; the key is never printed)"
KEY_FILE=$( python3 - "$CONFIG" <<'PY'
import configparser, os, sys
parser = configparser.ConfigParser(); parser.read( sys.argv[ 1 ] )
default = parser.get( "environments", "default", fallback="" )
print( os.path.expanduser( parser.get( default, "api_key_file", fallback="" ) ) )
PY
)
if [ -r "$KEY_FILE" ]; then
    echo "  key file  $( echo "$KEY_FILE" | sed "s|$HOME|~|" )  mode=$( stat -c %a "$KEY_FILE" )  bytes=$( stat -c %s "$KEY_FILE" )"
    for port in 7999 8000; do
        body=$( mktemp )
        code=$( curl -s -o "$body" -w '%{http_code}' --max-time 30 -H "X-API-Key: $( tr -d '\r\n' < "$KEY_FILE" )" "http://localhost:$port/api/tasks/approval-settings" )
        printf '  port %s  http %s  ' "$port" "$code"
        python3 - "$body" <<'PY'
import json, sys
try:
    with open( sys.argv[ 1 ] ) as handle: reply = json.load( handle )
except Exception as error:
    print( f"body not JSON ({type( error ).__name__})" ); sys.exit( 0 )
if not isinstance( reply, dict ): print( f"body is a {type( reply ).__name__}" ); sys.exit( 0 )
if "detail" in reply and len( reply ) == 1: print( f"detail: {str( reply[ 'detail' ] )[ :120 ]}" ); sys.exit( 0 )
def find( node, name ):
    if isinstance( node, dict ):
        if name in node: return node[ name ]
        for value in node.values():
            found = find( value, name )
            if found is not None: return found
    return None
accounts = find( reply, "approver_accounts" )
shown = "absent from the reply"
if isinstance( accounts, dict ):
    value = accounts.get( "value", accounts ) if "value" in accounts else accounts
    service = [ str( email ) for email in ( value if isinstance( value, ( dict, list ) ) else [ ] ) if "claude.code@" in str( email ).lower() ]
    shown = f"{len( value ) if hasattr( value, '__len__' ) else '?'} account(s), service logins among them: {service or 'none'}"
elif accounts is not None:
    shown = f"a {type( accounts ).__name__}"
print( f"top-level keys: {sorted( reply )[ :12 ]} | approver_accounts: {shown}" )
PY
        rm -f "$body"
    done
else
    echo "  key file  not readable: '${KEY_FILE:-none named under the default environment}'"
fi

hr "done"
echo "  written to $OUT"
