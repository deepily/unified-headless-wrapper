#!/usr/bin/env bash
# t19_acceptance_phase_check.sh — does every acceptance test stand in the same phase in the
# three places that state one? (row 63 of "Outstanding actions": the T17 log spec runs Log-4
# with Kernel-1 and Log-5 with Kernel-5; the framework's Section 15 table, written by D63,
# exit criteria and the switch-over, places Log-4 to Log-6 in Phase 2.)
#
#   t19_acceptance_phase_check.sh [checkout]        checkout defaults to this script's repository
#   t19_acceptance_phase_check.sh --check [checkout]  exit 1 while any test reads `conflict`
#
# The three places, read from the checkout and nowhere else:
#
#   (a) the owning spec   each spec's acceptance table, the cell under the column headed
#                         Phase, Runs with, Folded into, Folds into, Lands with, Where it lands
#                         or Gate; `no column` where the table has none (row 29 of the list)
#   (b) the Phase 1 spec  Section 12 and the amendments after it: the Kernel-N row or sentence
#                         that names the test
#   (c) the framework     Section 15's table: the stage row that names the test, with the
#                         qualifier that follows it there (`with Kernel-1`, `at Delete`)
#
# One line per test: `id | spec cell | Phase 1 spec | framework stage | verdict`. Verdicts:
#   agree       (a) and (c) name the same stage
#   conflict    (a) and (c) name different stages
#   split       (a) and (c) share a stage and one of them names another as well (a kernel side
#               and a Lupin side; a negative case on one engine and a positive on the other)
#   unplaced    (a) says `after Kernel-8` or another word this script maps to no stage
#   no column   (a) states no phase; (b) and (c) are printed for the reader
#   not named   (c) does not name the test at all
#
# Read-only, zero tokens, under a second. Output is meant for
# src/captures/out/t19-acceptance-phase-check-<host>-<date>.txt.

set -u
check=0
if [ "${1:-}" = "--check" ]; then check=1; shift; fi
here="$(cd "$(dirname "$0")" && pwd)"
checkout="${1:-$here/../..}"
checkout="$(cd "$checkout" && pwd)" || exit 2

CHECK="$check" python3 - "$checkout" <<'PYTHON'
import glob, os, re, sys

root      = sys.argv[ 1 ]
base      = os.path.join( root, "src/rnd/v0.0.1" )
framework = os.path.join( base, "01-framework.md" )
phase_one = os.path.join( base, "specs/2026.10.24-phase1-kernel-and-jetski-family-adapter-spec.md" )

COLUMN  = re.compile( r"^(phase|runs with|folded into|folds into|lands with|where it lands|gate)$", re.I )
TEST_ID = re.compile( r"^\**`?([A-Z][A-Za-z]+)-(\d+)`?\**$" )
SKIP    = { "Kernel", "SHA", "UTF", "Fable", "VETO", "Phase" }

def cells( line ):
    return [ c.strip() for c in line.strip().strip( "|" ).split( "|" ) ]

def stages_of( text ):
    """The stages a phrase names, as a sorted list; empty when the phrase maps to none."""
    found = set()
    t = re.sub( r"Phase \d does not run it[^)]*", "", text )
    stated = sorted( set( re.findall( r"Phase \d", t ) ) )
    if stated and not re.search( r"Switch|Delete|Move", t ): return stated    # a phase said outright wins
    if re.search( r"after Kernel-8", t ):
        t = t.replace( "after Kernel-8", "" )
        found.add( "after Kernel-8" )
    if re.search( r"Kernel-[1-8]\b|Phase 1\b|before the build|before Kernel-", t ):          found.add( "Phase 1" )
    if re.search( r"Phase 2|the move|Move clock|the Move|Fleet phase|Lupin phase|ticket store|crew layer|Lupin side|Lupin change|Switch-[123]\b", t ): found.add( "Phase 2" )
    if re.search( r"Claude phase|Phase 3|`claude` adapter|Claude adapter", t ):               found.add( "Phase 3" )
    if re.search( r"Phase 4|Switch-4\b", t ):                                                  found.add( "Phase 4" )
    if re.search( r"G1\.5", t ):                                                               found.add( "Gate G1.5" )
    if re.search( r"\bG2\b|Switch-5\b", t ):                                                   found.add( "Gate G2" )
    if re.search( r"Switch-over|Delete|Switch-6\b|the Switch\b", t ):                          found.add( "Switch-over" )
    return sorted( found )

# (a) every spec's acceptance tables -------------------------------------------------------
spec_cell = {}    # id -> ( file, line, cell or None )
order     = []
for path in sorted( glob.glob( os.path.join( base, "specs/*.md" ) ) ):
    lines = open( path, encoding="utf-8" ).read().split( "\n" )
    for i, line in enumerate( lines ):
        if not line.startswith( "|" ): continue
        row = cells( line )
        m = TEST_ID.match( row[ 0 ] )
        if not m or m.group( 1 ) in SKIP: continue
        j = i
        while j > 0 and lines[ j - 1 ].startswith( "|" ): j -= 1
        header = cells( lines[ j ] )
        column = next( ( k for k, h in enumerate( header ) if COLUMN.match( h ) ), None )
        test = "%s-%s" % ( m.group( 1 ), m.group( 2 ) )
        if column is None:                  value = None
        elif column == len( header ) - 1:   value = row[ -1 ]     # a `|` inside a code span splits a cell
        elif column < len( row ):           value = row[ column ]
        else:                               value = None
        if test not in spec_cell: order.append( test )
        spec_cell[ test ] = ( os.path.basename( path ), i + 1, value )   # the last table wins
families = sorted( { t.split( "-" )[ 0 ] for t in spec_cell } )
FAMILY   = "|".join( families )

def expand( text ):
    """Every test a passage names: `Log-1 to 3`, `Fleet-1, 2, 10`, `Grant-1 to Grant-9`,
    `Interrupt-1, 2 and 4`. Yields ( id, end offset of the group )."""
    for m in re.finditer( r"\b(%s)[- ](\d+)((?:\s*(?:,|and|to|,\s*and)\s*(?:\1-)?\d+\b(?!-))*)" % FAMILY, text ):
        family, numbers = m.group( 1 ), [ int( m.group( 2 ) ) ]
        for joiner, number in re.findall( r"(,\s*and|,|and|to)\s*(?:%s-)?(\d+)" % family, m.group( 3 ) ):
            number = int( number )
            if joiner == "to": numbers.extend( range( numbers[ -1 ] + 1, number + 1 ) )
            else:              numbers.append( number )
        for number in numbers:
            yield "%s-%d" % ( family, number ), m.end()

# (b) the Phase 1 spec, Section 12 and the amendments after it -------------------------------
phase_one_names = {}
lines   = open( phase_one, encoding="utf-8" ).read().split( "\n" )
inside  = False
for line in lines:
    if line.startswith( "## " ):
        inside = line.startswith( "## 12." ) or line.startswith( "## Amend" )
        continue
    if not inside: continue
    row_gate = re.match( r"\|\s*\**(Kernel-\d)\b", line )
    for sentence in ( [ line ] if row_gate else re.split( r"(?<=[.;])\s+", line ) ):
        gates = re.findall( r"Kernel-\d\b", sentence )
        for test, end in expand( sentence ):
            if row_gate: where = row_gate.group( 1 )
            else:
                after = re.search( r"Kernel-\d\b", sentence[ end: ] )
                where = after.group( 0 ) if after else ( gates[ 0 ] if gates else "named, no gate" )
            phase_one_names.setdefault( test, [] )
            if where not in phase_one_names[ test ]: phase_one_names[ test ].append( where )

# (c) the framework's Section 15 table --------------------------------------------------------
framework_stage = {}   # id -> [ ( stage row, qualifier ) ]
lines  = open( framework, encoding="utf-8" ).read().split( "\n" )
inside = False
for line in lines:
    if line.startswith( "## " ): inside = line.startswith( "## 15." ); continue
    if not inside or not line.startswith( "|" ): continue
    row = cells( line )
    stage_row = re.match( r"(Phase \d|Gate G[\d.]+|Switch-over)", row[ 0 ] )   # "Gate G2, parity" is Gate G2 (row 85)
    if not stage_row: continue
    text = row[ 1 ]
    for test, end in expand( text ):
        tail = text[ end: end + 60 ]
        q = re.match( r"\s*(?:\w+ )?((?:runs? with|with|at|as a capture before) [^,;()]*)", tail )
        qualifier = q.group( 1 ).strip() if q else ""
        framework_stage.setdefault( test, [] ).append( ( stage_row.group( 1 ), qualifier ) )

# the comparison -----------------------------------------------------------------------------
print( "checkout %s" % root )
print( "families %d  tests %d" % ( len( families ), len( order ) ) )
print( "id | spec cell | Phase 1 spec | framework Section 15 | verdict" )
counts = {}
by_family = {}
for test in order:
    spec_file, spec_line, value = spec_cell[ test ]
    named = framework_stage.get( test, [] )
    stage_text = "; ".join( "%s%s" % ( s, " (%s)" % q if q else "" ) for s, q in named ) or "—"
    framework_set = set()
    for stage, qualifier in named:
        from_qualifier = [ s for s in stages_of( qualifier ) if s != "after Kernel-8" ]
        framework_set.update( from_qualifier or [ stage ] )
    if value is None:            verdict = "no column"
    elif not named:              verdict = "not named"
    else:
        spec_set = set( stages_of( value ) )
        if not spec_set or spec_set == { "after Kernel-8" }: verdict = "unplaced"
        elif spec_set == framework_set:                       verdict = "agree"
        elif spec_set & framework_set:                        verdict = "split"
        else:                                                 verdict = "conflict"
    counts[ verdict ] = counts.get( verdict, 0 ) + 1
    by_family.setdefault( test.split( "-" )[ 0 ], {} ).setdefault( verdict, [] ).append( test )
    print( "%s | %s | %s | %s | %s" % ( test, value if value is not None else "(no column)",
        ", ".join( phase_one_names.get( test, [] ) ) or "—", stage_text, verdict ) )

print()
print( "summary " + "  ".join( "%s %d" % ( k, counts[ k ] ) for k in sorted( counts ) ) )
for family in families:
    parts = [ "%s %s" % ( v, ",".join( t.split( "-" )[ 1 ] for t in ts ) ) for v, ts in sorted( by_family[ family ].items() ) if v != "agree" ]
    if parts: print( "family %s: %s" % ( family, "; ".join( parts ) ) )
named_only = sorted( t for t in framework_stage if t not in spec_cell )
if named_only: print( "named in Section 15 with no acceptance row in any spec: " + ", ".join( named_only ) )
if os.environ.get( "CHECK" ) == "1" and counts.get( "conflict" ): sys.exit( 1 )
PYTHON
