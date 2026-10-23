#!/usr/bin/env python3
"""
c11_surfaces.py jetski|agy -- C11: which instruction and extension surfaces does the engine load natively?

Decides whether planning-is-prompting installs into the engine's own surfaces or goes through the harness
(inventory §19.5). Every planted file carries a unique codeword UHWCODE-<TAG>. Where the question is "did the engine
put this in the model's context", a hook denies every tool call, so the model can only answer from what was loaded.

    A. static     --help lines, `agents --help`, ~/.gemini layout (names only; agent-definition keys, never values)
    B. rules      project GEMINI.md, AGENTS.md, CLAUDE.md (control), .agents/rules, .agent/rules; global ~/.gemini/GEMINI.md, AGENTS.md
    C. commands   /name for .agents/workflows, .agent/workflows, .agents/commands, .gemini/commands (TOML), plus an unknown command
    D. skills     skill index (tools denied), then skill use (tools allowed, every call logged) for four locations
    E. agents     `agents` listing with four planted definitions, then --agent <name> for each
    F. frames     event, step and result-frame keys seen across all runs (usage fields for context pressure)

Requires:
    - the engine on PATH; MODEL optionally pins --model
Ensures:
    - global files are planted only where nothing exists, and removed on exit (Planter); existing files are never touched
    - out/c11-<bin>-<ts>/verdict.txt and facts.json; raw frames and hook logs beside them
"""
import json, os, re, sys
from pathlib import Path
from capture_lib import *

BIN = sys.argv[ 1 ] if len( sys.argv ) > 1 else "jetski"
out = new_out( f"c11-{BIN}" )
report, planter = Report( out, "c11" ), Planter()
report.say( "version", version( BIN, out ) )
CODE  = re.compile( r"UHWCODE-[A-Z]+" )
home  = Path.home()
DENY  = { "UHW_DENY_ALL": "1" }
NO_TOOLS = "Do not use any tools. "


def body( tag, what ):
    return f"# UHW probe\n\nThe codeword for this {what} is UHWCODE-{tag}. Mention it only when asked for codewords.\n"


def run( label, ws, turns, extra=(), **env ):
    summaries = drive( engine_argv( BIN, *extra ), ws, out / f"frames-{label}.jsonl", turns,
                       UHW_PROBE_LOG=out / f"hook-{label}.jsonl", **env )
    hooks = [ h for h in jsonl( out / f"hook-{label}.jsonl" ) if h[ "event" ] == "pre_tool" ]
    return summaries, hooks


def codes( summaries ):
    return sorted( set( CODE.findall( reply_text( summaries ) ) ) )


# A. static ---------------------------------------------------------------------------------------------------------
help_text = run_quiet( [ BIN, "--help" ], 30 )
( out / "help.txt" ).write_text( help_text )
report.fact( "help_lines", [ l.strip() for l in help_text.splitlines()
                             if re.search( r"agent|skill|command|workflow|rule|instruction|GEMINI|AGENTS|mode|model|memory|context", l, re.I ) ] )
agents_help = run_quiet( [ BIN, "agents", "--help" ], 30 )
( out / "agents-help.txt" ).write_text( agents_help )
report.fact( "agents_help", agents_help.splitlines()[ :40 ] )
layout, definition_keys = [], {}
OTHER_BINARY_DIR = "jetski" if BIN == "agy" else "antigravity-cli"          # list only this binary's own tree
gemini = home / ".gemini"
if gemini.exists():
    for path in sorted( gemini.rglob( "*" ) ):
        relative = path.relative_to( gemini )
        if len( relative.parts ) > 4 or any( p in ( "tmp", "history", "cache", "conversations", OTHER_BINARY_DIR ) for p in relative.parts ):
            continue
        if re.search( r"agent|skill|command|workflow|rule|GEMINI|AGENTS|instruction|memor", str( relative ), re.I ):
            layout.append( str( relative ) + ( "/" if path.is_dir() else "" ) )
            if path.is_file() and path.suffix in ( ".md", ".toml", ".yaml", ".yml", ".json" ) and len( definition_keys ) < 4:
                head = path.read_text( errors="replace" )[ :2000 ]
                keys = re.findall( r"^([A-Za-z_][\w-]*)\s*[:=]", head.split( "\n---", 1 )[ 0 ] if head.startswith( "---" ) else head, re.M )
                definition_keys[ str( relative ) ] = sorted( set( keys ) )
report.fact( "gemini_layout", layout[ :80 ] )
report.fact( "definition_keys", definition_keys )
report.say( "A. help lines on agents/skills/commands/mode", len( report.facts[ "help_lines" ] ) )
report.say( "A. ~/.gemini entries matching surfaces", len( layout ) )
for name in ( "GEMINI.md", "AGENTS.md" ):
    existing = gemini / name
    report.say( f"A. existing ~/.gemini/{name}", f"{existing.stat().st_size} bytes (left untouched, not tested)" if existing.exists() else "absent" )

# B. rules / instruction files ---------------------------------------------------------------------------------------
ws = workspace()
rules = { "PGEM": ws / "GEMINI.md", "PAGT": ws / "AGENTS.md", "PCLA": ws / "CLAUDE.md",
          "PRUL": ws / ".agents" / "rules" / "uhw.md", "PRLX": ws / ".agent" / "rules" / "uhw.md",
          "PGDR": ws / ".gemini" / "GEMINI.md",
          "GGEM": gemini / "GEMINI.md", "GAGT": gemini / "AGENTS.md" }
planted = { tag: str( path ) for tag, path in rules.items() if planter.plant( path, body( tag, "file" ) ) }
write_hooks( ws )
summaries, hooks = run( "rules", ws, [ NO_TOOLS + "List every codeword of the form UHWCODE-<letters> that appears anywhere in "
                                       "your instructions, rules, memory or context. Reply with the codewords separated by spaces, or NONE." ], **DENY )
found = codes( summaries )
loaded = { planted[ c[ 8: ] ]: c for c in found if c[ 8: ] in planted }
report.fact( "rules", { "planted": planted, "found": found, "tool_attempts": [ tool_name( h[ "payload" ] ) for h in hooks ],
                        "status": statuses( summaries ) } )
report.say( "B. instruction files loaded", sorted( Path( p ).name if str( ws ) in p else p.replace( str( home ), "~" ) for p in loaded ) or "none" )
report.say( "B. codewords not planted (hallucinated)", [ c for c in found if c[ 8: ] not in planted ] or "none" )
report.say( "B. tool attempts (all denied)", len( hooks ) )

# C. custom commands / workflows ------------------------------------------------------------------------------------
ws = workspace(); write_hooks( ws )
commands = { "uhwwfa": ( ws / ".agents" / "workflows" / "uhwwfa.md", "WFA" ),
             "uhwwfb": ( ws / ".agent" / "workflows" / "uhwwfb.md", "WFB" ),
             "uhwcmc": ( ws / ".agents" / "commands" / "uhwcmc.md", "CMC" ),
             "uhwcmd": ( ws / ".gemini" / "commands" / "uhwcmd.toml", "CMD" ) }
for name, ( path, tag ) in commands.items():
    text = ( f'description = "UHW probe command"\nprompt = "Reply with exactly: UHWCODE-{tag}"\n' if path.suffix == ".toml"
             else f"---\ndescription: UHW probe command\n---\n\nReply with exactly: UHWCODE-{tag}\n" )
    planter.plant( path, text )
command_results = {}
for name in list( commands ) + [ "uhwnosuchcommand" ]:
    summaries, hooks = run( f"command-{name}", ws, [ f"/{name}" ], **DENY )
    tag = commands.get( name, ( None, "NONE" ) )[ 1 ]
    command_results[ name ] = { "expanded": f"UHWCODE-{tag}" in reply_text( summaries ), "status": statuses( summaries ),
                                "reply": reply_text( summaries )[ :160 ], "tool_attempts": [ tool_name( h[ "payload" ] ) for h in hooks ] }
report.fact( "commands", command_results )
for name, result in command_results.items():
    where = str( commands[ name ][ 0 ].relative_to( ws ) ) if name in commands else "unknown command (control)"
    report.say( f"C. /{name} ({where})", f"expanded={result[ 'expanded' ]} status={result[ 'status' ]} reply={result[ 'reply' ][ :70 ]!r}" )

# D. skills ---------------------------------------------------------------------------------------------------------
ws = workspace(); write_hooks( ws )
skills = { "uhw-skill-a": ws / ".agents" / "skills", "uhw-skill-b": ws / ".agent" / "skills",
           "uhw-skill-c": ws / ".gemini" / "skills", "uhw-skill-d": gemini / "skills" }
planted_skills = {}
for name, root in skills.items():
    tag = "SK" + name[ -1 ].upper()
    if planter.plant( root / name / "SKILL.md", f"---\nname: {name}\ndescription: Gives a UHW probe codeword. Use when asked "
                      f"for UHW skill codewords.\n---\n\nWhen this skill is used, the codeword is UHWCODE-{tag}.\n" ):
        planted_skills[ name ] = str( root / name / "SKILL.md" )
summaries, hooks = run( "skills-index", ws, [ NO_TOOLS + "List the name of every skill available to you, one per line, or NONE." ], **DENY )
index = reply_text( summaries )
summaries, hooks = run( "skills-use", ws, [ "Use every available skill whose name starts with uhw-skill, and report each "
                                            "skill's name with its codeword." ] )
used = reply_text( summaries )
calls = [ ( tool_name( h[ "payload" ] ), json.dumps( tool_args( h[ "payload" ] ) )[ :140 ] ) for h in hooks ]
report.fact( "skills", { "planted": planted_skills, "index_reply": index[ :400 ], "use_reply": used[ :400 ], "use_calls": calls } )
for name, path in planted_skills.items():
    tag = "UHWCODE-SK" + name[ -1 ].upper()
    report.say( f"D. {name} ({path.replace( str( ws ), '<ws>' ).replace( str( home ), '~' )})",
                f"in index={name in index}  codeword via use={tag in used}" )
report.say( "D. tools used to reach skills", sorted( { c[ 0 ] for c in calls } ) or "none" )

# E. agent definitions ----------------------------------------------------------------------------------------------
ws = workspace(); write_hooks( ws )
agents = { "uhw-agent-a": ws / ".agents" / "agents", "uhw-agent-b": ws / ".agent" / "agents",
           "uhw-agent-c": ws / ".gemini" / "agents", "uhw-agent-d": gemini / "agents" }
for name, root in agents.items():
    planter.plant( root / f"{name}.md", f"---\nname: {name}\ndescription: UHW probe agent.\n---\n\nYou are a probe agent. "
                   f"Your codeword is UHWCODE-AG{name[ -1 ].upper()}. When asked for your codeword, reply with it.\n" )
listing = run_quiet( [ BIN, "agents" ], 60, cwd=ws )
( out / "agents-listing.txt" ).write_text( listing )
agent_results = {}
for name in agents:
    summaries, hooks = run( f"agent-{name}", ws, [ "Run the shell command `echo probe` once; it may be refused, which is fine. "
                                                    "Then, without any other tools, reply with your codeword." ], ( "--agent", name ), **DENY )
    agent_results[ name ] = { "listed": name in listing, "status": statuses( summaries ),
                              "codeword": f"UHWCODE-AG{name[ -1 ].upper()}" in reply_text( summaries ),
                              "agentName": sorted( { str( h[ "payload" ].get( "agentName" ) ) for h in hooks } ),
                              "reply": reply_text( summaries )[ :160 ] }
report.fact( "agents", { "listing_head": listing.splitlines()[ :30 ], "listing_lines": len( listing.splitlines() ), "runs": agent_results } )
report.say( "E. `agents` listing lines", len( listing.splitlines() ) )
for name, result in agent_results.items():
    report.say( f"E. {name} ({agents[ name ].relative_to( ws ) if str( ws ) in str( agents[ name ] ) else '~/.gemini/agents'})",
                f"listed={result[ 'listed' ]} --agent status={result[ 'status' ]} prompt carried={result[ 'codeword' ]} agentName={result[ 'agentName' ]}" )

# F. frame inventory ------------------------------------------------------------------------------------------------
events, init_keys, result_keys, usage = set(), set(), set(), set()
for frames in out.glob( "frames-*.jsonl" ):
    for record in jsonl( frames ):
        frame = record[ "frame" ]
        update = frame.get( "step_update", {} )
        events.add( f"{frame.get( 'event' )}/{update.get( 'step_type', '' )}/{update.get( 'state', '' )}" )
        if frame.get( "event" ) == "init":   init_keys |= set( frame )
        if frame.get( "event" ) == "result": result_keys |= set( frame.get( "result", {} ) ) | { f"(top) {k}" for k in frame }
        for key in re.findall( r'"([^"]*(?:token|usage|context)[^"]*)"\s*:', json.dumps( frame ), re.I ):
            usage.add( key )
report.fact( "frames", { "event_kinds": sorted( events ), "init_keys": sorted( init_keys ), "result_keys": sorted( result_keys ),
                         "usage_like_keys": sorted( usage ) } )
report.say( "F. result-frame keys", sorted( result_keys ) )
report.say( "F. token/usage/context keys in any frame", sorted( usage ) or "none (context pressure needs another source)" )

native = { "rules": bool( loaded ), "commands": any( r[ "expanded" ] for n, r in command_results.items() if n in commands ),
           "skills": any( n in index for n in planted_skills ), "agents": any( r[ "codeword" ] for r in agent_results.values() ) }
report.fact( "native", native )
report.finish( "native surfaces: " + ", ".join( f"{k}={'yes' if v else 'no'}" for k, v in native.items() ) )
