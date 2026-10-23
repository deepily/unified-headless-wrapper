#!/usr/bin/env python3
"""
c11c_final.py jetski|agy -- round 3: the last three questions C11/C11b left open.

    A. global skills   ~/.gemini/config/skills/<name>/SKILL.md (named by Jetski's migrate-workflows skill): indexed?
    B. rules           .agents/rules with frontmatter (C11's had none): always_on, model_decision; plus .agent/rules and
                       ~/.gemini/config/rules. Tools denied first (always-on must be in context), then allowed (model_decision
                       rules may be read on demand; every call logged)
    C. tool surface    the default tool list (ask with tools denied), then agent definitions that try to reach the uhw-probe
                       MCP server: [run_command] (control), [call_mcp_tool], [call_mcp_tool, read_file]. The model reads a
                       tool's schema file with read_file before its first MCP call (C14), so that grant may matter

Requires:
    - the engine on PATH; MCP_CONFIG optional (default ~/.gemini/config/mcp_config.json)
Ensures:
    - planted files only where absent, removed on exit; MCP config backed up and restored
    - out/c11c-<bin>-<ts>/verdict.txt and facts.json (tracked by git, like the other results)
"""
import atexit, json, os, re, shutil, sys
from capture_lib import *

BIN = sys.argv[ 1 ] if len( sys.argv ) > 1 else "jetski"
out = new_out( f"c11c-{BIN}" )
report, planter = Report( out, "c11c" ), Planter()
report.say( "version", version( BIN, out ) )
home, CODE = Path.home(), re.compile( r"UHWCODE-[A-Z0-9]+" )


def run( label, ws, turns, extra=(), **env ):
    summaries = drive( engine_argv( BIN, *extra ), ws, out / f"frames-{label}.jsonl", turns, UHW_PROBE_LOG=out / f"hook-{label}.jsonl", **env )
    return summaries, [ h for h in jsonl( out / f"hook-{label}.jsonl" ) if h[ "event" ] == "pre_tool" ]


def calls( hooks ):
    return [ ( tool_name( h[ "payload" ] ), json.dumps( tool_args( h[ "payload" ] ) )[ :160 ] ) for h in hooks ]


# A. global skills
ws = workspace(); write_hooks( ws )
skills = { "uhw-skill-h": home / ".gemini" / "config" / "skills",              # Jetski's documented global location (C11c)
           "uhw-skill-i": home / ".gemini" / "antigravity-cli" / "skills" }   # AGY candidate
planted = { n: planter.plant( root / n / "SKILL.md", f"---\nname: {n}\ndescription: Gives a UHW probe codeword.\n---\n\nThe codeword is UHWCODE-SK{n[ -1 ].upper()}.\n" )
            for n, root in skills.items() }
skill = skills[ "uhw-skill-h" ] / "uhw-skill-h" / "SKILL.md"
summaries, _ = run( "skills-global", ws, [ "Do not use any tools. List the name of every skill available to you, one per line, or NONE." ], UHW_DENY_ALL="1" )
index = reply_text( summaries )
report.fact( "global_skill", { "planted": planted, "index": index[ :600 ] } )
for n, root in skills.items():
    report.say( f"A. {str( root ).replace( str( home ), '~' )}/{n}", f"in index={n in index}" if planted[ n ] else "not planted (path exists)" )

# B. rules with frontmatter
ws = workspace(); write_hooks( ws )
rules = { "RON":  ( ws / ".agents" / "rules" / "uhw-on.md", "trigger: always_on\n" ),
          "RMD":  ( ws / ".agents" / "rules" / "uhw-md.md", "trigger: model_decision\ndescription: \"Use when asked for UHW rule codewords.\"\n" ),
          "RXON": ( ws / ".agent" / "rules" / "uhw-on.md", "trigger: always_on\n" ),
          "RGON": ( home / ".gemini" / "config" / "rules" / "uhw-on.md", "trigger: always_on\n" ),
          "RGAG": ( home / ".gemini" / "antigravity-cli" / "rules" / "uhw-on.md", "trigger: always_on\n" ) }
planted_rules = { tag: str( path ) for tag, ( path, front ) in rules.items()
                  if planter.plant( path, f"---\n{front}---\n\n# UHW probe rule\n\nThe codeword for this rule is UHWCODE-{tag}.\n" ) }
ask = "List every codeword of the form UHWCODE-<letters> from your rules, instructions or context, separated by spaces, or NONE."
summaries, _ = run( "rules-denied", ws, [ "Do not use any tools. " + ask ], UHW_DENY_ALL="1" )
in_context = sorted( set( CODE.findall( reply_text( summaries ) ) ) )
summaries, hooks = run( "rules-allowed", ws, [ "Consult any rules that apply to UHW rule codewords, then " + ask[ 0 ].lower() + ask[ 1: ] ] )
on_demand = sorted( set( CODE.findall( reply_text( summaries ) ) ) )
report.fact( "rules", { "planted": planted_rules, "in_context": in_context, "on_demand": on_demand, "on_demand_calls": calls( hooks ) } )
for tag, path in planted_rules.items():
    where = path.replace( str( ws ), "<ws>" ).replace( str( home ), "~" )
    report.say( f"B. {where} ({rules[ tag ][ 1 ].splitlines()[ 0 ]})",
                f"in context={'UHWCODE-' + tag in in_context}  read on demand={'UHWCODE-' + tag in on_demand}" )
report.say( "B. tools used on demand", sorted( { c[ 0 ] for c in calls( hooks ) } ) or "none" )

# C. tool surface and what an agent needs to reach MCP
ws = workspace(); write_hooks( ws )
summaries, _ = run( "tool-list", ws, [ "Do not use any tools. List the exact name of every tool available to you, one per line, nothing else." ],
                    UHW_DENY_ALL="1" )
tool_list = [ l.strip( " -*`" ) for l in reply_text( summaries ).splitlines() if re.fullmatch( r"[-*` ]*[a-z][a-z0-9_]+`?", l.strip() ) ]
report.fact( "default_tools", tool_list )
report.say( "C. default tools (as the model lists them)", tool_list or reply_text( summaries )[ :200 ] )

config_path = Path( os.environ.get( "MCP_CONFIG", home / ".gemini" / "config" / "mcp_config.json" ) )
backup, existed = out / "mcp_config.backup", config_path.exists()
if existed: shutil.copy( config_path, backup )
atexit.register( lambda: shutil.copy( backup, config_path ) if existed else config_path.unlink( missing_ok=True ) )
config = json.loads( config_path.read_text() ) if existed and config_path.stat().st_size else {}
config.setdefault( "mcpServers", {} )[ "uhw-probe" ] = { "command": PY, "args": [ str( HERE / "probe_mcp.py" ) ],
                                                         "env": { "UHW_PROBE_MCP_LOG": str( out / "mcp.jsonl" ) } }
config_path.parent.mkdir( parents=True, exist_ok=True ); config_path.write_text( json.dumps( config, indent=1 ) )
variants = { "uhw-agent-m0": "[run_command]", "uhw-agent-m1": "[call_mcp_tool]", "uhw-agent-m2": "[call_mcp_tool, read_file]" }
agents = {}
for name, tools in variants.items():
    planter.plant( ws / ".agents" / "agents" / f"{name}.md", f"---\nname: {name}\ndescription: UHW probe agent.\ntools: {tools}\n---\n\nYou are a probe agent.\n" )
for name, tools in variants.items():
    summaries, hooks = run( f"agent-{name}", ws, [ "Call the whoami tool from the uhw-probe MCP server exactly once and quote its output verbatim." ],
                            ( "--agent", name ), UHW_PROBE_TAG=name )
    reached = any( r.get( "env", {} ).get( "UHW_PROBE_TAG" ) == name for r in jsonl( out / "mcp.jsonl" ) ) and '"pid"' in reply_text( summaries )
    agents[ name ] = { "tools": tools, "status": statuses( summaries ), "calls": calls( hooks ), "whoami_answered": reached,
                       "agentName": sorted( { str( h[ "payload" ].get( "agentName" ) ) for h in hooks } ), "reply": reply_text( summaries )[ :200 ] }
    report.say( f"C. {name} tools: {tools}", f"whoami answered={reached} calls={[ c[ 0 ] for c in agents[ name ][ 'calls' ] ]} status={agents[ name ][ 'status' ]}" )
report.fact( "agents_mcp", agents )

minimal = next( ( agents[ n ][ "tools" ] for n in ( "uhw-agent-m1", "uhw-agent-m2" ) if agents[ n ][ "whoami_answered" ] ), "neither variant" )
report.finish( f"global skills at {[ n for n in skills if n in index ] or 'none'}; always_on rule in context={'yes' if 'UHWCODE-RON' in in_context else 'no'}; "
               f"minimal tools for MCP={minimal}" )
