#!/usr/bin/env python3
"""
drive.py -- send turns to one stream-json engine process, record every frame, summarize each turn.

    drive.py --family jetski|claude --out run.jsonl --turn "first prompt" [--turn "second" ...]
             [--cwd DIR] [--interrupt-after-deltas N] [--inject-on-tool TEXT] [--linger SECONDS]
             -- <engine argv ...>

Requires:
    - the engine speaks stream-json on stdin and stdout (Jetski/AGY or Claude Code)
Ensures:
    - every stdout frame is appended to --out as {"t": seconds_since_spawn, "turn": i, "frame": {...}}
    - stderr is saved to <out>.stderr
    - one JSON summary line per turn is printed to stdout
    - the engine's process group is reaped on exit, whatever happens
"""
import argparse, json, os, signal, subprocess, sys, threading, time, queue

parser = argparse.ArgumentParser()
parser.add_argument( "--family", choices=[ "jetski", "claude" ], required=True )
parser.add_argument( "--out", required=True )
parser.add_argument( "--turn", action="append", default=[] )
parser.add_argument( "--cwd" )
parser.add_argument( "--interrupt-after-deltas", type=int, default=0 )
parser.add_argument( "--inject-on-tool" )
parser.add_argument( "--linger", type=float, default=0.0 )
parser.add_argument( "--turn-timeout", type=float, default=600.0 )
parser.add_argument( "engine", nargs=argparse.REMAINDER )
arguments = parser.parse_args()
engine_argv = arguments.engine[ 1: ] if arguments.engine[ :1 ] == [ "--" ] else arguments.engine


def user_frame( text ):
    if arguments.family == "jetski":
        return { "event": "user", "message": { "role": "user", "content": text } }
    return { "type": "user", "message": { "role": "user", "content": text } }


def classify( frame ):
    """Return ( kind, value ) for the frames this driver reacts to: delta, tool, result, session."""
    if arguments.family == "jetski":
        event = frame.get( "event" )
        if event == "init":
            return "session", frame.get( "conversation_id" )
        if event == "step_update":
            update = frame.get( "step_update", {} )
            if update.get( "step_type" ) == "tool" and update.get( "state" ) == "ACTIVE":
                return "tool", update.get( "tool_name" )
            if update.get( "text_delta" ):
                return "delta", update[ "text_delta" ]
        if event == "result":
            return "result", frame.get( "result", {} )
        return None, None
    kind = frame.get( "type" )
    if kind == "system" and frame.get( "subtype" ) == "init":
        return "session", frame.get( "session_id" )
    if kind == "stream_event":
        delta = frame.get( "event", {} ).get( "delta", {} )
        if delta.get( "type" ) == "text_delta":
            return "delta", delta.get( "text", "" )
    if kind == "assistant":
        for block in frame.get( "message", {} ).get( "content", [] ):
            if block.get( "type" ) == "tool_use":
                return "tool", block.get( "name" )
    if kind == "result":
        return "result", frame
    return None, None


def result_summary( result ):
    if arguments.family == "jetski":
        return { "status": result.get( "status" ), "error": result.get( "error" ),
                 "session": result.get( "conversation_id" ), "text": ( result.get( "response" ) or "" )[ :400 ] }
    return { "status": result.get( "subtype" ), "is_error": result.get( "is_error" ),
             "session": result.get( "session_id" ), "text": ( result.get( "result" ) or "" )[ :400 ] }


started = time.monotonic()
process = subprocess.Popen( engine_argv, cwd=arguments.cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=open( arguments.out + ".stderr", "wb" ), start_new_session=True )
frames = queue.Queue()


def pump():
    for line in process.stdout:
        frames.put( line )
    frames.put( None )


threading.Thread( target=pump, daemon=True ).start()
record = open( arguments.out, "a" )


def send( frame ):
    try:
        process.stdin.write( ( json.dumps( frame ) + "\n" ).encode() )
        process.stdin.flush()
    except ( BrokenPipeError, OSError ):
        pass


def interrupt( request_number ):
    if arguments.family == "claude":
        send( { "type": "control_request", "request_id": f"capture-{request_number}", "request": { "subtype": "interrupt" } } )
    else:
        try: os.killpg( process.pid, signal.SIGINT )
        except ProcessLookupError: pass


def run_turn( index, text ):
    summary = { "turn": index, "pid": process.pid, "deltas": 0, "tools": [], "results": [], "session": None,
                "t_sent": round( time.monotonic() - started, 2 ), "t_first_delta": None, "interrupted_by_driver": False,
                "injected_at": None }
    send( user_frame( text ) )
    deadline, linger_until = time.monotonic() + arguments.turn_timeout, None
    while True:
        now = time.monotonic()
        if linger_until and now >= linger_until:
            break
        try:
            line = frames.get( timeout=max( 0.1, min( deadline, linger_until or deadline ) - now ) )
        except queue.Empty:
            if linger_until: break
            summary[ "timeout" ] = True
            break
        if line is None:
            summary[ "eof" ] = True
            break
        elapsed = round( time.monotonic() - started, 3 )
        try: frame = json.loads( line )
        except ValueError: continue
        record.write( json.dumps( { "t": elapsed, "turn": index, "frame": frame } ) + "\n" ); record.flush()
        kind, value = classify( frame )
        if kind == "session" and value:
            summary[ "session" ] = value
        elif kind == "delta":
            summary[ "deltas" ] += 1
            summary[ "t_first_delta" ] = summary[ "t_first_delta" ] or elapsed
            if index == 0 and arguments.interrupt_after_deltas and summary[ "deltas" ] == arguments.interrupt_after_deltas:
                summary[ "interrupted_by_driver" ] = True
                interrupt( index )
        elif kind == "tool":
            summary[ "tools" ].append( value )
            if index == 0 and arguments.inject_on_tool and summary[ "injected_at" ] is None:
                summary[ "injected_at" ] = elapsed
                send( user_frame( arguments.inject_on_tool ) )
        elif kind == "result":
            summary[ "results" ].append( { "t": elapsed, **result_summary( value ) } )
            summary[ "session" ] = summary[ "results" ][ -1 ][ "session" ] or summary[ "session" ]
            if arguments.linger and index == 0:
                linger_until = linger_until or time.monotonic() + arguments.linger
            else:
                break
    summary[ "alive_after" ] = process.poll() is None
    print( json.dumps( summary ), flush=True )
    return summary


try:
    for number, prompt in enumerate( arguments.turn ):
        if process.poll() is not None:
            print( json.dumps( { "turn": number, "skipped": "engine exited", "returncode": process.returncode } ), flush=True )
            break
        run_turn( number, prompt )
finally:
    try: process.stdin.close()
    except OSError: pass
    try: process.wait( timeout=10 )
    except subprocess.TimeoutExpired:
        try: os.killpg( process.pid, signal.SIGKILL )
        except ProcessLookupError: pass
        process.wait()
    print( json.dumps( { "returncode": process.returncode } ), flush=True )
