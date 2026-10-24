"""
capture_lib.py -- shared plumbing for the Python captures C11, C12 and C14 (Jetski family).

Requires:
    - drive.py, probe_hook.py and probe_mcp.py beside this file
Ensures:
    - engine_argv() is the persona launch shape: stream-json, skip-permissions, AGY's --print-timeout 0,
      Jetski's --use_ls_chrome_devtools_mcp=false, and --model when MODEL is set
    - Planter removes everything it created, on normal exit, exception, SIGINT or SIGTERM, and never touches an
      existing file
"""
import atexit, json, os, shutil, signal, subprocess, sys, tempfile, time
from pathlib import Path

HERE = Path( __file__ ).resolve().parent
PY   = sys.executable


def engine_argv( binary, *extra ):
    argv = [ binary, "--input-format", "stream-json", "--output-format", "stream-json", "--dangerously-skip-permissions" ]
    if binary == "agy":    argv += [ "--print-timeout", "0" ]
    if binary == "jetski": argv += [ "--use_ls_chrome_devtools_mcp=false" ]
    if os.environ.get( "MODEL" ): argv += [ "--model", os.environ[ "MODEL" ] ]
    return argv + list( extra )


def new_out( label ):
    out = HERE / "out" / f"{label}-{time.strftime( '%Y%m%dT%H%M%S' )}"
    out.mkdir( parents=True )
    print( f"output: {out}", flush=True )
    return out


def version( binary, out ):
    text = run_quiet( [ binary, "--version" ], 30 )
    ( out / "version.txt" ).write_text( text )
    return text.strip().splitlines()[ 0 ] if text.strip() else "unknown"


def run_quiet( argv, seconds, cwd=None ):
    """stdout+stderr of a short non-interactive command; never raises."""
    try:
        done = subprocess.run( argv, cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=seconds )
        return done.stdout + done.stderr
    except ( subprocess.TimeoutExpired, OSError ) as problem:
        return f"<{type( problem ).__name__}: {problem}>"


def workspace():
    """A throwaway git repo: persona workspaces are worktrees, and some engines look for instructions up to the repo root."""
    path = Path( tempfile.mkdtemp( prefix="uhw-ws-" ) )
    if shutil.which( "git" ):
        subprocess.run( [ "git", "init", "-q", str( path ) ], capture_output=True )
    return path


def write_hooks( ws ):
    """Project-level hooks (format A, measured on both binaries). The hook reads its log path and mode from the
    environment it inherits from the engine (measured in C1/C3), so drive( env=... ) sets them."""
    entry  = lambda event: [ { "matcher": "*", "hooks": [ { "type": "command", "timeout": 10,
                               "command": f"{PY} {HERE / 'probe_hook.py'} {event}" } ] } ]
    ( ws / ".agents" ).mkdir( parents=True, exist_ok=True )
    ( ws / ".agents" / "hooks.json" ).write_text( json.dumps( { "uhw-probe": { "PreToolUse": entry( "pre_tool" ),
                                                                              "PostToolUse": entry( "post_tool" ) } }, indent=1 ) )


def drive( argv, ws, frames, turns, timeout=600, **env ):
    """One engine process, one or more turns, with env added to the engine's environment (hooks and MCP servers
    inherit it). Returns the per-turn summaries drive.py printed."""
    command = [ PY, str( HERE / "drive.py" ), "--family", "jetski", "--cwd", str( ws ), "--out", str( frames ),
                "--turn-timeout", str( timeout ) ]
    for turn in turns:
        command += [ "--turn", turn ]
    done = subprocess.run( command + [ "--" ] + argv, capture_output=True, text=True,
                           env={ **os.environ, **{ k: str( v ) for k, v in env.items() } } )
    summaries = [ json.loads( line ) for line in done.stdout.splitlines() if line.startswith( "{" ) ]
    Path( str( frames ) + ".summary" ).write_text( done.stdout )
    return [ s for s in summaries if "turn" in s ]


def jsonl( path ):
    path = Path( path )
    return [ json.loads( line ) for line in path.read_text().splitlines() if line.strip() ] if path.exists() else []


def tool_name( payload ):
    call = payload.get( "toolCall" ) or payload.get( "tool_call" ) or {}
    return call.get( "name" ) or payload.get( "tool_name" )


def tool_args( payload ):
    call = payload.get( "toolCall" ) or payload.get( "tool_call" ) or {}
    return call.get( "args" ) or payload.get( "tool_input" ) or {}


def reply_text( summaries ):
    return " ".join( r.get( "text", "" ) for s in summaries for r in s.get( "results", [] ) )


def statuses( summaries ):
    return [ r.get( "status" ) for s in summaries for r in s.get( "results", [] ) ] or [ "no result" ]


class Planter:
    """Creates files for a capture and removes exactly what it created. Global paths are only planted where absent."""

    def __init__( self ):
        self.created = []
        atexit.register( self.cleanup )
        for number in ( signal.SIGINT, signal.SIGTERM ):
            signal.signal( number, lambda *_: sys.exit( 130 ) )

    def plant( self, path, text ):
        path = Path( path ).expanduser()
        if path.exists():
            return False
        top = path
        while not top.parent.exists():
            top = top.parent
        path.parent.mkdir( parents=True, exist_ok=True )
        path.write_text( text )
        self.created.append( top )
        return True

    def cleanup( self ):
        for top in reversed( self.created ):
            if top.is_dir(): shutil.rmtree( top, ignore_errors=True )
            elif top.exists(): top.unlink()
        self.created = []


class Report:
    """verdict.txt holds the lines to paste back; facts.json holds the raw facts behind them."""

    def __init__( self, out, label ):
        self.out, self.label, self.lines, self.facts = out, label, [], {}

    def say( self, key, value ):
        self.lines.append( f"{key:<46} {value}" )
        print( self.lines[ -1 ], flush=True )

    def fact( self, key, value ):
        self.facts[ key ] = value

    def finish( self, verdict ):
        self.lines.append( f"VERDICT {self.label}: {verdict}" )
        print( self.lines[ -1 ], flush=True )
        ( self.out / "verdict.txt" ).write_text( "\n".join( self.lines ) + "\n" )
        ( self.out / "facts.json" ).write_text( json.dumps( self.facts, indent=1, default=str ) )
