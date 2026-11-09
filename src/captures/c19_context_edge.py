#!/usr/bin/env python3
"""
c19_context_edge.py jetski|agy [--leg a|b|ab] -- C19 (T23, D57): confirm the public record on context exhaustion on Rick's binaries.

    Research first (Rick's ruling, 2026-11-09): the Antigravity CLI auto-compacts at a fixed ~256,000-token ceiling for every
    model (Google staff, 11-04/06; antigravity-cli issues 878 and 1245), shows it as a `checkpoint` step in stream-json, and
    records `max_context_tokens` per request in its session database. This capture confirms that on the engine and models the
    kernel will run, and reads the one number the record does not give: the ceiling for the two Claude models under each engine.

    leg a  survey + table read   two short turns; which steps carry `usage`; whether `cache_read_tokens` sits beside
                                 `input_tokens`; whether `result.usage` is cumulative; then the session database's
                                 `max_context_tokens` for the model, when the database can be found.
    leg b  the edge              FILES files of ~40k tokens read one per turn until the ceiling; a recall probe last. Stops at
                                 the end of the turn list or when the process dies; the stop rules (checkpoint step, drop of
                                 more than half, error, flat occupancy) are applied in the analysis. Run the flash model first.

Requires:
    - the engine on PATH; MODEL pins --model (run once per D44 model); FILES overrides the fill count (default 9 → ~360k)
Ensures:
    - planted files only inside a throwaway workspace
    - out/c19-<bin>-<model>-<ts>/verdict.txt, facts.json, usage.tsv (one row per usage-bearing step)
    - no write to the engine's session database: it is opened read-only and copied first
"""
import glob, os, re, shutil, sqlite3, sys, time
from capture_lib import *

BIN   = sys.argv[ 1 ] if len( sys.argv ) > 1 and not sys.argv[ 1 ].startswith( "--" ) else "agy"
LEG   = "ab"
if "--leg" in sys.argv: LEG = sys.argv[ sys.argv.index( "--leg" ) + 1 ]
MODEL = os.environ.get( "MODEL", "default" )
FILES = int( os.environ.get( "FILES", "9" ) )
TOKENS_PER_FILE = 40_000

out = new_out( f"c19-{BIN}-{MODEL}" )
report, planter = Report( out, "c19" ), Planter()
report.say( "version", version( BIN, out ) )
report.say( "model", MODEL )


def fill_text( index, tokens=TOKENS_PER_FILE ):
    """Numbered lines of plain words; about 4 characters a token, so ~160 KB a file. Deterministic, so recall is checkable."""
    lines = []
    for n in range( tokens // 10 ):                                   # ~10 tokens a line
        lines.append( f"fill-{index:02d} line {n:05d} alpha bravo charlie delta echo" )
    return "\n".join( lines ) + "\n"


def usage_rows( frames_path ):
    """Every frame with a usage object, flattened: (t, turn, where, step_index, state, step_type, usage dict)."""
    rows = []
    for record in jsonl( frames_path ):
        frame, turn, t = record.get( "frame", {} ), record.get( "turn" ), record.get( "t" )
        event = frame.get( "event" )
        if event == "step_update":
            update = frame.get( "step_update", {} )
            if "usage" in update:
                rows.append( dict( t=t, turn=turn, where="step_update", step_index=update.get( "step_index" ),
                                   state=update.get( "state" ), step_type=update.get( "step_type" ),
                                   duration=update.get( "duration_seconds" ), usage=update[ "usage" ] ) )
        elif event == "result" and "usage" in frame.get( "result", {} ):
            rows.append( dict( t=t, turn=turn, where="result", step_index=None, state=None, step_type=None,
                               duration=frame[ "result" ].get( "duration_seconds" ), usage=frame[ "result" ][ "usage" ] ) )
    return rows


def occupancy( usage ):
    return int( usage.get( "input_tokens", 0 ) or 0 ) + int( usage.get( "cache_read_tokens", 0 ) or 0 )


def step_types( frames_path ):
    return sorted( { r.get( "frame", {} ).get( "step_update", {} ).get( "step_type" ) for r in jsonl( frames_path )
                     if r.get( "frame", {} ).get( "event" ) == "step_update" } - { None } )


def write_tsv( rows, path ):
    with open( path, "w" ) as handle:
        handle.write( "t\tturn\twhere\tstep_index\tstate\tstep_type\tinput\tcache_read\toutput\tthinking\ttotal\toccupancy\n" )
        for r in rows:
            u = r[ "usage" ]
            handle.write( "\t".join( str( x ) for x in ( r[ "t" ], r[ "turn" ], r[ "where" ], r[ "step_index" ], r[ "state" ],
                          r[ "step_type" ], u.get( "input_tokens" ), u.get( "cache_read_tokens" ), u.get( "output_tokens" ),
                          u.get( "thinking_tokens" ), u.get( "total_tokens" ), occupancy( u ) ) ) + "\n" )


def session_db_ceiling( conversation_id, started_after ):
    """Read max_context_tokens from the engine's own session database, read-only, from a copy. Returns (value, path) or (None, why)."""
    roots = [ os.path.expanduser( p ) for p in ( "~/.gemini/antigravity-cli/conversations", "~/.gemini/jetski/conversations",
                                                 "~/.gemini/antigravity-cli", "~/.gemini/jetski", "~/.gemini" ) ]
    candidates = []
    for root in roots:
        candidates += glob.glob( os.path.join( root, "**", "*.db" ), recursive=True )
    candidates = [ c for c in dict.fromkeys( candidates ) if os.path.getmtime( c ) >= started_after - 5 ]
    if conversation_id:
        named = [ c for c in candidates if conversation_id in os.path.basename( c ) ]
        candidates = named or candidates
    if not candidates:
        return None, "no session database newer than this run under ~/.gemini"
    db = max( candidates, key=os.path.getmtime )
    copy = out / "session-db-copy.db"
    shutil.copy2( db, copy )
    try:
        con = sqlite3.connect( f"file:{copy}?mode=ro", uri=True )
        values = set()
        for ( table, ) in con.execute( "select name from sqlite_master where type='table'" ):
            columns = [ c[ 1 ] for c in con.execute( f'pragma table_info("{table}")' ) ]
            for column in columns:
                if "context" in column.lower() or "max_context" in column.lower():
                    for ( v, ) in con.execute( f'select distinct "{column}" from "{table}" where "{column}" is not null limit 20' ):
                        if isinstance( v, int ): values.add( v )
            # protobuf blobs: scan for the literal field name and a nearby varint is not reliable; record the table names instead
        con.close()
        if values:
            return max( values ), db
        return None, f"{db}: no integer context column found; tables listed in facts.json"
    except Exception as problem:
        return None, f"{db}: {type( problem ).__name__}: {problem}"


# ----------------------------------------------------------------------------------------------------------------------- leg a
if "a" in LEG:
    ws = workspace()
    planter.plant( ws / "fill-00.txt", fill_text( 0, 30_000 ) )
    frames = out / "a-frames.jsonl"
    started = time.time()
    summaries = drive( engine_argv( BIN ), ws, frames, [
        "Say hi in one word.",
        "Read the whole of fill-00.txt with your file-reading tool (keep reading until its last line if your tool reads only part), then say hi in one word." ],
        timeout=600 )
    rows = usage_rows( frames )
    write_tsv( rows, out / "a-usage.tsv" )
    report.fact( "a_usage_rows", rows )
    report.fact( "a_step_types", step_types( frames ) )
    carriers = sorted( { f"{r['where']}:{r['step_type']}:{r['state']}" for r in rows } )
    report.say( "usage carried on", ", ".join( carriers ) or "no usage anywhere" )
    results = [ r for r in rows if r[ "where" ] == "result" ]
    steps   = [ r for r in rows if r[ "where" ] == "step_update" and r[ "step_type" ] == "agent_response" and r[ "state" ] == "DONE" ]
    if len( results ) >= 2:
        t1, t2 = results[ 0 ][ "usage" ].get( "total_tokens", 0 ), results[ 1 ][ "usage" ].get( "total_tokens", 0 )
        report.say( "result.usage cumulative", f"{'yes' if t2 > t1 * 1.5 else 'no'} (turn 1 total {t1}, turn 2 total {t2})" )
    turn1 = [ r for r in steps if r[ "turn" ] == 0 ]
    turn2 = [ r for r in steps if r[ "turn" ] == 1 ]
    if turn1 and turn2:
        o1, o2 = occupancy( turn1[ -1 ][ "usage" ] ), occupancy( turn2[ -1 ][ "usage" ] )
        i2, c2 = turn2[ -1 ][ "usage" ].get( "input_tokens", 0 ), turn2[ -1 ][ "usage" ].get( "cache_read_tokens", 0 )
        expected = o1 + 30_000
        beside = abs( ( i2 + c2 ) - expected ) < abs( i2 - expected )
        report.say( "cache_read beside input", f"{'yes' if beside else 'no'} (turn 1 occupancy {o1}; turn 2 input {i2} + cache_read {c2}; file ≈30k)" )
        report.say( "occupancy field", "agent_response DONE: input_tokens + cache_read_tokens" if beside else "agent_response DONE: input_tokens" )
    else:
        report.say( "occupancy field", "agent_response DONE step without usage; see a-usage.tsv" )
    conversation = next( ( r.get( "session" ) for s in summaries for r in s.get( "results", [] ) if r.get( "session" ) ), None )
    ceiling, where = session_db_ceiling( conversation, started )
    report.say( "db max_context_tokens", f"{ceiling} ({where})" if ceiling else f"not read: {where}" )
    report.fact( "a_summaries", summaries )

# ----------------------------------------------------------------------------------------------------------------------- leg b
if "b" in LEG:
    ws = workspace()
    for n in range( FILES ):
        planter.plant( ws / f"fill-{n:02d}.txt", fill_text( n ) )
    turns = [ f"Read the whole of fill-{n:02d}.txt with your file-reading tool (keep reading until its last line if your tool reads only part). Reply with only its first line, nothing else."
              for n in range( FILES ) ]
    turns.append( "Without reading any file now: what was the first line of fill-00.txt? Reply with only that line." )
    frames = out / "b-frames.jsonl"
    summaries = drive( engine_argv( BIN ), ws, frames, turns, timeout=900 )
    rows = usage_rows( frames )
    write_tsv( rows, out / "b-usage.tsv" )
    report.fact( "b_usage_rows", rows )
    report.fact( "b_step_types", step_types( frames ) )
    report.fact( "b_summaries", summaries )
    steps = [ r for r in rows if r[ "where" ] == "step_update" and r[ "step_type" ] == "agent_response" and r[ "state" ] == "DONE" ]
    checkpoints = [ r for r in jsonl( frames ) if r.get( "frame", {} ).get( "step_update", {} ).get( "step_type" ) == "checkpoint" ]
    series = [ ( r[ "turn" ], occupancy( r[ "usage" ] ) ) for r in steps ]
    report.fact( "b_occupancy_series", series )
    behaviour, before, after, stall = "none below ceiling", None, None, None
    if checkpoints:
        first = checkpoints[ 0 ]
        prior = [ o for ( t, o ) in series if t <= first.get( "turn", 0 ) and o ]
        before = max( prior ) if prior else None
        later  = [ o for ( t, o ) in series if t > first.get( "turn", 0 ) ]
        after  = later[ 0 ] if later else None
        stall  = first[ "frame" ][ "step_update" ].get( "duration_seconds" )
        behaviour = "checkpoint"
        report.fact( "b_first_checkpoint", first )
    else:
        for ( t1, o1 ), ( t2, o2 ) in zip( series, series[ 1: ] ):
            if o1 and o2 < o1 * 0.5:
                behaviour, before, after = "silent drop", o1, o2
                break
        statuses_seen = statuses( summaries )
        if behaviour == "none below ceiling" and any( s not in ( "success", None ) for s in statuses_seen ):
            behaviour = f"errored ({[ s for s in statuses_seen if s not in ( 'success', None ) ][ 0 ]})"
        if behaviour == "none below ceiling" and len( summaries ) < len( turns ):
            behaviour = "exited before the turn list ended"
        if behaviour == "none below ceiling" and len( series ) >= 4:
            tail = [ o for _, o in series[ -4: ] ]
            if max( tail ) - min( tail ) < TOKENS_PER_FILE // 2:
                behaviour, before = "truncated (occupancy flat while files kept being read)", max( tail )
    recall = reply_text( summaries[ -1: ] ) if summaries else ""
    report.say( "behaviour at the edge", behaviour )
    report.say( "edge tokens before / after", f"{before} / {after}" )
    report.say( "stall seconds", stall )
    report.say( "max occupancy seen", max( ( o for _, o in series ), default=None ) )
    report.say( "recall after edge", "intact" if "fill-00 line 00000" in recall else f"lost ({recall[ :80 ]!r})" )
    report.say( "turns driven / files", f"{len( summaries )} / {FILES}" )

planter.cleanup()
report.finish( "see the lines above; db max_context_tokens or edge tokens before → [context windows] ceiling_tokens for this model" )
