#!/usr/bin/env python3
"""
c14_mcp_wait.py jetski|agy -- C14: how long may one MCP tool call block before the engine gives up?

A cosa-voice ask blocks until a human answers (the session sits in awaiting_human, framework §5.2). If the engine times
MCP calls out, sync asks need a different shape (return a ticket, poll, or deliver the answer as the next turn).
One engine process, one turn per duration; the probe server logs call start, call end, cancellation and EOF.

Requires:
    - the engine on PATH; MCP_CONFIG optional (default ~/.gemini/config/mcp_config.json, measured for both binaries)
    - WAITS optional: seconds per turn, default "45 200 620" (about 15 minutes in all)
Ensures:
    - the MCP config is backed up and restored on exit (removed if it did not exist)
    - out/c14-<bin>-<ts>/verdict.txt and facts.json
"""
import atexit, json, os, shutil, sys
from capture_lib import *

BIN    = sys.argv[ 1 ] if len( sys.argv ) > 1 else "jetski"
WAITS  = [ int( s ) for s in os.environ.get( "WAITS", "45 200 620" ).split() ]
CONFIG = Path( os.environ.get( "MCP_CONFIG", Path.home() / ".gemini" / "config" / "mcp_config.json" ) )
out = new_out( f"c14-{BIN}" )
report = Report( out, "c14" )
report.say( "version", version( BIN, out ) )

backup = out / "mcp_config.backup"
existed = CONFIG.exists()
if existed: shutil.copy( CONFIG, backup )
atexit.register( lambda: shutil.copy( backup, CONFIG ) if existed else CONFIG.unlink( missing_ok=True ) )
config = json.loads( CONFIG.read_text() ) if existed and CONFIG.stat().st_size else {}
log = out / "mcp.jsonl"
config.setdefault( "mcpServers", {} )[ "uhw-probe" ] = { "command": PY, "args": [ str( HERE / "probe_mcp.py" ) ],
                                                         "env": { "UHW_PROBE_MCP_LOG": str( log ) } }
CONFIG.parent.mkdir( parents=True, exist_ok=True ); CONFIG.write_text( json.dumps( config, indent=1 ) )

ws = workspace(); write_hooks( ws )
turns = [ f"Call the wait_seconds tool from the uhw-probe MCP server with seconds={s}, exactly once, then quote its output verbatim."
          for s in WAITS ]
summaries = drive( engine_argv( BIN ), ws, out / "frames.jsonl", turns, timeout=max( WAITS ) + 300, UHW_PROBE_LOG=out / "hook.jsonl" )

events = jsonl( log )
starts  = [ e for e in events if e.get( "phase" ) == "start" ]          # ids repeat across server restarts: match by
ends    = [ e for e in events if e.get( "phase" ) == "end" ]            # requested duration and order, never by id
cancels = [ e for e in events if e.get( "call" ) == "notification" ]
eof     = [ e for e in events if e.get( "phase" ) == "eof" ]
done_frames = [ r for r in jsonl( out / "frames.jsonl" ) if r[ "frame" ].get( "event" ) == "step_update"
                and r[ "frame" ][ "step_update" ].get( "step_type" ) == "tool" and r[ "frame" ][ "step_update" ].get( "state" ) != "ACTIVE" ]
rows, longest_ok = [], 0
for index, seconds in enumerate( WAITS ):
    summary = summaries[ index ] if index < len( summaries ) else {}
    start  = next( ( e for e in starts if e[ "seconds" ] == seconds ), None )
    end    = next( ( e for e in ends if start and e[ "seconds" ] == seconds and e[ "t" ] >= start[ "t" ] ), None )
    cancel = next( ( c for c in cancels if start and c[ "t" ] >= start[ "t" ] ), None )
    text  = reply_text( [ summary ] ) if summary else ""
    ok    = f"waited {seconds} seconds" in text or ( f"waited {seconds - 1} seconds" in text )
    longest_ok = max( longest_ok, seconds if ok else 0 )
    rows.append( { "seconds": seconds, "called": bool( start ), "server_finished": bool( end ),
                   "cancelled_after_s": round( cancel[ "t" ] - start[ "t" ], 1 ) if cancel and start else None,
                   "result_ok": ok, "status": statuses( [ summary ] ) if summary else [ "no turn" ],
                   "timeout": summary.get( "timeout" ), "reply": text[ :200 ] } )
    report.say( f"wait {seconds:>4} s", f"called={bool( start )} answered_in_reply={ok} cancelled_after={rows[ -1 ][ 'cancelled_after_s' ]} "
                                        f"status={rows[ -1 ][ 'status' ]} reply={text[ :60 ]!r}" )
report.fact( "rows", rows )
report.fact( "tool_done_frames", [ json.dumps( r[ "frame" ] )[ :400 ] for r in done_frames ] )
report.fact( "server_eof_after_s", round( eof[ 0 ][ "t" ] - events[ 0 ][ "t" ], 1 ) if eof and events else None )
report.say( "tool result frames (first, truncated)", report.facts[ "tool_done_frames" ][ :1 ] or "none" )
report.finish( f"longest call answered = {longest_ok} s of {max( WAITS )} s tried"
               + ( "" if longest_ok == max( WAITS ) else " (a timeout lies between the last success and the next try)" ) )
