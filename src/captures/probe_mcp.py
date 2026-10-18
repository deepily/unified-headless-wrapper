#!/usr/bin/env python3
"""
probe_mcp.py -- dependency-free stdio MCP server for capture C3 (does identity reach MCP servers?).

Requires:
    - launched by an engine as a stdio MCP server (newline-delimited JSON-RPC 2.0)
Ensures:
    - on startup appends { t, pid, ppid, cwd, env subset } to UHW_PROBE_MCP_LOG (default /tmp/uhw-mcp-probe.jsonl),
      so the capture works even if the model never calls the tool
    - exposes whoami, returning the same record as text
    - exposes wait_seconds{seconds} (C14): sleeps on its own thread, then answers; the main loop keeps reading, so
      call start, call end, engine cancellation (notifications/cancelled) and stdin EOF are all logged with times
"""
import json, os, sys, threading, time

NAMES    = { "UHW_PROBE_TAG", "UHW_PROBE_BLOCK", "UHW_PROBE_EXPANDED",      # exact names only: a prefix match once
             "LUPIN_PERSONA_ID", "CLAUDE_SESSION_ID", "CLAUDE_PROJECT_DIR", "PWD" }   # logged LUPIN_DEV_PASSWORD (2026-10-15)
IDENTITY = { "t": time.time(), "pid": os.getpid(), "ppid": os.getppid(), "cwd": os.getcwd(),
             "env": { k: v for k, v in os.environ.items() if k in NAMES } }
LOG      = os.environ.get( "UHW_PROBE_MCP_LOG", "/tmp/uhw-mcp-probe.jsonl" )
LOCK     = threading.Lock()


def note( record ):
    with LOCK, open( LOG, "a" ) as log:
        log.write( json.dumps( record ) + "\n" )


note( IDENTITY )

WHOAMI = { "name": "whoami", "description": "Report the identity this MCP server process was started with.",
           "inputSchema": { "type": "object", "properties": {} } }
WAIT   = { "name": "wait_seconds", "description": "Wait the given number of seconds, then report how long it waited.",
           "inputSchema": { "type": "object", "properties": { "seconds": { "type": "number" } }, "required": [ "seconds" ] } }


def reply( message ):
    with LOCK:
        sys.stdout.write( json.dumps( message ) + "\n" ); sys.stdout.flush()


def wait_then_answer( request_id, seconds ):
    started = time.time()
    note( { "call": "wait_seconds", "phase": "start", "id": request_id, "seconds": seconds, "t": started } )
    time.sleep( seconds )
    note( { "call": "wait_seconds", "phase": "end", "id": request_id, "seconds": seconds, "t": time.time() } )
    try:
        reply( { "jsonrpc": "2.0", "id": request_id,
                 "result": { "content": [ { "type": "text", "text": f"waited {round( time.time() - started )} seconds" } ] } } )
    except ( BrokenPipeError, OSError ):
        note( { "call": "wait_seconds", "phase": "reply_failed", "id": request_id, "t": time.time() } )


def answer( request ):
    method, params = request.get( "method" ), request.get( "params" ) or {}
    if method == "initialize":
        return { "protocolVersion": params.get( "protocolVersion", "2025-06-18" ),
                 "capabilities": { "tools": {} }, "serverInfo": { "name": "uhw-probe", "version": "0.1" } }
    if method == "tools/list":
        return { "tools": [ WHOAMI, WAIT ] }
    if method == "tools/call" and params.get( "name" ) == "whoami":
        return { "content": [ { "type": "text", "text": json.dumps( IDENTITY ) } ] }
    if method == "ping":
        return {}
    raise LookupError( method )


for line in sys.stdin:
    try: request = json.loads( line )
    except ValueError: continue
    if "id" not in request:                                        # notifications need no reply; cancellations are C14 data
        if "cancel" in str( request.get( "method" ) ):
            note( { "call": "notification", "method": request.get( "method" ), "params": request.get( "params" ), "t": time.time() } )
        continue
    params = request.get( "params" ) or {}
    if request.get( "method" ) == "tools/call" and params.get( "name" ) == "wait_seconds":
        seconds = float( ( params.get( "arguments" ) or {} ).get( "seconds", 0 ) )
        threading.Thread( target=wait_then_answer, args=( request[ "id" ], seconds ), daemon=True ).start()
        continue
    try:
        reply( { "jsonrpc": "2.0", "id": request[ "id" ], "result": answer( request ) } )
    except LookupError as missing:
        reply( { "jsonrpc": "2.0", "id": request[ "id" ], "error": { "code": -32601, "message": f"no method {missing}" } } )
note( { "call": "stdin", "phase": "eof", "t": time.time() } )
