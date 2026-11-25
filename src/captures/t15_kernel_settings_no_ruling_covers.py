#!/usr/bin/env python3
"""Row 142: list the kernel settings whose splainer line says neither "Required" nor "Optional".

Zero tokens; writes nothing. Reads the splainer lines of the turn-end policy spec's amendments
from 2026-11-24 (row 138) on, a later line replacing an earlier one of the same name and a
withdrawn name left out, and prints, family by family, every setting no ruling made required
or optional, with the value its spec's configuration block gives and whether its line states
a default. With --check it exits 1 while any such setting remains.

Before the rulings of row 142: 55 (14 with a stated default, 41 with none). After: the five
`kernel grant ...` settings, which wait for row 7 of "Outstanding actions".

    python3 src/captures/t15_kernel_settings_no_ruling_covers.py [--check]
"""
import glob
import os
import re
import sys

sys.path.insert( 0, os.path.dirname( os.path.abspath( __file__ ) ) )
from t15_kernel_settings_without_splainer_line import WITHDRAWN

ROOT     = os.path.join( os.path.dirname( os.path.abspath( __file__ ) ), "..", "rnd", "v0.0.1" )
SPEC     = os.path.join( ROOT, "specs", "2026.11.10-t15-turn-end-policy-spec.md" )
HEADING  = "## Amendment (2026-11-24, row 138"
FAMILIES = [
    ( "the session and the voice", ( "kernel engine update policy", "kernel watch ", "kernel interrupt exit", "kernel voice out " ) ),
    ( "the log",                   ( "kernel log ", ) ),
    ( "the fleet",                 ( "kernel fleet ", ) ),
    ( "the host",                  ( "kernel host ", ) ),
    ( "the kernel's lifecycle",    ( "kernel stop ", "kernel crash loop ", "kernel gate retry", "kernel memento verify", "kernel archive ", "kernel job " ) ),
    ( "the end of a turn",         ( "kernel turn end ", ) ),
    ( "the inbox",                 ( "kernel inbox ", ) ),
    ( "the control API",           ( "kernel accept ", "kernel client retry", "kernel idempotency", "kernel interrupt hold", "kernel upgrade ", "kernel message limit" ) ),
    ( "grants",                    ( "kernel grant ", ) ),
]

def read_splainer_lines():
    lines   = open( SPEC, encoding="utf-8" ).read().split( "\n" )
    start   = next( i for i, line in enumerate( lines ) if line.startswith( HEADING ) )
    found   = {}
    fenced, inside = False, False
    for line in lines[ start: ]:
        if line.startswith( "```" ):
            fenced, inside = not fenced, False
        elif fenced and line.strip() == "[default]":
            inside = True
        elif inside and line.startswith( "kernel " ):
            name, text = line.split( "=", 1 )
            found[ name.strip() ] = text.strip()                 # a later amendment's line replaces an earlier one
    return start, [ ( name, text ) for name, text in found.items() if name not in WITHDRAWN ]

def find_block_value( name, before_line ):
    """The value the setting's own spec gives it in a configuration block, or None."""
    pattern = re.compile( r"^\s*" + re.escape( name ) + r"\s*=\s*(.*?)\s*(;.*)?$" )
    for path in sorted( glob.glob( os.path.join( ROOT, "specs", "*.md" ) ) ):
        for number, line in enumerate( open( path, encoding="utf-8" ).read().split( "\n" ) ):
            if os.path.samefile( path, SPEC ) and number >= before_line:
                break
            match = pattern.match( line )
            if match:
                return match.group( 1 )
    return None

def name_family( name ):
    for family, prefixes in FAMILIES:
        if any( ( name + " " ).startswith( prefix ) for prefix in prefixes ):
            return family
    return "no family"

def main():
    start, found = read_splainer_lines()
    uncovered    = [ ( n, t ) for n, t in found if "Required" not in t and "Optional" not in t ]
    with_default = [ n for n, t in uncovered if re.search( r"\bDefault\b", t ) ]
    print( f"splainer lines from the row 138 amendment on : {len( found )}" )
    print( f"  say neither \"Required\" nor \"Optional\"     : {len( uncovered )}" )
    print( f"    state a default from their spec         : {len( with_default )}" )
    print( f"    state none                              : {len( uncovered ) - len( with_default )}" )
    for family in [ f for f, _ in FAMILIES ] + [ "no family" ]:
        members = [ ( n, t ) for n, t in uncovered if name_family( n ) == family ]
        if not members: continue
        print( f"\n== {family} ({len( members )})" )
        for name, text in members:
            default = re.search( r"\bDefault (.+?)\. ", text + " " )
            bounded = re.search( r"\bFrom \d+ to \d+", text )
            note    = ( f"line: default {default.group( 1 )}" if default else "line: no default" ) + ( "; bounds stated" if bounded else "" )
            print( f"   {name:52} block: {str( find_block_value( name, start ) ):26} {note}" )
    if "--check" in sys.argv and uncovered:
        sys.exit( 1 )

if __name__ == "__main__":
    main()
