#!/usr/bin/env bash
# t22_meter_shape.sh: the usage meter's real shape on this host, against what the sign-in and
# quota spec (D68, register item T22) was written to. Row 21 of "Outstanding actions".
#
# Zero tokens: it runs `agy -p "/usage" --output-format json` twice, a few seconds apart, and
# reads files in this checkout. It writes one file under src/captures/out/ and nothing else.
# It prints no secret, token or email address.
#
# Usage: src/captures/t22_meter_shape.sh [seconds between the two reads, default 5]

set -u
HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$( cd "$HERE/../.." && pwd )"
GAP="${1:-5}"
BIN="$( command -v agy || true )"
STAMP="$( TZ=America/New_York date +%Y%m%d )"
OUT="$HERE/out/t22-meter-shape-$( hostname -s )-$STAMP.txt"
SCRATCH="$( mktemp -d )"
trap 'rm -rf "$SCRATCH"' EXIT

if [ -z "$BIN" ]; then echo "agy not on PATH; nothing read"; exit 1; fi

timeout 60 "$BIN" -p "/usage" --output-format json </dev/null >"$SCRATCH/first.json"  2>"$SCRATCH/first.stderr"
sleep "$GAP"
timeout 60 "$BIN" -p "/usage" --output-format json </dev/null >"$SCRATCH/second.json" 2>"$SCRATCH/second.stderr"
timeout 30 "$BIN" models </dev/null >"$SCRATCH/models.txt" 2>&1 || true

python3 - "$SCRATCH" "$ROOT" "$( "$BIN" --version 2>/dev/null | head -1 )" <<'PY' | tee "$OUT"
import json, os, re, sys, importlib.util
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

scratch, root, version = sys.argv[ 1 ], sys.argv[ 2 ], sys.argv[ 3 ]
EASTERN = ZoneInfo( "America/New_York" )

def read_reply( name ):
    with open( os.path.join( scratch, name ) ) as handle: return json.load( handle )

def get_groups( reply ):
    return ( ( reply.get( "command" ) or {} ).get( "data" ) or {} ).get( "groups" ) or []

def parse_time( text ):
    return datetime.fromisoformat( text.replace( "Z", "+00:00" ) )

first, second = read_reply( "first.json" ), read_reply( "second.json" )
now = datetime.now( timezone.utc )
print( "# The usage meter's shape (row 21; zero tokens)" )
print( "read at            :", now.astimezone( EASTERN ).strftime( "%Y-%m-%d %H:%M:%S %Z" ) )
print( "engine version     :", version )
print( "reply status       :", first.get( "status" ), "| turns:", first.get( "num_turns" ), "| tokens:", ( first.get( "usage" ) or {} ).get( "total_tokens" ) )
print( "command name       :", ( first.get( "command" ) or {} ).get( "name" ) )

groups = get_groups( first )
windows, bucket_count = set(), 0
print()
print( "## Groups, as the meter prints them" )
for group in groups:
    models = re.sub( r"^Models within this group:\s*", "", group.get( "description", "" ) )
    print( f"- group \"{group.get( 'name' )}\" ({len( group.get( 'buckets' ) or [] )} bucket)" )
    print( f"    models         : {models}" )
    for bucket in group.get( "buckets" ) or []:
        bucket_count += 1
        windows.add( bucket.get( "window" ) )
        reset = parse_time( bucket[ "reset_time" ] ) if bucket.get( "reset_time" ) else None
        hours = ( reset - now ).total_seconds() / 3600 if reset else None
        print( f"    bucket         : id {bucket.get( 'id' )} | window {bucket.get( 'window' )} | name \"{bucket.get( 'name' )}\"" )
        print( f"    remaining      : {bucket.get( 'remaining_fraction' ):.4f}" )
        print( f"    reset          : {reset.astimezone( EASTERN ).strftime( '%Y-%m-%d %H:%M:%S %Z' ) if reset else None} ({hours:.2f} h from the read)" if reset else "    reset          : none" )
        print( f"    bucket fields  : {sorted( bucket.keys() )}" )
print()
print( "groups             :", len( groups ) )
print( "buckets            :", bucket_count )
print( "distinct windows   :", sorted( str( window ) for window in windows ) )

print()
print( "## Does a reset time stand still? (two reads)" )
for before, after in zip( get_groups( first ), get_groups( second ) ):
    for bucket_before, bucket_after in zip( before.get( "buckets" ) or [], after.get( "buckets" ) or [] ):
        moved = ( parse_time( bucket_after[ "reset_time" ] ) - parse_time( bucket_before[ "reset_time" ] ) ).total_seconds()
        used  = bucket_before.get( "remaining_fraction", 1 ) < 1
        print( f"- {before.get( 'name' ):24s} remaining {bucket_before.get( 'remaining_fraction' ):.4f} | drawn on: {'yes' if used else 'no '} | reset moved {moved:+.0f} s between the reads" )

print()
print( "## The spec's parser on this reply (specs/t22-reference/engine_account.py, unchanged)" )
path = os.path.join( root, "src/rnd/v0.0.1/specs/t22-reference/engine_account.py" )
spec = importlib.util.spec_from_file_location( "engine_account", path )
module = importlib.util.module_from_spec( spec ); sys.modules[ "engine_account" ] = module; spec.loader.exec_module( module )
parsed = module.parse_usage( first )
print( "group names it knows   :", sorted( module.POOL_BY_GROUP_NAME ) )
print( "window names it knows  :", sorted( module.WINDOW_NAMES ) )
print( "group names matched    :", sum( 1 for group in groups if str( group.get( "name", "" ) ).strip().lower() in module.POOL_BY_GROUP_NAME ), "of", len( groups ) )
print( "window names matched   :", sum( 1 for window in windows if window in module.WINDOW_NAMES ), "of", len( windows ) )
print( "buckets it returns     :", len( parsed ), "of", bucket_count )
for model in ( "fable-5.1-high", "opus-5.5-high" ):
    pool = module.pool_for_model( model )
    print( f"default role model {model:15s} -> pool `{pool}`; remaining it would read: {[ bucket.remaining_fraction for bucket in parsed if bucket.pool == pool ] or 'unknown (admits)'}" )

print()
print( "## `agy models` (the identifiers a manifest carries)" )
with open( os.path.join( scratch, "models.txt" ) ) as handle: listing = handle.read().strip()
print( "\n".join( "    " + line for line in listing.splitlines()[ :60 ] ) or "    (nothing printed)" )

print()
print( "## Readings the record holds for the third-party group (00-status.md and transcripts/)" )
import glob
sources = [ os.path.join( root, "src/rnd/v0.0.1/00-status.md" ) ] + sorted( glob.glob( os.path.join( root, "src/rnd/v0.0.1/transcripts/*.md" ) ) )
readings, pairs = set(), set()
for source in sources:
    with open( source ) as handle: body = handle.read()
    for found in re.finditer( r"(?i)third-party models[^\n]{0,140}", body ):
        percents = tuple( float( value ) for value in re.findall( r"(\d+(?:\.\d+)?)\s?%", found.group( 0 ) ) )[ :2 ]
        readings.update( percents )
        if len( percents ) == 2 and percents[ 0 ] > percents[ 1 ]: pairs.add( percents )
draws = sorted( round( first - last, 1 ) for first, last in pairs )
print( "distinct readings              :", len( readings ) )
print( "lowest reading                 :", min( readings ) if readings else None )
print( "opening and closing pairs      :", len( pairs ) )
print( "draw of one planning session   : median", draws[ len( draws ) // 2 ] if draws else None, "| largest", draws[ -1 ] if draws else None, "points" )
print( "(a planning session is one persona at work; no reading of a fleet exists)" )
PY
echo "written: $OUT"
