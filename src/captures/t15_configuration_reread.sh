#!/usr/bin/env bash
# t15_configuration_reread.sh — what a re-read of lupin-app.ini costs and how lupin's
# ConfigurationManager behaves when it is read again (row 60 of "Outstanding actions":
# how the kernel re-reads the file at each admission; D62, turn-end policy, part 10).
#
#   t15_configuration_reread.sh <lupin checkout> [block id]      block id defaults to "Lupin: Development"
#
# Three parts, one line per fact, `name value`:
#
#   (a) the file      lines, bytes, blocks, what each block inherits, keys defined in more than
#                     one block, `kernel …` keys present
#   (b) the cost      median milliseconds, 20 runs each: one stat; one bare configparser parse;
#                     one whole ConfigurationManager build (inheritance, defaults, splainer);
#                     the key-to-value dictionary the tables loader takes
#   (c) the manager   on a small fixture in a temporary folder, never on the checkout's file:
#                     a second instance beside the singleton; `init()` in place on a broken file;
#                     `_reset_singleton=True` on a broken file; an override and a `set_config`
#                     value across `init()`; what `init()` prints; a file cut short; a key
#                     written twice; a read made while `init()` is half done
#
# Read-only on the checkout, zero tokens, a few seconds. It imports `cosa`, so it runs under the
# checkout's own interpreter (`.venv/bin/python`) when there is one. Output is meant for
# src/captures/out/t15-configuration-reread-<host>-<date>.txt.

set -u
checkout="${1:?usage: t15_configuration_reread.sh <lupin checkout> [block id]}"
block="${2:-Lupin: Development}"
checkout="$(cd "$checkout" && pwd)" || exit 2
python="$checkout/.venv/bin/python"; [ -x "$python" ] || python="python3"
export PYTHONPATH="$checkout/src" LUPIN_ROOT="${LUPIN_ROOT:-$checkout}"
exec "$python" - "$checkout" "$block" <<'PYTHON'
import collections, configparser, contextlib, datetime, io, os, socket, statistics, subprocess, sys, tempfile, time, zoneinfo

checkout, block = sys.argv[ 1 ], sys.argv[ 2 ]
ini      = os.path.join( checkout, "src/conf/lupin-app.ini" )
splainer = os.path.join( checkout, "src/conf/lupin-app-splainer.ini" )

def say( name, value ): print( f"{name:<44} {value}" )

def quiet( function, *args, **kwargs ):
    """Run with stdout captured; return ( result or the exception, the lines printed )."""
    buffer = io.StringIO()
    with contextlib.redirect_stdout( buffer ):
        try:                       result = function( *args, **kwargs )
        except BaseException as e: result = e
    return result, buffer.getvalue().count( "\n" )

def median_ms( function, runs=20 ):
    times = [ ]
    for _ in range( runs ):
        start = time.perf_counter(); function(); times.append( ( time.perf_counter() - start ) * 1000 )
    return f"{statistics.median( times ):.3f} ms (max {max( times ):.3f})"

head = subprocess.run( [ "git", "-C", checkout, "rev-parse", "--short=10", "HEAD" ], capture_output=True, text=True ).stdout.strip()
dirty = subprocess.run( [ "git", "-C", checkout, "status", "--porcelain", "--", "src/conf/lupin-app.ini" ], capture_output=True, text=True ).stdout.strip()
say( "host", socket.gethostname() )
say( "when", datetime.datetime.now( zoneinfo.ZoneInfo( "America/New_York" ) ).strftime( "%Y-%m-%d %H:%M %Z" ) + " (app timezone)" )
say( "python", sys.version.split()[ 0 ] + " " + sys.executable )
say( "lupin_head", head + ( " (lupin-app.ini modified in the working tree)" if dirty else "" ) )
say( "block", block )

print( "\n(a) the file" )
text = open( ini ).read()
say( "ini_lines_bytes", f"{text.count( chr( 10 ) )} {len( text.encode() )}" )
say( "splainer_lines_bytes", f"{open( splainer ).read().count( chr( 10 ) )} {os.path.getsize( splainer )}" )
parser = configparser.ConfigParser(); parser.read( ini )
for section in parser.sections():
    own      = set( parser._sections[ section ] )
    inherits = parser._sections[ section ].get( "inherits", "-" )
    say( f"block [{section}]", f"keys={len( own )} inherits={inherits} inherits_a_file={os.path.isfile( inherits )}" )
where = collections.defaultdict( list )
for section in parser.sections():
    for key in parser._sections[ section ]:
        if key != "inherits": where[ key ].append( section )
say( "keys_distinct", len( where ) )
say( "keys_in_more_than_one_block", sum( len( sections ) > 1 for sections in where.values() ) )
say( "kernel_keys_present", sum( key.startswith( "kernel " ) for key in where ) )

print( "\n(b) the cost" )
from cosa.config.configuration_manager import ConfigurationManager
first, _ = quiet( ConfigurationManager, config_path=ini, splainer_path=splainer, config_block_id=block, silent=True, _reset_singleton=True )
if isinstance( first, BaseException ):
    say( "manager_build", f"FAILED {type( first ).__name__}: {first}" ); sys.exit( 1 )
Manager = type( first )                                       # the class itself; the module's name is the singleton wrapper
def bare():
    p = configparser.ConfigParser(); p.read( ini )
def whole():
    return Manager( config_path=ini, splainer_path=splainer, config_block_id=block, silent=True )
def whole_then_pairs():
    manager = whole(); return { key: manager.config.get( manager.config_block_id, key ) for key in manager.get_keys() }
say( "stat", median_ms( lambda: os.stat( ini ) ) )
say( "bare_configparser_parse", median_ms( bare ) )
say( "whole_manager_build", median_ms( lambda: quiet( whole ) ) )
say( "whole_manager_build_and_pairs", median_ms( lambda: quiet( whole_then_pairs ) ) )
say( "keys_in_force_for_block", len( first.get_keys() ) )

print( "\n(c) the manager, on a fixture" )
folder   = tempfile.mkdtemp( prefix="t15-reread-" )
fixture  = os.path.join( folder, "app.ini" )
splain   = os.path.join( folder, "splainer.ini" )
GOOD     = "[default]\nzone = east\n\n[child]\ninherits = parent\nown key = 1\n\n[parent]\nkernel fleet size cap = 14\nkernel fleet batch cap = 8\n"
def write( content ):
    with open( fixture, "w" ) as handle: handle.write( content )
write( GOOD ); open( splain, "w" ).write( "[default]\nown key = a key\n" )
def build( **kwargs ): return quiet( ConfigurationManager, config_path=fixture, splainer_path=splain, config_block_id="child", silent=True, **kwargs )
def cap( manager ):
    value, _ = quiet( manager.get, "kernel fleet size cap", silent=True ); return value

manager, _ = build( _reset_singleton=True )
other, _   = quiet( Manager, config_path=fixture, splainer_path=splain, config_block_id="child", silent=True )
same, _    = build()
say( "second_instance_is_separate", f"{other is not manager}; the singleton is untouched={same is manager}; both read cap={cap( manager )},{cap( other )}" )

write( GOOD.replace( "= 14", "= 15" ) )
say( "singleton_sees_edit_without_reread", cap( manager ) == "15" )
fresh, _ = quiet( Manager, config_path=fixture, splainer_path=splain, config_block_id="child", silent=True )
say( "second_instance_sees_edit", cap( fresh ) == "15" )

BROKEN = GOOD + "this line has no separator\n"
write( BROKEN )
result, _ = quiet( manager.init, silent=True )
say( "init_in_place_on_broken_file", f"raises {type( result ).__name__}; afterwards cap reads {cap( manager )!r} (was '14')" )
write( GOOD ); quiet( manager.init, silent=True )
say( "init_in_place_after_repair", f"cap reads {cap( manager )!r}" )

write( BROKEN )
result, _ = build( _reset_singleton=True )
again, _  = build()
say( "reset_singleton_on_broken_file", f"raises {type( result ).__name__}; the old instance still reads {cap( manager )!r}; the next plain call {'raises ' + type( again ).__name__ if isinstance( again, BaseException ) else 'returns an instance'}" )
second, _ = quiet( Manager, config_path=fixture, splainer_path=splain, config_block_id="child", silent=True )
say( "second_instance_on_broken_file", f"raises {type( second ).__name__}; nothing else is touched" )
write( GOOD )

manager, _ = build( _reset_singleton=True, cli_args={ "kernel fleet size cap": "3" } )
before = cap( manager ); quiet( manager.init, silent=True )
say( "override_across_init", f"before {before!r}, after {cap( manager )!r}" )
manager.set_config( "kernel fleet size cap", 5 ); quiet( manager.init, silent=True )
say( "set_config_across_init", f"set 5, after init {cap( manager )!r}" )

manager, _ = build( _reset_singleton=True )
_, lines   = quiet( manager.init )
say( "init_with_no_arguments", f"prints {lines} lines; silent is now {manager.silent}" )

write( GOOD[ : GOOD.index( "kernel fleet batch cap" ) ] )
short, _ = quiet( Manager, config_path=fixture, splainer_path=splain, config_block_id="child", silent=True )
batch, _ = ( None, 0 ) if isinstance( short, BaseException ) else quiet( short.get, "kernel fleet batch cap", silent=True )
say( "file_cut_short_in_the_parent_block", f"{'raises ' + type( short ).__name__ if isinstance( short, BaseException ) else 'builds without error'}; batch cap reads {batch!r}" )
write( GOOD[ : GOOD.index( "[parent]" ) ] )
short, _ = quiet( Manager, config_path=fixture, splainer_path=splain, config_block_id="child", silent=True )
say( "file_cut_short_before_the_parent_block", f"{'raises ' + type( short ).__name__ if isinstance( short, BaseException ) else 'builds without error'}" )
write( "" )
short, _ = quiet( Manager, config_path=fixture, splainer_path=splain, config_block_id="child", silent=True )
say( "file_empty", f"{'raises ' + type( short ).__name__ if isinstance( short, BaseException ) else 'builds without error'}" )

write( GOOD + "kernel fleet size cap = 16\n" )
twice, _ = quiet( Manager, config_path=fixture, splainer_path=splain, config_block_id="child", silent=True )
say( "key_written_twice_in_one_block", f"{'raises ' + type( twice ).__name__ if isinstance( twice, BaseException ) else 'builds; cap reads ' + repr( cap( twice ) )}" )
write( GOOD.replace( "own key = 1", "own key = 1\nkernel fleet size cap = 9" ) )
both, _ = quiet( Manager, config_path=fixture, splainer_path=splain, config_block_id="child", silent=True )
say( "key_in_child_and_parent", f"builds; cap reads {cap( both )!r} (the child's)" )

write( GOOD )
manager, _ = build( _reset_singleton=True )
seen, original = [ ], manager._calculate_inheritance
def halfway(): seen.append( cap( manager ) ); original()
manager._calculate_inheritance = halfway
quiet( manager.init, silent=True )
say( "read_while_init_is_half_done", f"an inherited key reads {seen[ 0 ]!r} inside init(), {cap( manager )!r} after" )

before = os.stat( fixture )
temporary = fixture + ".new"
with open( temporary, "w" ) as handle: handle.write( GOOD )
os.replace( temporary, fixture )
after = os.stat( fixture )
say( "atomic_replace_same_bytes", f"inode changed={before.st_ino != after.st_ino}; size changed={before.st_size != after.st_size}; mtime_ns changed={before.st_mtime_ns != after.st_mtime_ns}" )

quiet( ConfigurationManager.reset_for_testing )
for name in os.listdir( folder ): os.remove( os.path.join( folder, name ) )
os.rmdir( folder )
PYTHON
