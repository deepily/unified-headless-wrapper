#!/usr/bin/env python3
"""
c11b_followups.py jetski|agy -- what C11 (2026-10-18) left open.

    A. workflows   /uhwwfa with tools ALLOWED (C11 denied run_workflow); the full slash-command list with workflows planted
    B. skills      global skill locations C11 did not try: ~/.gemini/jetski/skills, ~/.agents/skills, ~/.agent/skills
    C. agent tools C11's agents had no tools ("no shell execution tool"); frontmatter variants that might grant them
    D. format docs the frontmatter/field lines from Jetski's own builtin customization skills (field names, not prose)

Requires:
    - the engine on PATH; MODEL optionally pins --model
Ensures:
    - global files planted only where absent and removed on exit; out/c11b-<bin>-<ts>/verdict.txt and facts.json
"""
import json, re, sys
from capture_lib import *

BIN = sys.argv[ 1 ] if len( sys.argv ) > 1 else "jetski"
out = new_out( f"c11b-{BIN}" )
report, planter = Report( out, "c11b" ), Planter()
report.say( "version", version( BIN, out ) )
home = Path.home()


def run( label, ws, turns, extra=(), **env ):
    summaries = drive( engine_argv( BIN, *extra ), ws, out / f"frames-{label}.jsonl", turns, UHW_PROBE_LOG=out / f"hook-{label}.jsonl", **env )
    return summaries, [ h for h in jsonl( out / f"hook-{label}.jsonl" ) if h[ "event" ] == "pre_tool" ]


# A. workflows with tools allowed
ws = workspace(); write_hooks( ws )
for name, folder in ( ( "uhwwfa", ".agents/workflows" ), ( "uhwwfb", ".agent/workflows" ) ):
    planter.plant( ws / folder / f"{name}.md", f"---\ndescription: UHW probe workflow\n---\n\nReply with exactly: UHWCODE-{name[ -3: ].upper()}\n" )
workflows = {}
for name in ( "uhwwfa", "uhwwfb" ):
    summaries, hooks = run( f"workflow-{name}", ws, [ f"/{name}" ] )
    workflows[ name ] = { "codeword": f"UHWCODE-{name[ -3: ].upper()}" in reply_text( summaries ),
                          "calls": [ ( tool_name( h[ "payload" ] ), json.dumps( tool_args( h[ "payload" ] ) )[ :200 ] ) for h in hooks ],
                          "reply": reply_text( summaries )[ :240 ] }
    report.say( f"A. /{name} (tools allowed)", f"codeword={workflows[ name ][ 'codeword' ]} tools={[ c[ 0 ] for c in workflows[ name ][ 'calls' ] ]}" )
summaries, _ = run( "slash-list", ws, [ "/uhwnosuchcommand" ], UHW_DENY_ALL="1" )
listing = reply_text( summaries )
commands = sorted( set( re.findall( r"`(/[\w:-]+)`", listing ) ) )
report.fact( "workflows", workflows )
report.fact( "slash_list", listing[ :1500 ] )
report.say( "A. slash commands offered", commands or listing[ :120 ] )
report.say( "A. planted workflows among them", [ c for c in commands if c in ( "/uhwwfa", "/uhwwfb" ) ] or "none" )

# B. global skill locations
ws = workspace(); write_hooks( ws )
candidates = { "uhw-skill-e": home / ".gemini" / "jetski" / "skills", "uhw-skill-f": home / ".agents" / "skills",
               "uhw-skill-g": home / ".agent" / "skills" }
planted = { n: str( r ) for n, r in candidates.items()
            if planter.plant( r / n / "SKILL.md", f"---\nname: {n}\ndescription: Gives a UHW probe codeword.\n---\n\nThe codeword is UHWCODE-SK{n[ -1 ].upper()}.\n" ) }
summaries, _ = run( "skills-global", ws, [ "Do not use any tools. List the name of every skill available to you, one per line, or NONE." ], UHW_DENY_ALL="1" )
index = reply_text( summaries )
report.fact( "global_skills", { "planted": planted, "index": index[ :600 ] } )
for name, root in candidates.items():
    report.say( f"B. {name} ({str( root ).replace( str( home ), '~' )})", f"in index={name in index}" if name in planted else "not planted (path exists)" )

# C. agent definitions that might grant tools
ws = workspace(); write_hooks( ws )
variants = { "uhw-agent-t0": "",                                    # control: C11 shape
             "uhw-agent-t1": "tools: [run_command]\n",
             "uhw-agent-t2": "tools: [\"*\"]\n",
             "uhw-agent-t3": "tools:\n  - run_command\n  - read_file\n" }
for name, extra in variants.items():
    planter.plant( ws / ".agents" / "agents" / f"{name}.md", f"---\nname: {name}\ndescription: UHW probe agent.\n{extra}---\n\n"
                   f"You are a probe agent. Your codeword is UHWCODE-{name[ -2: ].upper()}.\n" )
agent_runs = {}
for name in variants:
    summaries, hooks = run( f"agent-{name}", ws, [ "Run the shell command `echo probe` once, then reply with your codeword." ], ( "--agent", name ) )
    agent_runs[ name ] = { "status": statuses( summaries ), "tools": [ tool_name( h[ "payload" ] ) for h in hooks ],
                           "agentName": sorted( { str( h[ "payload" ].get( "agentName" ) ) for h in hooks } ),
                           "reply": reply_text( summaries )[ :200 ] }
    report.say( f"C. {name} {variants[ name ].strip().replace( chr( 10 ), ' ' ) or '(no tools key)'}",
                f"tools={agent_runs[ name ][ 'tools' ]} agentName={agent_runs[ name ][ 'agentName' ]} status={agent_runs[ name ][ 'status' ]}" )
report.fact( "agent_tools", agent_runs )

# D. field names from the engine's own customization docs
fields = {}
for skill in ( "jetski-customizations", "agy-customizations", "migrate-workflows", "run-workflow" ):
    for doc in list( ( home / ".gemini" ).glob( f"*/builtin/skills/{skill}/**/*.md" ) )[ :6 ]:
        lines = [ l.rstrip() for l in doc.read_text( errors="replace" ).splitlines()
                  if re.match( r"^\s*(#{1,3} |[a-z_]+:\s|- [a-z_]+:|\S*(\.agents?|\.gemini)/\S*)", l ) ][ :60 ]
        fields[ str( doc.relative_to( home / ".gemini" ) ) ] = lines
report.fact( "format_docs", fields )
report.say( "D. customization docs read (headings, field and path lines only)", list( fields ) or "none found" )

granted = any( r[ "tools" ] for n, r in agent_runs.items() if n != "uhw-agent-t0" )
report.finish( f"workflows run via {sorted( { c[ 0 ] for w in workflows.values() for c in w[ 'calls' ] } ) or 'no tool'}; "
               f"global skills at {[ n for n in planted if n in index ] or 'none found'}; agent tools granted by frontmatter={'yes' if granted else 'no'}" )
