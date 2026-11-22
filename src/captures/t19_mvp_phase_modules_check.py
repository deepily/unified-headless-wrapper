#!/usr/bin/env python3
"""Check that the plan of the Single persona kernel MVP (Phase 1) places every module once.

Row 116 of "Outstanding actions" (2026-11-22), rulings 3 and 10: the Phase 1 spec carries an
amendment with one "Phase N" sub-heading for each phase of the plan that the cascaded review of
planning-is-prompting (PiP) reads, and every module of the spec's Section 3 layout that the MVP
needs stands under exactly one of those headings. Zero tokens; it writes nothing.

    t19_mvp_phase_modules_check.py --check        exit 1, with a line saying why, on any failure
    t19_mvp_phase_modules_check.py --self-test    the check against texts built to fail

It fails when:
  - a module of the layout not marked "Phase 2" stands under no phase, or under two;
  - a module marked "Phase 2" in the layout stands under a phase;
  - a phase names a .py file the layout lacks, other than the three of the convention-kit port;
  - the phase headings are not numbered 1 to N without a gap;
  - the spec's title is itself read as a phase heading.
"""
import pathlib
import re
import sys

sys.dont_write_bytecode = True

REPOSITORY = pathlib.Path( __file__ ).resolve().parents[ 2 ]
SPEC = REPOSITORY / "src/rnd/v0.0.1/specs/2026.10.24-phase1-kernel-and-jetski-family-adapter-spec.md"

# The heading PiP's importer reads as a phase heading (workflow/scripts/plan_stub_import.py,
# PLAN_HEAD_RE, numbered form), copied here so the check needs no import from PiP.
PHASE_HEADING = re.compile( r"^#{1,6}\s+(?:\d+(?:\.\d+)*\.?\s+)?Phase\s+(\d+)(?![A-Za-z0-9-])(.*)$", re.IGNORECASE )
LAYOUT_LINE = re.compile( r"^\s+([A-Za-z_/]+\.py)\s+(.*)$" )
MODULE_TOKEN = re.compile( r"`([A-Za-z_/]+\.py)`" )

# Named by Section 13, step 8, and absent from the layout (T18 spec Section 9).
PORT_MODULES = { "provision.py", "first_turn.py", "respin.py" }


def read_layout( text ):
    """
    Requires: text is the spec; its Section 3 holds one fenced block listing the modules.
    Ensures: returns ( needed, later ): base names of the modules the MVP needs, and of those
             the layout marks "Phase 2". Test files are not modules.
    """
    section = text.split( "\n## 3. Layout", 1 )[ 1 ].split( "\n## ", 1 )[ 0 ]
    block = section.split( "```", 2 )[ 1 ]
    needed, later = [], []
    for line in block.splitlines():
        match = LAYOUT_LINE.match( line )
        if not match: continue
        name = match.group( 1 ).rsplit( "/", 1 )[ -1 ]
        if name.startswith( "test_" ): continue
        ( later if match.group( 2 ).rstrip().endswith( "Phase 2" ) else needed ).append( name )
    return needed, later


def read_phases( text ):
    """
    Requires: text is the spec.
    Ensures: returns [ ( number, heading line number, [ module base names ] ) ] in file order;
             a phase's body runs to the next heading of any level that is a phase heading or
             a second-level heading.
    """
    phases, current = [], None
    for index, line in enumerate( text.splitlines(), 1 ):
        match = PHASE_HEADING.match( line )
        if match:
            current = ( int( match.group( 1 ) ), index, [] )
            phases.append( current )
            continue
        if line.startswith( "## " ):
            current = None
            continue
        if current is not None:
            current[ 2 ].extend( token.rsplit( "/", 1 )[ -1 ] for token in MODULE_TOKEN.findall( line ) )
    return phases


def find_faults( text ):
    """
    Requires: text is the spec.
    Ensures: returns ( faults, report ): faults is a list of sentences, empty when the plan
             places every needed module exactly once; report is the lines to print.
    """
    needed, later = read_layout( text )
    phases = read_phases( text )
    faults, report = [], []
    report.append( f"layout_modules_needed                        {len( needed )}" )
    report.append( f"layout_modules_marked_phase_2                {len( later )}: {' '.join( later )}" )
    report.append( f"phase_headings                               {[ number for number, _, _ in phases ]}" )
    if text.splitlines() and PHASE_HEADING.match( text.splitlines()[ 0 ] ):
        faults.append( "the spec's title is read as a phase heading" )
    numbers = [ number for number, _, _ in phases ]
    if numbers != list( range( 1, len( numbers ) + 1 ) ):
        faults.append( f"the phase headings are not numbered 1 to N in order: {numbers}" )
    placed = {}
    for number, line_number, modules in phases:
        report.append( f"phase_{number}[line {line_number}]".ljust( 45 ) + f"{len( modules )}: {' '.join( modules )}" )
        for name in modules:
            placed.setdefault( name, [] ).append( number )
    for name in needed:
        where = placed.get( name, [] )
        if not where: faults.append( f"{name} stands under no phase" )
        elif len( where ) > 1: faults.append( f"{name} stands under phases {where}" )
    for name in later:
        if name in placed: faults.append( f"{name} is marked Phase 2 in the layout and stands under phase {placed[ name ]}" )
    outside = sorted( name for name in placed if name not in needed and name not in later )
    report.append( f"named_in_a_phase_and_not_in_the_layout       {len( outside )}: {' '.join( outside )}" )
    for name in outside:
        if name not in PORT_MODULES: faults.append( f"{name} is named in a phase and is not in the layout" )
        elif len( placed[ name ] ) > 1: faults.append( f"{name} stands under phases {placed[ name ]}" )
    return faults, report


def build_fixture( phase_bodies, title = "# Single persona kernel MVP (Phase 1): a fixture" ):
    layout = "\n## 3. Layout\n\n```\nsrc/uhw_kernel/\n  events.py   types\n  log/sweep.py   retention\n  fleet_rules.py   pure; Phase 2\n  tests/\n    test_*.py   unit tests\n```\n\n## 4. Types\n"
    phases = "".join( f"\n### Phase {number}: fixture\n\n{body}\n" for number, body in phase_bodies )
    return title + "\n" + layout + "\n## Amendment\n" + phases


def run_self_test():
    cases = [
        ( "every module once",        build_fixture( [ ( 1, "`events.py`" ), ( 2, "`log/sweep.py`" ) ] ), 0 ),
        ( "a module under no phase",   build_fixture( [ ( 1, "`events.py`" ) ] ), 1 ),
        ( "a module under two phases", build_fixture( [ ( 1, "`events.py` `sweep.py`" ), ( 2, "`events.py`" ) ] ), 1 ),
        ( "a Phase 2 module placed",   build_fixture( [ ( 1, "`events.py` `sweep.py` `fleet_rules.py`" ) ] ), 1 ),
        ( "a file the layout lacks",   build_fixture( [ ( 1, "`events.py` `sweep.py` `stranger.py`" ) ] ), 1 ),
        ( "a port module allowed",     build_fixture( [ ( 1, "`events.py` `sweep.py`" ), ( 2, "`provision.py`" ) ] ), 0 ),
        ( "a gap in the numbering",    build_fixture( [ ( 1, "`events.py`" ), ( 3, "`sweep.py`" ) ] ), 1 ),
        ( "the title read as a phase", build_fixture( [ ( 2, "`events.py` `sweep.py`" ) ], title = "# Phase 1 spec: a fixture" ), 1 ),
    ]
    failed = 0
    for name, text, expected in cases:
        faults, _ = find_faults( text )
        passed = len( faults ) == expected
        failed += not passed
        print( f"self_test[{name}]".ljust( 45 ) + ( "ok" if passed else f"FAILED: {faults}" ) )
    return 1 if failed else 0


def main( arguments ):
    if arguments == [ "--self-test" ]:
        return run_self_test()
    if arguments != [ "--check" ]:
        print( __doc__ )
        return 2
    faults, report = find_faults( SPEC.read_text() )
    print( "\n".join( report ) )
    for fault in faults:
        print( f"FAULT                                        {fault}" )
    print( "verdict                                      " + ( "every needed module stands under exactly one phase" if not faults else f"{len( faults )} faults" ) )
    return 1 if faults else 0


if __name__ == "__main__":
    sys.exit( main( sys.argv[ 1: ] ) )
