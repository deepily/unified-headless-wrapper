#!/usr/bin/env python3
"""
c17_internal_tools.py jetski|agy -- C17 (T14): which native tools exist beyond the default list, and with which argument keys?

    A. oracle      for each candidate name, an agent definition with tools: [<name>] and a launch with tools denied.
                   C11b/C11c: an unknown name (["*"], call_mcp_tool) is a launch error, so a clean SUCCESS means the
                   name exists. Zero model work beyond one short reply per candidate.
    B. keys        for each survivor, one turn with tools: [<name>, read_file] on a seeded workspace, asking the model
                   to use that tool by name; argument keys from the hook payload go to tool-map.tsv.

Under D47 a persona's native tools are an allow-list, so a tool found here is a grant the role table may or may not
make, not something the gate must discover at run time.

Requires:
    - the engine on PATH; MODEL optionally pins --model; CANDIDATES optionally overrides the list (space-separated)
Ensures:
    - planted files only inside throwaway workspaces
    - out/c17-<bin>-<ts>/verdict.txt, facts.json and tool-map.tsv
"""
import json, os, sys
from capture_lib import *

BIN = sys.argv[ 1 ] if len( sys.argv ) > 1 else "jetski"
out = new_out( f"c17-{BIN}" )
report, planter = Report( out, "c17" ), Planter()
report.say( "version", version( BIN, out ) )

DEFAULT_CANDIDATES = [ "code_search", "grep_search", "find_by_name", "list_dir", "view_code_item", "view_file_outline",
                       "skill_search", "read_url_content", "view_file", "browser_subagent", "generate_image",
                       "write_to_file", "replace_file_content", "search_web", "notebook_edit" ]
CANDIDATES = os.environ.get( "CANDIDATES", " ".join( DEFAULT_CANDIDATES ) ).split()
CONTROLS   = { "run_command": True, "uhw_no_such_tool_7731": False }        # one known-good, one known-bad, to calibrate the oracle
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


def seeded_workspace():
    ws = workspace(); write_hooks( ws )
    ( ws / "notes.txt" ).write_text( "the zebra is here\n" )
    ( ws / "hello.py" ).write_text( "def greet( name ):\n    return f\"hello {name}\"\n" )
    ( ws / "probe.ipynb" ).write_text( json.dumps( { "cells": [], "metadata": {}, "nbformat": 4, "nbformat_minor": 5 } ) )
    return ws


def agent_definition( ws, name, tools ):
    planter.plant( ws / ".agents" / "agents" / f"{name}.md",
                   f"---\nname: {name}\ndescription: UHW probe agent.\ntools: [{', '.join( tools )}]\n---\n\nYou are a probe agent.\n" )


def run( label, ws, turn, agent, **env ):
    summaries = drive( engine_argv( BIN, "--agent", agent ), ws, out / f"frames-{label}.jsonl", [ turn ],
                       UHW_PROBE_LOG=out / f"hook-{label}.jsonl", timeout=180, **env )
    hooks     = [ h for h in jsonl( out / f"hook-{label}.jsonl" ) if h[ "event" ] == "pre_tool" ]
    return summaries, hooks


# A. the oracle
oracle = {}
for name in list( CONTROLS ) + CANDIDATES:
    ws = seeded_workspace(); agent_definition( ws, f"probe-{name}", [ name ] )
    summaries, _ = run( f"oracle-{name}", ws, "Do not use any tools. Reply with the single word ready.", f"probe-{name}", UHW_DENY_ALL="1" )
    status = statuses( summaries )
    oracle[ name ] = { "status": status, "exists": status == [ "SUCCESS" ], "reply": reply_text( summaries )[ :120 ] }
    report.say( f"A. tools: [{name}]", f"{'exists' if oracle[ name ][ 'exists' ] else 'launch refused'} status={status}" )
report.fact( "oracle", oracle )
calibrated = oracle[ "run_command" ][ "exists" ] and not oracle[ "uhw_no_such_tool_7731" ][ "exists" ]
report.say( "A. oracle calibrated (control tools behaved)", "yes" if calibrated else "NO: read B with care" )

# B. argument keys for survivors
rows = [ "candidate\thook name\targument keys\tsample" ]
keys = {}
for name in [ n for n in CANDIDATES if oracle[ n ][ "exists" ] ]:
    ws = seeded_workspace(); agent_definition( ws, f"use-{name}", [ name, "read_file" ] )
    summaries, hooks = run( f"use-{name}", ws, f"Using only the tool named {name}, {USES.get( name, 'use that tool once on this directory' )}. Then say which tool you used.", f"use-{name}" )
    seen = [ h for h in hooks if tool_name( h[ "payload" ] ) == name ]
    keys[ name ] = { "called": bool( seen ), "all_calls": [ tool_name( h[ "payload" ] ) for h in hooks ], "status": statuses( summaries ),
                     "argument_keys": sorted( tool_args( seen[ 0 ][ "payload" ] ).keys() ) if seen else [],
                     "sample": json.dumps( tool_args( seen[ 0 ][ "payload" ] ) )[ :200 ] if seen else "" }
    rows.append( f"{name}\t{name if seen else '-'}\t{','.join( keys[ name ][ 'argument_keys' ] )}\t{keys[ name ][ 'sample' ]}" )
    report.say( f"B. {name}", f"called={keys[ name ][ 'called' ]} keys={keys[ name ][ 'argument_keys' ]} other calls={[ c for c in keys[ name ][ 'all_calls' ] if c != name ]}" )
report.fact( "keys", keys )
( out / "tool-map.tsv" ).write_text( "\n".join( rows ) + "\n" )

survivors = [ n for n in CANDIDATES if oracle[ n ][ "exists" ] ]
report.finish( f"exists={survivors or 'none beyond the controls'}; keys captured for {[ n for n in survivors if keys.get( n, {} ).get( 'called' ) ]}" )
