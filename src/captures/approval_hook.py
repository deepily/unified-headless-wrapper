#!/usr/bin/env python3
"""
approval_hook.py -- C18: a PreToolUse hook that behaves like one gate rule in `ask` mode (D49, T26 spec Section 4).

    The rule: any shell command that names UHW_APPROVE_ME.marker needs approval. The approval key is the marker
    name, not the command text, so `touch X`, `touch ./X`, `: > X` and a python one-liner are one act (spec 4.5).

Requires:
    - stdin carries one hook payload (Claude: tool_name/tool_input; Jetski family: toolCall.name/args)
    - UHW_FAMILY is "claude" or "jetski" (decides the output shape; the real shim reads LUPIN_ENGINE, D48)
    - UHW_TICKET_DIR is a writable directory shared with approval_mcp.py; UHW_PROBE_LOG a writable JSONL file
Ensures:
    - no ticket for the key -> opens one (pending) and denies with the D49 instruction
    - pending -> denies "approval pending"; answered yes and unconsumed -> allows once and marks it consumed
    - consumed -> denies "already used"; always exits 0; every decision is appended to UHW_PROBE_LOG
"""
import json, os, re, secrets, sys, time
from pathlib import Path

KEY_PATTERN = re.compile( r"UHW_APPROVE_ME\.marker" )
TICKETS     = Path( os.environ.get( "UHW_TICKET_DIR", "/tmp/uhw-tickets" ) )
FAMILY      = os.environ.get( "UHW_FAMILY", "jetski" )


def call_of( payload ):
    """( tool_name, arguments ) in either family's payload shape."""
    if "toolCall" in payload:
        return payload[ "toolCall" ].get( "name" ), payload[ "toolCall" ].get( "args" ) or {}
    return payload.get( "tool_name" ), payload.get( "tool_input" ) or {}


def approval_key( name, arguments ):
    """The act, normalized: the marker name if any shell-like argument mentions it, else None (rule does not match)."""
    text = json.dumps( arguments )
    return "UHW_APPROVE_ME.marker" if KEY_PATTERN.search( text ) else None


def decide( key ):
    """
    Requires: key is the normalized act
    Ensures:  returns ( allow: bool, text: str, ticket: dict ) and persists the ticket transition
    """
    TICKETS.mkdir( parents=True, exist_ok=True )
    path = TICKETS / f"{key}.json"
    if not path.exists():
        ticket = { "ticket": f"ask-{secrets.token_hex( 4 )}", "key": key, "status": "pending", "answer": None,
                   "consumed_at": None, "opened_at": time.time(), "denies": 1, "allows": 0 }
        path.write_text( json.dumps( ticket ) )
        return False, ( f"needs approval · ticket {ticket[ 'ticket' ]} · call ask_wait( \"{ticket[ 'ticket' ]}\" ); "
                        f"when it returns answered:yes, repeat this exact call" ), ticket
    ticket = json.loads( path.read_text() )
    if ticket[ "status" ] == "pending":
        ticket[ "denies" ] += 1; path.write_text( json.dumps( ticket ) )
        return False, f"approval pending · ticket {ticket[ 'ticket' ]} · call ask_wait( \"{ticket[ 'ticket' ]}\" )", ticket
    if ticket[ "answer" ] != "yes":
        ticket[ "denies" ] += 1; path.write_text( json.dumps( ticket ) )
        return False, f"refused by human: no", ticket
    if ticket[ "consumed_at" ]:
        ticket[ "denies" ] += 1; path.write_text( json.dumps( ticket ) )
        return False, f"approval {ticket[ 'ticket' ]} already used; ask again", ticket
    ticket[ "consumed_at" ] = time.time(); ticket[ "allows" ] += 1; path.write_text( json.dumps( ticket ) )
    return True, "", ticket


def emit( allow, text ):
    if FAMILY == "claude":
        if not allow:
            print( json.dumps( { "hookSpecificOutput": { "hookEventName": "PreToolUse", "permissionDecision": "deny",
                                                         "permissionDecisionReason": text } } ) )
    else:
        print( json.dumps( { "allow_tool": True } if allow else { "allow_tool": False, "deny_reason": text } ) )


def main():
    raw = sys.stdin.read()
    try: payload = json.loads( raw )
    except ValueError: payload = { "unparsed": raw }
    name, arguments = call_of( payload )
    key   = approval_key( name, arguments ) if name else None
    allow, text, ticket = ( True, "", None ) if key is None else decide( key )
    with open( os.environ.get( "UHW_PROBE_LOG", "/tmp/uhw-approval-hook.jsonl" ), "a" ) as log:
        log.write( json.dumps( { "t": time.time(), "event": "pre_tool", "tool": name, "arguments": arguments, "key": key,
                                 "allow": allow, "text": text, "ticket": ticket and ticket[ "ticket" ] } ) + "\n" )
    emit( allow, text )
    sys.exit( 0 )


if __name__ == "__main__":
    main()
