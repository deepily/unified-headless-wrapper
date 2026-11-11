#!/usr/bin/env python3
"""
c9_c10_pyramid_probe.py -- before the harness exists: how often does a model follow the response-pyramid format (C9),
and how long after the spoken lines close does the result frame arrive (C10)?

    c9_c10_pyramid_probe.py --family jetski [--repeat 3] -- jetski --input-format stream-json --output-format stream-json --dangerously-skip-permissions
    c9_c10_pyramid_probe.py --family claude [--repeat 3] -- claude -p --input-format stream-json --output-format stream-json \
        --verbose --include-partial-messages --setting-sources project,local --strict-mcp-config --dangerously-skip-permissions

Requires:
    - drive.py beside this file; for Claude, capture C5 has passed (the flags above keep AH4L hooks out)
Ensures:
    - one fresh conversation per prompt per repeat; rules go in --append-system-prompt (Claude) or the first message (Jetski)
    - out/pyramid-<family>-<ts>/results.tsv: prompt, needs_repair, spoken line count, abstract?, document?, timings
    - prints the compliance rate and the median gap from spoken-block close to result
"""
import argparse, json, os, re, statistics, subprocess, sys, tempfile, time
from pathlib import Path

RULES = """You are speaking to one person through a voice interface. Write your final reply in this exact shape:
Line 1: a one-sentence headline that answers the request.
Lines 2 and 3: at most two short supporting sentences in plain words, with no markdown, lists, links or code.
If there is detail worth showing, add a line containing only <<<abstract, then that detail in markdown.
Only if the person asked for a document, or the detail is too long for a card, add a line containing only
<<<document persistent (if they asked for it) or <<<document transient, then the full markdown.
Most replies need only the first lines."""

RULES_V2 = """You are speaking to one person through a voice interface. Write your final reply in this exact shape:
Line 1: one sentence that answers the request. One line is enough when one line answers.
At most two more lines, only if they add something the listener needs. One sentence per line,
plain words, no markdown, lists, links or code.     # shape only: length is handled by Lupin's rewriter and KISS
If there is detail worth showing, add a line containing only <<<abstract, then that detail in markdown.
Only if the person asked for a document, or the detail is too long for a card, add a line containing only
<<<document persistent (if they asked for it) or <<<document transient, then the full markdown."""
if os.environ.get( "UHW_RULES", "v1" ) == "v2":      # v1 stays the default so earlier runs remain comparable
    RULES = RULES_V2

PROMPTS = [ "Say hello.",
            "What is the capital of Australia?",
            "Compare TCP and UDP in a table.",
            "List the files in this directory and say what each one is.",
            "Explain how a hash map works.",
            "Write me a short document with a plan to back up a laptop. I want it as a document.",
            "Give me five tips for better sleep.",
            "Thanks, that's all." ]

SPOKEN_LINE_LIMIT = 3
SECTION_MARKER    = re.compile( r"^<<<(abstract|document(?: (?:transient|persistent))?)\s*$", re.MULTILINE )
MARKDOWN          = re.compile( r"[*_`#>|]+|\[([^\]]+)\]\([^)]*\)" )


def parse_pyramid( text ):
    """
    Requires:
        - text is the final assistant message of a turn
    Ensures:
        - returns ( spoken lines, abstract or None, document or None ); never raises
    """
    head, *sections = SECTION_MARKER.split( text )
    spoken = [ MARKDOWN.sub( r"\1", line ).strip() for line in head.splitlines() if line.strip() ]
    abstract = document = None
    for tag, body in zip( sections[ 0::2 ], sections[ 1::2 ] ):
        if tag == "abstract": abstract = body.strip()
        else:                 document = body.strip()
    return spoken, abstract, document


def needs_repair( spoken ):
    return not ( 1 <= len( spoken ) <= SPOKEN_LINE_LIMIT )


def delta_text( family, frame ):
    if family == "jetski":
        return frame.get( "step_update", {} ).get( "text_delta", "" ) if frame.get( "event" ) == "step_update" else ""
    delta = frame.get( "event", {} ).get( "delta", {} ) if frame.get( "type" ) == "stream_event" else {}
    return delta.get( "text", "" ) if delta.get( "type" ) == "text_delta" else ""


parser = argparse.ArgumentParser()
parser.add_argument( "--family", choices=[ "jetski", "claude" ], required=True )
parser.add_argument( "--repeat", type=int, default=1 )
parser.add_argument( "engine", nargs=argparse.REMAINDER )
arguments = parser.parse_args()
engine = arguments.engine[ 1: ] if arguments.engine[ :1 ] == [ "--" ] else arguments.engine
if arguments.family == "claude":
    engine = engine + [ "--append-system-prompt", RULES ]

here = Path( __file__ ).resolve().parent
label = os.environ.get( "UHW_LABEL", arguments.family )                # run_engine.sh sets it to agy or jetski
out  = here / "out" / f"pyramid-{label}-{time.strftime( '%Y%m%dT%H%M%S' )}"
out.mkdir( parents=True )
workspace = Path( tempfile.mkdtemp() )
( workspace / "notes.txt" ).write_text( "meeting notes\n" ); ( workspace / "budget.csv" ).write_text( "item,usd\n" )
rows = [ "prompt\trepeat\tneeds_repair\tspoken_lines\tabstract\tdocument\tt_first_delta\tt_spoken_closed\tt_result\tgap_s" ]
repairs, gaps = 0, []

for repeat in range( arguments.repeat ):
    for number, prompt in enumerate( PROMPTS ):
        frames_path = out / f"frames-{number}-{repeat}.jsonl"
        turn = prompt if arguments.family == "claude" else f"{RULES}\n\n{prompt}"
        subprocess.run( [ sys.executable, str( here / "drive.py" ), "--family", arguments.family, "--cwd", str( workspace ),
                          "--out", str( frames_path ), "--turn", turn, "--", *engine ], stdout=subprocess.DEVNULL )
        text, first, closed, final, t_result = "", None, None, "", None
        for line in frames_path.read_text().splitlines():
            record = json.loads( line )
            frame, now = record[ "frame" ], record[ "t" ]
            piece = delta_text( arguments.family, frame )
            if piece:
                first = first or now
                text += piece
                closed = closed or ( now if "\n<<<" in text else None )
            if frame.get( "event" ) == "result" or frame.get( "type" ) == "result":
                result = frame.get( "result", {} )
                final = ( result.get( "response" ) if isinstance( result, dict ) else result ) or ""
                t_result = now
        spoken, abstract, document = parse_pyramid( final )
        repair = needs_repair( spoken )
        repairs += repair
        closed = closed or t_result
        gap = round( t_result - closed, 2 ) if t_result and closed else None
        if gap is not None: gaps.append( gap )
        with open( out / "spoken.txt", "a" ) as said:
            said.write( f"[{number}-{repeat}] " + " | ".join( spoken ) + "\n" )
        rows.append( "\t".join( map( str, [ number, repeat, repair, len( spoken ), abstract is not None, document is not None,
                                            first, closed, t_result, gap ] ) ) )
        print( rows[ -1 ], flush=True )

( out / "results.tsv" ).write_text( "\n".join( rows ) + "\n" )
total = len( PROMPTS ) * arguments.repeat
print( f"C9 compliance ({os.environ.get( 'UHW_RULES', 'v1' )} rules): {total - repairs}/{total} well formed" )
print( f"C10 median gap spoken-close -> result: {statistics.median( gaps ) if gaps else 'n/a'} s   (results: {out})" )
