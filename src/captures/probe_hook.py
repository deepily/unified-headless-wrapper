#!/usr/bin/env python3
"""
probe_hook.py -- Jetski/AGY hook probe for captures C1-C3.

Requires:
    - stdin carries one hook payload (JSON); argv[1] names the hook event (pre_tool, post_tool, ...)
    - UHW_PROBE_LOG names a writable JSONL file (default /tmp/uhw-hook-probe.jsonl)
Ensures:
    - appends { t, event, deny, ppid, env subset, payload } to the log
    - pre_tool: denies any call whose tool arguments contain UHW_DENY_ME, allows everything else
    - always exits 0: Jetski treats a non-zero exit as a hook failure, not a denial
"""
import json, os, sys, time

SENTINEL = "UHW_DENY_ME"
REASON   = "UHW-VETO-7731: blocked by the capture hook"
NAMES    = { "UHW_PROBE_TAG", "UHW_PROBE_BLOCK", "UHW_PROBE_EXPANDED",      # exact names only: a prefix match once
             "LUPIN_PERSONA_ID", "CLAUDE_SESSION_ID", "CLAUDE_PROJECT_DIR", "PWD" }   # logged LUPIN_DEV_PASSWORD (2026-10-15)


def tool_part( payload ):
    """The tool-call part of the payload only, so a sentinel in the user prompt never triggers a deny."""
    for key in ( "toolCall", "tool_call", "tool_input" ):
        if key in payload:
            return payload[ key ]
    return payload


def main():
    event = sys.argv[ 1 ] if len( sys.argv ) > 1 else "unknown"
    raw = sys.stdin.read()
    try: payload = json.loads( raw )
    except ValueError: payload = { "unparsed": raw }
    deny = event == "pre_tool" and SENTINEL in json.dumps( tool_part( payload ) )
    with open( os.environ.get( "UHW_PROBE_LOG", "/tmp/uhw-hook-probe.jsonl" ), "a" ) as log:
        log.write( json.dumps( { "t": time.time(), "event": event, "deny": deny, "ppid": os.getppid(),
                                 "env": { k: v for k, v in os.environ.items() if k in NAMES },
                                 "payload": payload } ) + "\n" )
    if event == "pre_tool":
        print( json.dumps( { "allow_tool": False, "deny_reason": REASON } if deny else { "allow_tool": True } ) )
    else:
        print( "{}" )


try:
    main()
except Exception:
    print( json.dumps( { "allow_tool": True } ) )
sys.exit( 0 )
