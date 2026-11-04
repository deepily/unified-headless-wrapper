#!/usr/bin/env python3
"""
c15_launch_surfaces.py jetski|agy -- C15: do D47's launch surfaces load together, and is --mode accept-edits a no-op?

    A. together    one workspace, one launch with --agent: agent body codeword, AGENTS.md codeword, a skill whose
                   description carries a codeword, an always-on rule codeword. Tools denied, so every codeword in the
                   reply was loaded by the engine itself. C11/C11c measured each surface alone; D47 relies on all four.
    B. modes       --mode auto and --mode accept-edits, same two-step prompt (write a file, run a command), hooks allowing.
                   Pass = same tool names in the same order, same status, file present in both.
    C. habit       does the agent body change the engine's own behavior: with read_file granted and a probe MCP server
                   configured, is the schema file still read before the first MCP call (framework Section 8 rule 6)?

Requires:
    - the engine on PATH; MODEL optionally pins --model; MCP_CONFIG optional (default ~/.gemini/config/mcp_config.json)
Ensures:
    - planted files only inside throwaway workspaces, plus the probe server entry in the MCP config, backed up and
      restored on any exit
    - out/c15-<bin>-<ts>/verdict.txt and facts.json
"""
import atexit, json, os, re, shutil, signal, sys
from capture_lib import *

BIN = sys.argv[ 1 ] if len( sys.argv ) > 1 else "jetski"
out = new_out( f"c15-{BIN}" )
report, planter = Report( out, "c15" ), Planter()
report.say( "version", version( BIN, out ) )
CODE = re.compile( r"UHWCODE-[A-Z0-9]+" )


def run( label, ws, turns, extra=(), **env ):
    summaries = drive( engine_argv( BIN, *extra ), ws, out / f"frames-{label}.jsonl", turns, UHW_PROBE_LOG=out / f"hook-{label}.jsonl", **env )
    hooks     = [ h for h in jsonl( out / f"hook-{label}.jsonl" ) if h[ "event" ] == "pre_tool" ]
    return summaries, hooks


def agent_definition( ws, name, tools, body ):
    planter.plant( ws / ".agents" / "agents" / f"{name}.md",
                   f"---\nname: {name}\ndescription: UHW probe persona, role {name}.\ntools: [{', '.join( tools )}]\n---\n\n{body}\n" )


# A. all four surfaces in one launch
ws = workspace(); write_hooks( ws )
agent_definition( ws, "reviewer", [ "run_command", "read_file" ], "You are a probe persona. Your body codeword is UHWCODE-AGENT." )
planter.plant( ws / "AGENTS.md", "# Project mandates\n\nThe mandate codeword is UHWCODE-MANDATE.\n" )
planter.plant( ws / ".agents" / "skills" / "uhw-probe-skill" / "SKILL.md",
               "---\nname: uhw-probe-skill\ndescription: Probe skill; its index codeword is UHWCODE-SKILL.\n---\n\nNothing to do.\n" )
planter.plant( ws / ".agents" / "rules" / "uhw-on.md", "---\ntrigger: always_on\n---\n\nThe rule codeword is UHWCODE-RULE.\n" )
ask = "Do not use any tools. List every codeword of the form UHWCODE-<letters> in your instructions, rules, skills or context, separated by spaces, or NONE."
summaries, _ = run( "together", ws, [ ask ], ( "--agent", "reviewer" ), UHW_DENY_ALL="1" )
found = sorted( set( CODE.findall( reply_text( summaries ) ) ) )
report.fact( "together", { "found": found, "status": statuses( summaries ), "reply": reply_text( summaries )[ :400 ] } )
for tag, surface in ( ( "AGENT", "--agent body" ), ( "MANDATE", "AGENTS.md" ), ( "SKILL", ".agents/skills index" ), ( "RULE", ".agents/rules always_on" ) ):
    report.say( f"A. {surface} under --agent", "loaded" if f"UHWCODE-{tag}" in found else "MISSING" )

# B. --mode auto vs --mode accept-edits under skipped permissions
prompt = "Create a file named mode.marker containing the word hello, then run the shell command `echo done`, then reply with the single word finished."
modes  = {}
for mode in ( "auto", "accept-edits" ):
    ws = workspace(); write_hooks( ws )
    agent_definition( ws, "implementer", [ "run_command", "read_file", "write_file", "edit_file" ], "You are a probe persona." )
    summaries, hooks = run( f"mode-{mode}", ws, [ prompt ], ( "--mode", mode, "--agent", "implementer" ) )
    modes[ mode ] = { "tools": [ tool_name( h[ "payload" ] ) for h in hooks ], "status": statuses( summaries ),
                      "marker": ( ws / "mode.marker" ).exists(), "reply": reply_text( summaries )[ :200 ] }
    report.say( f"B. --mode {mode}", f"tools={modes[ mode ][ 'tools' ]} status={modes[ mode ][ 'status' ]} marker={modes[ mode ][ 'marker' ]}" )
report.fact( "modes", modes )
same = all( modes[ "auto" ][ k ] == modes[ "accept-edits" ][ k ] for k in ( "tools", "status", "marker" ) )
report.say( "B. accept-edits indistinguishable from auto", "yes" if same else "no" )

# C. the schema-read habit under an agent body
config_path = Path( os.environ.get( "MCP_CONFIG", Path.home() / ".gemini" / "config" / "mcp_config.json" ) )
backup, existed = out / "mcp_config.backup", config_path.exists()
if existed: shutil.copy( config_path, backup )
atexit.register( lambda: shutil.copy( backup, config_path ) if existed else config_path.unlink( missing_ok=True ) )
config = json.loads( config_path.read_text() ) if existed and config_path.stat().st_size else {}
config.setdefault( "mcpServers", {} )[ "uhw-probe" ] = { "command": PY, "args": [ str( HERE / "probe_mcp.py" ) ],
                                                         "env": { "UHW_PROBE_MCP_LOG": str( out / "mcp.jsonl" ) } }
config_path.parent.mkdir( parents=True, exist_ok=True ); config_path.write_text( json.dumps( config, indent=1 ) )
ws = workspace(); write_hooks( ws )
agent_definition( ws, "steward", [ "run_command", "read_file" ], "You are a probe persona." )
summaries, hooks = run( "habit", ws, [ "Call the whoami tool from the uhw-probe MCP server exactly once and quote its output verbatim." ],
                        ( "--agent", "steward" ), UHW_PROBE_TAG="c15-habit" )
calls = [ ( tool_name( h[ "payload" ] ), json.dumps( tool_args( h[ "payload" ] ) )[ :160 ] ) for h in hooks ]
schema_reads = [ a for n, a in calls if n in ( "read_file", "view_file" ) and "/mcp/" in a ]
report.fact( "habit", { "calls": calls, "schema_reads": schema_reads, "status": statuses( summaries ) } )
report.say( "C. calls before/around the MCP call", [ n for n, _ in calls ] )
report.say( "C. schema file read first", "yes" if schema_reads and calls[ 0 ][ 0 ] in ( "read_file", "view_file" ) else "no" )

report.finish( f"surfaces together={len( found )}/4; accept-edits==auto={'yes' if same else 'no'}; schema read under --agent={'yes' if schema_reads else 'no'}" )
