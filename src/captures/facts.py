#!/usr/bin/env python3
"""
facts.py OUT_DIR --check c1|c2|c3|c4|c6|c7 [--workspace DIR] [--pinned UUID]

Requires:
    - OUT_DIR holds what a capture script wrote: summary*.jsonl (drive.py stdout), frames*.jsonl,
      and optionally hook.jsonl (probe_hook.py) and mcp.jsonl (probe_mcp.py)
Ensures:
    - prints one verdict line per fact, then a final PASS / FAIL / PARTIAL line; writes the same to verdict.txt
    - writes facts.json with the raw facts behind the verdict, which is what to paste back
"""
import argparse, json, os
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument( "out" )
parser.add_argument( "--check", required=True )
parser.add_argument( "--workspace" )
parser.add_argument( "--pinned" )
arguments = parser.parse_args()
out = Path( arguments.out )


def rows( pattern ):
    found = []
    for path in sorted( out.glob( pattern ) ):
        found += [ json.loads( line ) for line in path.read_text().splitlines() if line.strip().startswith( "{" ) ]
    return found


def tool_call( payload ):
    for key in ( "toolCall", "tool_call" ):
        if isinstance( payload.get( key ), dict ):
            return payload[ key ]
    return {}


def hook_tool_name( payload ):
    call = tool_call( payload )
    return call.get( "name" ) or call.get( "toolName" ) or payload.get( "tool_name" )


turns   = [ r for r in rows( "summary*.jsonl" ) if "turn" in r and "results" in r ]
frames  = rows( "frames*.jsonl" )
hooks   = rows( "hook.jsonl" )
servers = [ r for r in rows( "mcp.jsonl" ) if "pid" in r ]          # identity rows; C14 call/eof rows have no pid
pre     = [ h for h in hooks if h[ "event" ] == "pre_tool" ]
session = next( ( t[ "session" ] for t in turns if t.get( "session" ) ), None )
facts = {
    "results"            : [ r for t in turns for r in t[ "results" ] ],
    "session"            : session,
    "engine_pids"        : sorted( { t[ "pid" ] for t in turns } ),
    "stream_tools"       : [ name for t in turns for name in t[ "tools" ] ],
    "hook_events"        : len( hooks ),
    "hook_denies"        : sum( h[ "deny" ] for h in pre ),
    "hook_payload_keys"  : sorted( pre[ 0 ][ "payload" ] ) if pre else [],
    "hook_toolcall_keys" : sorted( tool_call( pre[ 0 ][ "payload" ] ) ) if pre else [],
    "hook_tools"         : [ hook_tool_name( h[ "payload" ] ) for h in pre ],
    "hook_has_session"   : bool( session ) and any( session in json.dumps( h[ "payload" ] ) for h in hooks ),
    "hook_env_tags"      : sorted( { h[ "env" ].get( "UHW_PROBE_TAG" ) for h in hooks } - { None } ),
    "veto_text_in_stream": any( "UHW-VETO-7731" in json.dumps( f[ "frame" ] ) for f in frames ),
    "mcp_servers"        : [ { "pid": s[ "pid" ], "ppid": s[ "ppid" ], "tag": s[ "env" ].get( "UHW_PROBE_TAG" ),
                               "block": s[ "env" ].get( "UHW_PROBE_BLOCK" ), "expanded": s[ "env" ].get( "UHW_PROBE_EXPANDED" ) }
                             for s in servers ],
}
lines = []


def say( label, value ):
    lines.append( f"{label:<40} {value}" )


def yes( condition ):
    return "yes" if condition else "no"


workspace = Path( arguments.workspace ) if arguments.workspace else None
check = arguments.check

if check == "c1":
    allowed = workspace and ( workspace / "allowed.marker" ).exists()
    blocked = workspace and not ( workspace / "UHW_DENY_ME.marker" ).exists()
    say( "hook fired", yes( hooks ) )
    say( "hook denied a call", yes( facts[ "hook_denies" ] ) )
    say( "allowed call ran", yes( allowed ) )
    say( "sentinel call blocked", yes( blocked ) )
    say( "model saw the deny_reason", yes( facts[ "veto_text_in_stream" ] ) )
    say( "turn results", [ r[ "status" ] for r in facts[ "results" ] ] )
    say( "hook payload keys", facts[ "hook_payload_keys" ] )
    say( "toolCall keys", facts[ "hook_toolcall_keys" ] )
    say( "session id inside hook payload", yes( facts[ "hook_has_session" ] ) )
    say( "parent env reached hook", facts[ "hook_env_tags" ] or "no" )
    passed = hooks and facts[ "hook_denies" ] and allowed and blocked
    verdict = "PASS" if passed else ( "FAIL: hook never fired" if not hooks else "FAIL: see lines above" )

elif check == "c2":
    stream = [ ( f[ "frame" ][ "step_update" ].get( "tool_name" ), f[ "frame" ][ "step_update" ] )
               for f in frames if f[ "frame" ].get( "event" ) == "step_update"
               and f[ "frame" ][ "step_update" ].get( "step_type" ) == "tool"
               and f[ "frame" ][ "step_update" ].get( "state" ) == "ACTIVE" ]
    table = [ "index\tstream_tool\thook_tool\targ_keys\tsample_args" ]
    for index in range( max( len( stream ), len( pre ) ) ):
        hook = pre[ index ][ "payload" ] if index < len( pre ) else {}
        args = tool_call( hook ).get( "args" ) or hook.get( "tool_input" ) or {}
        table.append( "\t".join( [ str( index ), str( stream[ index ][ 0 ] if index < len( stream ) else "" ),
                                   str( hook_tool_name( hook ) if hook else "" ),
                                   ",".join( sorted( args ) ) if isinstance( args, dict ) else type( args ).__name__,
                                   json.dumps( args )[ :100 ] ] ) )
    ( out / "tool-map.tsv" ).write_text( "\n".join( table ) + "\n" )
    say( "tool calls seen in stream", len( stream ) )
    say( "tool calls seen by hook", len( pre ) )
    say( "names agree (stream vs hook)", yes( [ s[ 0 ] for s in stream ] == facts[ "hook_tools" ] ) )
    say( "distinct tool names", sorted( { s[ 0 ] for s in stream } | set( filter( None, facts[ "hook_tools" ] ) ) ) )
    verdict = "PASS: see tool-map.tsv" if stream and pre else "PARTIAL: stream-only names, see tool-map.tsv" if stream else "FAIL: no tool calls"

elif check == "c3":
    tags = sorted( { s[ "tag" ] for s in facts[ "mcp_servers" ] } - { None } )
    say( "MCP servers started", len( servers ) )
    say( "distinct server pids", len( { s[ "pid" ] for s in servers } ) )
    say( "server ppids / engine pids", f"{sorted( { s[ 'ppid' ] for s in servers } )} / {facts[ 'engine_pids' ]}" )
    say( "parent env inherited (tags)", tags or "no" )
    say( "config env block applied", yes( any( s[ "block" ] == "block-static" for s in facts[ "mcp_servers" ] ) ) )
    say( "${VAR} expanded in env block", yes( any( s[ "expanded" ] and s[ "expanded" ] == s[ "tag" ] for s in facts[ "mcp_servers" ] ) )
         + f"  (raw: {sorted( { s[ 'expanded' ] for s in facts[ 'mcp_servers' ] } - { None } )})" )
    mcp_hooks = [ h for h in pre if hook_tool_name( h[ "payload" ] ) == "call_mcp_tool"            # AGY: one generic tool,
                  or "whoami" in str( hook_tool_name( h[ "payload" ] ) ) ]                          # Claude: mcp__server__tool
    say( "model called whoami", yes( mcp_hooks or any( "whoami" in json.dumps( f[ "frame" ] ) for f in frames
                                                      if f[ "frame" ].get( "event" ) == "step_update" ) ) )
    say( "hook fired on MCP tool (name, args)", [ ( hook_tool_name( h[ "payload" ] ), sorted( tool_call( h[ "payload" ] ).get( "args", {} ) ) )
                                                  for h in mcp_hooks ][ :1 ] or "no" )
    say( "tool calls before the MCP call", [ hook_tool_name( h[ "payload" ] ) for h in pre[ :pre.index( mcp_hooks[ 0 ] ) ] ] if mcp_hooks else "n/a" )
    per_process = len( tags ) >= 2 and len( { s[ "pid" ] for s in servers } ) >= 2
    verdict = ( "PASS: identity by inherited env, one server per engine" if per_process
                else "PARTIAL: servers start, identity not per process" if servers else "FAIL: no server started" )

elif check == "c4":
    first  = [ t for t in rows( "summary-1.jsonl" ) if "results" in t ]
    second = [ t for t in rows( "summary-2.jsonl" ) if "results" in t ]
    got    = first[ 0 ][ "session" ] if first else None
    status = first[ 0 ][ "results" ][ 0 ][ "status" ] if first and first[ 0 ][ "results" ] else None
    recall = second and any( "PELICAN" in r[ "text" ].upper() for r in second[ 0 ][ "results" ] )
    say( "requested id", arguments.pinned )
    say( "id reported by engine", got )
    say( "first turn status", status )
    say( "resume recalled PELICAN", yes( recall ) )
    verdict = ( "PASS: id pinned before spawn" if got == arguments.pinned and recall
                else "FAIL: pinned id rejected" if status not in ( "SUCCESS", None )
                else "PARTIAL: engine assigns its own id" )

elif check == "c6":
    first, second = ( turns + [ {}, {} ] )[ :2 ]
    controls = [ f[ "frame" ] for f in frames if f[ "frame" ].get( "type" ) == "control_response" ]
    say( "driver sent interrupt", yes( first.get( "interrupted_by_driver" ) ) )
    say( "control_response frame", json.dumps( controls[ :1 ] )[ :200 ] or "none" )
    say( "interrupted result (status, is_error)", [ ( r[ "status" ], r.get( "is_error" ) ) for r in first.get( "results", [] ) ] )
    say( "process alive after interrupt", yes( first.get( "alive_after" ) ) )
    say( "same pid for next turn", yes( first.get( "pid" ) and first.get( "pid" ) == second.get( "pid" ) ) )
    say( "next turn", [ ( r[ "status" ], r[ "text" ][ :60 ] ) for r in second.get( "results", [] ) ] )
    say( "session ids == pinned", yes( { r[ "session" ] for r in facts[ "results" ] } == { arguments.pinned } ) )
    survived = ( first.get( "interrupted_by_driver" ) and first.get( "alive_after" ) and first.get( "pid" ) == second.get( "pid" )
                 and second.get( "results" ) and second[ "results" ][ 0 ][ "status" ] == "success" )
    verdict = ( "FAIL: the turn ended before the driver could interrupt (raise the count)" if not first.get( "interrupted_by_driver" )
                else "PASS: control interrupt, process survives" if survived else "FAIL: see lines above" )

elif check == "c7":
    first   = turns[ 0 ] if turns else {}
    results = first.get( "results", [] )
    where   = [ i for i, r in enumerate( results ) if "BANANA" in r[ "text" ].upper() ]
    replays = [ f[ "t" ] for f in frames if f[ "frame" ].get( "type" ) == "user"
                and "BANANA" in json.dumps( f[ "frame" ].get( "message", {} ) ).upper() ]
    say( "injected at (s)", first.get( "injected_at" ) )
    say( "result frames in turn", len( results ) )
    say( "BANANA in result index", where or "none" )
    say( "replayed user frame at (s)", replays or "none" )
    verdict = ( "ABSORBED: mid-turn message joined the running turn" if where == [ 0 ] and len( results ) == 1
                else "QUEUED: mid-turn message ran as the next turn" if where and where[ 0 ] >= 1
                else "DROPPED: mid-turn message never answered" )

else:
    raise SystemExit( f"unknown check {check}" )

lines.append( f"VERDICT {check}: {verdict}" )
( out / "facts.json" ).write_text( json.dumps( facts, indent=1 ) )
( out / "verdict.txt" ).write_text( "\n".join( lines ) + "\n" )
print( "\n".join( lines ) )
