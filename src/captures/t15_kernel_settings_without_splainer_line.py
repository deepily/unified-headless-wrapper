#!/usr/bin/env python3
"""Which `kernel …` settings of the record have no splainer line. Zero tokens; it writes nothing.

Run at every recording (ruling protocol, Section 6; row 138, ruling 4). Row 138 of "Outstanding actions"
(2026-11-24): every amendment that adds a kernel setting writes the setting's line
for lupin's `lupin-app-splainer.ini` (the turn-end policy spec's amendment of 2026-11-24, decision 16), one line for
each setting under its exact name. This script reads the specs and the framework and counts.

    python3 src/captures/t15_kernel_settings_without_splainer_line.py            # the count and the list
    python3 src/captures/t15_kernel_settings_without_splainer_line.py --check    # exit 1 while a setting has no line

What it takes for a setting: a name beginning `kernel ` that the record writes whole, either at the start of a line
inside a fenced block (`kernel stop drain seconds = 180`) or between backticks in the text or a table. A name with a
placeholder or an ellipsis (`kernel memory <engine> cap bytes`, `kernel fleet …`) is a form, not a setting, and is
listed apart. What it takes for a line: the same name at the start of a line in a fenced block that opens with
`[default]`, the one section of lupin's splainer file.

Two ledgers are kept by hand, each entry with the place in the record that says so: `WITHDRAWN` (a setting a ruling
removed) and `NOT_SETTINGS` (a prefix, or a name a test made up). A name the record adds later appears in the list
until its line is written or a ledger names it.
"""
import pathlib
import re
import sys

REPOSITORY = pathlib.Path( __file__ ).resolve().parents[ 2 ]
RECORD     = REPOSITORY / "src/rnd/v0.0.1"
FRAMEWORK  = "framework"

WITHDRAWN = {
    "kernel engine login check seconds"         : "sign-in and quota spec, amendment of 2026-11-23 (rows 124 and 125), ruling 1",
    "kernel engine login warn hours"            : "the same amendment, ruling 4",
    "kernel engine force file storage"          : "the same amendment, ruling 6",
    "kernel usage rollup at"                    : "the same amendment, ruling 8",
    "kernel engine prices"                      : "the same amendment: one setting became three for each model",
    "kernel engine quota spawn floor five hour" : "sign-in and quota spec, amendment of 2026-11-23 (row 21), ruling 3",
    "kernel engine quota spawn floor weekly"    : "the same ruling",
    "kernel engine quota reserve five hour"     : "the same amendment, ruling 5",
    "kernel memory agy heap mebibytes"          : "host-capacity spec, amendment of 2026-11-23 (row 61), ruling 7",
    "kernel job memento verify at"              : "kernel lifecycle spec, amendment of 2026-11-24 (row 138), ruling 1",
    "kernel job archive sweep at"               : "the same ruling",
    "kernel job log sweep every seconds"        : "the same ruling",
    "kernel job tree sweep every seconds"       : "the same ruling",
    "kernel log sweep interval minutes"         : "log schema and rotation spec, amendment of 2026-11-24 (row 138), ruling 1",
    "kernel inbox dm grades"                    : "broadcasts spec, amendment of 2026-11-24 (row 142), ruling 8a: renamed `kernel inbox grade dms`",
}
NOT_SETTINGS = {
    "kernel fleet"                               : "a prefix (engine-neutral naming spec, ruling 2)",
    "kernel memory"                              : "a prefix",
    "kernel engine pool name"                    : "a prefix: the bare name, with no pool after it, is passed over",
    "kernel engine pool name third_party models" : "a test's counter-example (an underscore where a space belongs)",
    "kernel engine pool names x"                 : "a test's counter-example",
}

BLOCK_NAME  = re.compile( r"^\s*(kernel [^=`]+?)\s*=" )
TICKED_NAME = re.compile( r"`(kernel [^`=]+?)\s*(?:=[^`]*)?`" )
WHOLE_NAME  = re.compile( r"^kernel (?!.*\.\.)[a-z0-9][a-z0-9 .-]*$" )
SPEC_TAG    = re.compile( r"-(t\d+|phase1)-" )

def get_sources():
    """Ensures: ( tag, path ) for every spec, then the framework."""
    sources = []
    for path in sorted( ( RECORD / "specs" ).glob( "*.md" ) ):
        tag = SPEC_TAG.search( path.name )
        sources.append( ( tag.group( 1 ) if tag else path.stem, path ) )
    sources.append( ( FRAMEWORK, RECORD / "01-framework.md" ) )
    return sources

def read_names( sources ):
    """Ensures: ( named, explained ): each name mapped to the `tag:line` places that write it, and to those that
    write its splainer line."""
    named, explained = {}, {}
    for tag, path in sources:
        fenced, splainer = False, False
        for number, line in enumerate( path.read_text( encoding="utf-8" ).split( "\n" ), 1 ):
            if line.lstrip().startswith( "```" ):
                fenced, splainer = not fenced, False
                continue
            found = [ match.group( 1 ) for match in TICKED_NAME.finditer( line ) ]
            if fenced:
                if line.strip() == "[default]": splainer = True
                match = BLOCK_NAME.match( line )
                if match:
                    found.append( match.group( 1 ) )
                    if splainer: explained.setdefault( match.group( 1 ).strip(), [] ).append( f"{tag}:{number}" )
            for name in found:
                named.setdefault( " ".join( name.split() ), [] ).append( f"{tag}:{number}" )
    return named, explained

def sort_names( named, explained ):
    """Ensures: a dict of lists: `settings` (whole names in neither ledger), `forms`, `withdrawn`, `not_settings`,
    `unexplained` (settings with no line), `framework_only` (settings no spec names)."""
    whole     = [ name for name in named if WHOLE_NAME.match( name ) ]
    settings  = sorted( name for name in whole if name not in WITHDRAWN and name not in NOT_SETTINGS )
    return {
        "settings"       : settings,
        "forms"          : sorted( name for name in named if not WHOLE_NAME.match( name ) ),
        "withdrawn"      : sorted( name for name in whole if name in WITHDRAWN ),
        "not_settings"   : sorted( name for name in whole if name in NOT_SETTINGS ),
        "unexplained"    : [ name for name in settings if name not in explained ],
        "framework_only" : [ name for name in settings if all( place.startswith( FRAMEWORK ) for place in named[ name ] ) ],
    }

def get_first_spec( places ):
    """Ensures: the tag of the first spec that writes the name, the framework's only when no spec does."""
    tags = [ place.split( ":" )[ 0 ] for place in places ]
    return next( ( tag for tag in tags if tag != FRAMEWORK ), FRAMEWORK )

def print_report( named, explained, sorted_names ):
    settings, unexplained = sorted_names[ "settings" ], sorted_names[ "unexplained" ]
    print( f"kernel settings the record names whole : {len( settings )}" )
    print( f"  with a splainer line                 : {len( settings ) - len( unexplained )}" )
    print( f"  with none                            : {len( unexplained )}" )
    print( f"withdrawn by a ruling (no line owed)   : {len( sorted_names[ 'withdrawn' ] )}" )
    print( f"prefixes and tests' made-up names      : {len( sorted_names[ 'not_settings' ] )}" )
    print( f"forms with a placeholder or an ellipsis: {len( sorted_names[ 'forms' ] )}" )
    print( f"settings only the framework names      : {len( sorted_names[ 'framework_only' ] )}" )
    by_spec = {}
    for name in unexplained: by_spec.setdefault( get_first_spec( named[ name ] ), [] ).append( name )
    print( "\n== with no line, by the first spec that names each" )
    for tag in sorted( by_spec ):
        print( f"-- {tag} ({len( by_spec[ tag ] )})" )
        for name in by_spec[ tag ]: print( f"   {name:66s} {', '.join( named[ name ][ :3 ] )}" )
    print( "\n== with a line" )
    for name in settings:
        if name in explained: print( f"   {name:66s} {', '.join( explained[ name ] )}" )
    print( "\n== withdrawn" )
    for name in sorted_names[ "withdrawn" ]: print( f"   {name:44s} {WITHDRAWN[ name ]}" )
    print( "\n== not settings" )
    for name in sorted_names[ "not_settings" ]: print( f"   {name:44s} {NOT_SETTINGS[ name ]}" )
    print( "\n== forms" )
    for name in sorted_names[ "forms" ]: print( f"   {name}" )
    for name in sorted_names[ "framework_only" ]: print( f"\nonly in the framework: {name} ({', '.join( named[ name ] )})" )

def main( arguments ):
    named, explained = read_names( get_sources() )
    sorted_names     = sort_names( named, explained )
    if "--check" in arguments:
        for name in sorted_names[ "unexplained" ]: print( f"no splainer line: {name} ({', '.join( named[ name ][ :3 ] )})" )
        print( f"{len( sorted_names[ 'unexplained' ] )} of {len( sorted_names[ 'settings' ] )} kernel settings have no splainer line" )
        return 1 if sorted_names[ "unexplained" ] else 0
    print_report( named, explained, sorted_names )
    return 0

if __name__ == "__main__":
    sys.exit( main( sys.argv[ 1: ] ) )
