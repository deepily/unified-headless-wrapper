#!/usr/bin/env python3
"""
c17_internal_tools.py jetski|agy [--replay <out directory>] -- C17 (T14, D74): which built-in tools does a persona
definition deliver, under which name and with which argument keys?

    A. launch      for each candidate name, an agent definition with tools: [<name>] and a launch with tools denied.
                   A clean SUCCESS means the launch ACCEPTED the name. It does not mean the tool exists: both engines
                   accept retired names as aliases or as no-ops (measured 2026-11-16, both engines).
    B. delivery    for each accepted name, one turn with tools: [<name>, read_file] on a seeded workspace, asking the
                   model to use that tool by name. A name counts as DELIVERED only when the hook saw it called. Otherwise
                   the row says what happened: an alias (the hook saw another tool called), a launch error (the text is
                   recorded, and the turn is repeated with the name alone), or not delivered (the names the reply gave).
    C. manage_task one turn with tools: [run_command]: background a command, then list it, read its status, send it
                   input and kill it. The argument names of run_command and manage_task are read from the hook payloads
                   and compared with the provisional constants of builtin_tools.py (Tools-6 of D74).

The first frame's tool list is recorded from every launch (one fixed list on both engines; D74 reads it as nothing).

Requires:
    - the engine on PATH; MODEL optionally pins --model; CANDIDATES optionally overrides the list (space-separated);
      PARTS optionally selects parts (default ABC; PARTS=C is the Tools-6 run: one launch, one turn)
    - with --replay: a previous run's directory holding its *.summary and hook-*.jsonl files; no engine is started
Ensures:
    - planted files only inside throwaway workspaces; a background command Part C leaves running is killed
    - out/c17-<bin>-<ts>/verdict.txt, facts.json, tool-map.tsv and results-manage-task.tsv
      (with --replay: the same four under <out directory>/replay/, the original files untouched)
"""
import json, os, re, signal, sys
from pathlib import Path
from capture_lib import *

COMPANION   = "read_file"                                                     # granted beside each candidate in Part B
ACTIONS     = ( "list", "status", "send_input", "kill" )                      # D74, ruling 2
PROVISIONAL = { "action": "Action", "task_id": "TaskId", "input": "Input" }   # builtin_tools.py: TASK_ACTION, TASK_ID, TASK_INPUT
TASK_MARKER = "UHW_C17_TASK_7731"
TASK_INPUT  = "uhw-input-7731"
TASK_COMMAND = f"sh -c 'read line; echo got $line; sleep 300' {TASK_MARKER}"
TASK_TURN   = ( f"Do these steps in order, one tool call per step. "
                f"1. With run_command, start this exact command so that it keeps running as a background task (wait at most one second for it): {TASK_COMMAND} "
                f"2. With manage_task, list the running tasks. "
                f"3. With manage_task, check the status of that task. "
                f"4. With manage_task, send that task the input line {TASK_INPUT} "
                f"5. With manage_task, check its status again. "
                f"6. With manage_task, kill that task. "
                f"Then reply with the task's identifier and the name of every tool you called. If a step cannot be done, say which and why." )

DEFAULT_CANDIDATES = [ "code_search", "grep_search", "find_by_name", "list_dir", "view_code_item", "view_file_outline",
                       "skill_search", "read_url_content", "view_file", "browser_subagent", "generate_image",
                       "write_to_file", "replace_file_content", "search_web", "notebook_edit" ]
CONTROLS = { "run_command": True, "uhw_no_such_tool_7731": False }            # one known-good, one known-bad, to calibrate Part A
USES = { "code_search": "search this project's code for the word zebra with your code search tool",
         "grep_search": "grep this project for the word zebra with your grep tool",
         "find_by_name": "find every file named *.txt with your find-by-name tool",
         "list_dir": "list this directory with your directory-listing tool",
         "view_code_item": "view the function named greet in hello.py with your code-item tool",
         "view_file_outline": "show the outline of hello.py with your outline tool",
         "skill_search": "search your skills for the word probe with your skill search tool",
         "read_url_content": "read https://example.com with your URL reading tool",
         "view_file": "view notes.txt with your file viewing tool",
         "browser_subagent": "open https://example.com with your browser tool and report its title",
         "generate_image": "generate a 64 by 64 image of a red square with your image tool",
         "write_to_file": "write the word hello into new.txt with your file writing tool",
         "replace_file_content": "replace zebra with giraffe in notes.txt with your content replacing tool",
         "search_web": "search the web for the phrase unified headless wrapper with your web search tool",
         "notebook_edit": "add a code cell printing hello to probe.ipynb with your notebook tool" }


# ---- pure functions: no engine, no files (tested by .scratch/row53/test_c17_classify.py and by --replay) ----

def launch_error( summaries ):
    """The first error text of a launch, or None."""
    for summary in summaries:
        for result in summary.get( "results", [] ):
            if result.get( "error" ): return result[ "error" ]
    return None


def reply_names( text, own ):
    """Tool-like names the reply put in backticks, other than the candidate's own: what the model said it had or used."""
    return sorted( { n for n in re.findall( r"`([a-z][a-z0-9_]*)`", text or "" ) if n != own and "_" in n } )


def classify_delivery( name, status, error, calls, reply, companion=COMPANION ):
    """
    Part B's outcome for one candidate.

    Requires: calls is the list of ( tool name, argument dict ) the pre-tool hook saw, in order
    Ensures: outcome is one of delivered, alias, launch_error, not_delivered; delivered only when the hook saw `name` called
    """
    own    = [ a for n, a in calls if n == name ]
    others = [ n for n, _ in calls if n != name ]
    instead = sorted( { n for n in others if n != companion } )
    row = { "outcome": None, "called": bool( own ), "all_calls": [ n for n, _ in calls ], "status": status, "error": error,
            "called_instead": instead, "argument_keys": sorted( own[ 0 ].keys() ) if own else [],
            "sample": json.dumps( own[ 0 ] )[ :200 ] if own else "", "reply_names": reply_names( reply, name ) }
    if own:                       row[ "outcome" ] = "delivered"
    elif status != [ "SUCCESS" ]: row[ "outcome" ] = "launch_error"
    elif instead:                 row[ "outcome" ] = "alias"
    else:                         row[ "outcome" ] = "not_delivered"
    return row


def classify_task_calls( calls ):
    """
    The argument names of manage_task, read from hook payloads.

    Requires: calls is the list of ( tool name, argument dict ) the pre-tool hook saw, in order
    Ensures: names maps action, task_id and input to the key observed (None when no call showed it); agrees compares
             each observed name with PROVISIONAL (None when unobserved); complete only when all four actions were seen
    """
    task  = [ a for n, a in calls if n == "manage_task" ]
    names = { "action": None, "task_id": None, "input": None }
    seen, per_action = [], {}
    for arguments in task:
        action_key = next( ( k for k, v in arguments.items() if isinstance( v, str ) and v.lower() in ACTIONS ), None )
        action     = arguments[ action_key ].lower() if action_key else "unrecognized"
        input_key  = next( ( k for k, v in arguments.items() if isinstance( v, str ) and TASK_INPUT in v ), None )
        rest       = [ k for k in arguments if k not in ( action_key, input_key ) ]
        if action_key and not names[ "action" ]: names[ "action" ] = action_key
        if input_key and not names[ "input" ]:   names[ "input" ]  = input_key
        if action in ( "status", "kill" ) and len( rest ) == 1 and not names[ "task_id" ]: names[ "task_id" ] = rest[ 0 ]
        if action not in seen: seen.append( action )
        per_action.setdefault( action, { "argument_keys": sorted( arguments.keys() ), "sample": json.dumps( arguments )[ :200 ],
                                         "action_value": arguments.get( action_key ) if action_key else None } )
    agrees = { part: ( None if names[ part ] is None else names[ part ] == PROVISIONAL[ part ] ) for part in names }
    return { "hook_saw_manage_task": bool( task ), "calls": len( task ), "actions_seen": seen, "per_action": per_action,
             "names": names, "agrees_with_provisional": agrees, "complete": all( a in seen for a in ACTIONS ),
             "all_calls": [ n for n, _ in calls ],
             "run_command_keys": sorted( next( ( a for n, a in calls if n == "run_command" ), {} ).keys() ) }


# ---- the engine side ----

BIN    = sys.argv[ 1 ] if len( sys.argv ) > 1 else "jetski"
REPLAY = Path( sys.argv[ sys.argv.index( "--replay" ) + 1 ] ).resolve() if "--replay" in sys.argv else None
PARTS  = os.environ.get( "PARTS", "ABC" ).upper()
CANDIDATES = os.environ.get( "CANDIDATES", " ".join( DEFAULT_CANDIDATES ) ).split()

if REPLAY:
    source, out = REPLAY, REPLAY / "replay"
    out.mkdir( exist_ok=True )
    print( f"replaying {source} (no engine is started); output: {out}", flush=True )
else:
    source = out = new_out( f"c17-{BIN}" )
report, planter = Report( out, "c17" ), Planter()
report.say( "version", ( source / "version.txt" ).read_text().strip().splitlines()[ 0 ] if REPLAY else version( BIN, out ) )
if REPLAY: report.say( "replayed from", source.name )
init_lists = {}


def seeded_workspace():
    ws = workspace(); write_hooks( ws )
    ( ws / "notes.txt" ).write_text( "the zebra is here\n" )
    ( ws / "hello.py" ).write_text( "def greet( name ):\n    return f\"hello {name}\"\n" )
    ( ws / "probe.ipynb" ).write_text( json.dumps( { "cells": [], "metadata": {}, "nbformat": 4, "nbformat_minor": 5 } ) )
    return ws


def recorded( label ):
    """Whether a replayed run holds this launch."""
    return ( source / f"frames-{label}.jsonl.summary" ).exists()


def run( label, tools, turn, **env ):
    """One launch, one turn. Returns ( summaries, the pre-tool calls the hook saw as ( name, arguments ) )."""
    frames, hook_log = source / f"frames-{label}.jsonl", source / f"hook-{label}.jsonl"
    if REPLAY:
        summaries = [ s for s in jsonl( str( frames ) + ".summary" ) if "turn" in s ]
    else:
        ws = seeded_workspace()
        planter.plant( ws / ".agents" / "agents" / f"{label}.md",
                       f"---\nname: {label}\ndescription: UHW probe agent.\ntools: [{', '.join( tools )}]\n---\n\nYou are a probe agent.\n" )
        summaries = drive( engine_argv( BIN, "--agent", label ), ws, frames, [ turn ], UHW_PROBE_LOG=hook_log, timeout=180, **env )
    for line in jsonl( frames ):                                              # the first frame's tool list, when the frames are at hand
        if line.get( "frame", {} ).get( "event" ) == "init":
            init_lists[ label ] = line[ "frame" ].get( "init", {} ).get( "tools" )
    calls = [ ( tool_name( h[ "payload" ] ), tool_args( h[ "payload" ] ) ) for h in jsonl( hook_log ) if h[ "event" ] == "pre_tool" ]
    return summaries, calls


def kill_leftover_tasks():
    """Kill any Part C command still running (argv is sh -c <script> TASK_MARKER). Returns how many were found."""
    found = 0
    for entry in Path( "/proc" ).glob( "[0-9]*/cmdline" ):
        try: argv = entry.read_bytes().split( b"\0" )
        except OSError: continue
        if argv[ :2 ] == [ b"sh", b"-c" ] and TASK_MARKER.encode() in argv[ 3:4 ]:
            found += 1
            try: os.kill( int( entry.parent.name ), signal.SIGKILL )
            except ( OSError, ValueError ): pass
    return found


# A. what a launch accepts
launch = {}
if "A" in PARTS:
    for name in list( CONTROLS ) + CANDIDATES:
        if REPLAY and not recorded( f"oracle-{name}" ): continue
        summaries, _ = run( f"oracle-{name}", [ name ], "Do not use any tools. Reply with the single word ready.", UHW_DENY_ALL="1" )
        status = statuses( summaries )
        launch[ name ] = { "status": status, "accepted": status == [ "SUCCESS" ], "error": launch_error( summaries ),
                           "reply": reply_text( summaries )[ :120 ] }
        report.say( f"A. tools: [{name}]", f"{'launch accepted' if launch[ name ][ 'accepted' ] else 'launch refused'} status={status}" )
    report.fact( "launch", launch )
    calibrated = all( name in launch and launch[ name ][ "accepted" ] == expected for name, expected in CONTROLS.items() )
    report.say( "A. controls behaved (run_command accepted, a made-up name refused)", "yes" if calibrated else "NO: read B with care" )
    accepted = [ n for n in CANDIDATES if launch.get( n, {} ).get( "accepted" ) ]
else:
    accepted = list( CANDIDATES )                                             # without Part A, Part B's own launch says which are refused

# B. what the model is delivered
delivery = {}
rows = [ "candidate\toutcome\thook name\targument keys\tsample\tcalled instead\tlaunch error" ]
if "B" in PARTS:
    for name in accepted:
        label = f"use-{name}"
        if REPLAY and not recorded( label ): continue
        turn = f"Using only the tool named {name}, {USES.get( name, 'use that tool once on this directory' )}. Then say which tool you used."
        summaries, calls = run( label, [ name, COMPANION ], turn )
        row = classify_delivery( name, statuses( summaries ), launch_error( summaries ), calls, reply_text( summaries ) )
        if row[ "outcome" ] == "launch_error" and ( not REPLAY or recorded( f"alone-{name}" ) ):     # e.g. view_file beside read_file
            summaries, calls = run( f"alone-{name}", [ name ], turn )
            alone = classify_delivery( name, statuses( summaries ), launch_error( summaries ), calls, reply_text( summaries ), companion=None )
            row[ "alone" ] = alone
            row[ "called_instead" ] = alone[ "called_instead" ]
            if alone[ "outcome" ] == "delivered":
                row.update( { k: alone[ k ] for k in ( "called", "argument_keys", "sample" ) } )
        delivery[ name ] = row
        rows.append( "\t".join( [ name, row[ "outcome" ], name if row[ "called" ] else "-", ",".join( row[ "argument_keys" ] ), row[ "sample" ],
                                  ",".join( row[ "called_instead" ] ), row[ "error" ] or "" ] ) )
        detail = { "delivered":     f"keys={row[ 'argument_keys' ]}",
                   "alias":         f"the hook saw {row[ 'called_instead' ]} called instead",
                   "launch_error":  f"{row[ 'error' ]}" + ( f"; alone: {row[ 'alone' ][ 'outcome' ]}, called {row[ 'alone' ][ 'all_calls' ]}" if "alone" in row else "" ),
                   "not_delivered": f"no call by that name; the reply named {row[ 'reply_names' ] or 'no tool'}" }[ row[ "outcome" ] ]
        report.say( f"B. {name}", f"{row[ 'outcome' ]}: {detail}" )
    report.fact( "delivery", delivery )
( out / "tool-map.tsv" ).write_text( "\n".join( rows ) + "\n" )

# C. the background-task tool's argument names (Tools-6)
task = None
if "C" in PARTS and ( not REPLAY or recorded( "manage-task" ) ):
    summaries, calls = run( "manage-task", [ "run_command" ], TASK_TURN )
    task = classify_task_calls( calls )
    task.update( { "status": statuses( summaries ), "error": launch_error( summaries ), "reply": reply_text( summaries )[ :600 ],
                   "driver_saw_tools": [ t for s in summaries for t in s.get( "tools", [] ) ],
                   "left_running_and_killed": 0 if REPLAY else kill_leftover_tasks() } )
    report.fact( "manage_task", task )
    lines = [ "tool\taction\targument keys\tsample" ] + [ f"run_command\t-\t{','.join( task[ 'run_command_keys' ] )}\t" ]
    lines += [ f"manage_task\t{action}\t{','.join( seen[ 'argument_keys' ] )}\t{seen[ 'sample' ]}" for action, seen in task[ "per_action" ].items() ]
    ( out / "results-manage-task.tsv" ).write_text( "\n".join( lines ) + "\n" )
    report.say( "C. status; calls the hook saw", f"{task[ 'status' ]}; {task[ 'all_calls' ]}" )
    report.say( "C. calls the driver saw in the frames", task[ "driver_saw_tools" ] )
    report.say( "C. run_command argument keys", task[ "run_command_keys" ] )
    for action, seen in task[ "per_action" ].items():
        report.say( f"C. manage_task {action}", f"keys={seen[ 'argument_keys' ]} action value={seen[ 'action_value' ]!r}" )
    for part, constant in PROVISIONAL.items():
        observed = task[ "names" ][ part ]
        report.say( f"C. {part}: provisional {constant}", "not observed" if observed is None else f"observed {observed}: {'agrees' if observed == constant else 'DIFFERS, correct builtin_tools.py'}" )
    report.say( "C. all four actions seen", "yes" if task[ "complete" ] else f"NO: missing {[ a for a in ACTIONS if a not in task[ 'actions_seen' ] ]}" )
    report.say( "C. background commands left running, killed", task[ "left_running_and_killed" ] )

# the first frame's tool list
distinct = { json.dumps( sorted( tools ) ) for tools in init_lists.values() if tools is not None }
report.fact( "init_tools", { "launches_printing_it": len( init_lists ), "distinct_lists": len( distinct ),
                             "lists": [ json.loads( d ) for d in sorted( distinct ) ] } )
report.say( "first frame's tool list", f"{len( init_lists )} launches printed it; {len( distinct )} distinct list(s); sizes {sorted( len( json.loads( d ) ) for d in distinct )}"
            if init_lists else "no frames at hand" )

by = lambda outcome: [ n for n in delivery if delivery[ n ][ "outcome" ] == outcome ]
parts = []
if "A" in PARTS: parts.append( f"launch accepted {len( accepted )} of {len( CANDIDATES )} (acceptance proves nothing about delivery)" )
if "B" in PARTS: parts.append( f"delivered, the hook saw the name called={by( 'delivered' ) or 'none'}; "
                               f"alias={ { n: delivery[ n ][ 'called_instead' ] for n in by( 'alias' ) } or 'none' }; "
                               f"launch error in B={ { n: ( delivery[ n ][ 'called_instead' ] or 'no call alone' ) if 'alone' in delivery[ n ] else 'not retried alone' for n in by( 'launch_error' ) } or 'none' }; "
                               f"not delivered={by( 'not_delivered' ) or 'none'}" )
if task:
    differs = [ p for p, same in task[ "agrees_with_provisional" ].items() if same is False ]
    unseen  = [ p for p, same in task[ "agrees_with_provisional" ].items() if same is None ]
    parts.append( f"manage_task names={task[ 'names' ]}, " + ( f"DIFFER from the provisional constants in {differs}" if differs else "none differs from the provisional constants" )
                  + ( f", NOT OBSERVED: {unseen}" if unseen else "" ) + ( "" if task[ "complete" ] else ", INCOMPLETE: not all four actions were called" ) )
report.finish( "; ".join( parts ) or "nothing ran: PARTS selected no part" )
