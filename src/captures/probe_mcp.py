#!/usr/bin/env python3
"""
probe_mcp.py -- dependency-free stdio MCP server for capture C3 (does identity reach MCP servers?).

Requires:
    - launched by an engine as a stdio MCP server (newline-delimited JSON-RPC 2.0)
Ensures:
    - on startup appends { t, pid, ppid, cwd, env subset } to UHW_PROBE_MCP_LOG (default /tmp/uhw-mcp-probe.jsonl),
      so the capture works even if the model never calls the tool
    - exposes one tool, whoami, returning the same record as text
"""
import json, os, sys, time

PREFIXES = ( "UHW_", "LUPIN_" )                                  # allow-list: never log tokens or credentials
NAMES    = { "CLAUDE_SESSION_ID", "CLAUDE_PROJECT_DIR", "PWD" }
IDENTITY = { "t": time.time(), "pid": os.getpid(), "ppid": os.getppid(), "cwd": os.getcwd(),
             "env": { k: v for k, v in os.environ.items() if ( k.startswith( PREFIXES ) or k in NAMES ) } }
with open( os.environ.get( "UHW_PROBE_MCP_LOG", "/tmp/uhw-mcp-probe.jsonl" ), "a" ) as log:
    log.write( json.dumps( IDENTITY ) + "\n" )

WHOAMI = { "name": "whoami", "description": "Report the identity this MCP server process was started with.",
           "inputSchema": { "type": "object", "properties": {} } }


def answer( request ):
    method, params = request.get( "method" ), request.get( "params" ) or {}
    if method == "initialize":
        return { "protocolVersion": params.get( "protocolVersion", "2025-06-18" ),
                 "capabilities": { "tools": {} }, "serverInfo": { "name": "uhw-probe", "version": "0.1" } }
    if method == "tools/list":
        return { "tools": [ WHOAMI ] }
    if method == "tools/call" and params.get( "name" ) == "whoami":
        return { "content": [ { "type": "text", "text": json.dumps( IDENTITY ) } ] }
    if method == "ping":
        return {}
    raise LookupError( method )


for line in sys.stdin:
    try: request = json.loads( line )
    except ValueError: continue
    if "id" not in request:
        continue                                                   # notifications need no reply
    try:
        reply = { "jsonrpc": "2.0", "id": request[ "id" ], "result": answer( request ) }
    except LookupError as missing:
        reply = { "jsonrpc": "2.0", "id": request[ "id" ], "error": { "code": -32601, "message": f"no method {missing}" } }
    sys.stdout.write( json.dumps( reply ) + "\n" ); sys.stdout.flush()
