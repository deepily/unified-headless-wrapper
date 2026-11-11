#!/usr/bin/env python3
"""
t31_switch_over.py — the Switch clock's first steps for one fleet host (D64, T31).

Three verbs, run in this order on each host where lupin is installed (today: the
development server and the test VM), as the persona account, while AH4L is still up
for the first two and stopped for the third:

    snapshot   read every live bridge file and write the roster snapshot
    check      the quiescence check: refuse until every live seat is drained
    archive    tar the AH4L state under ~/.claude into ~/.lupin/archive/, with a manifest

Nothing here writes anything the kernel owns (registry, inbox.json, the log). Dry run
is the default for `archive`; `--apply` writes the tarball. `--self-test` runs the
built-in tests against a scratch directory and touches nothing else.

    t31_switch_over.py snapshot <sessions_dir> --out ah4l-roster-<host>-<date>.json [--no-pid-check]
    t31_switch_over.py check    <snapshot.json> --lupin http://localhost:7999 --api-key-file ~/.lupin/fleet.key
    t31_switch_over.py archive  <snapshot.json> [--home ~] [--out-dir ~/.lupin/archive] [--apply]
    t31_switch_over.py --self-test

Standard library only.
"""
import argparse, hashlib, io, json, os, socket, sys, tarfile, tempfile, time, urllib.parse, urllib.request
from datetime import datetime, timezone
from pathlib  import Path

STALE_SECONDS   = 43200          # lupin's find_active_sessions default: twelve hours
ARCHIVE_MEMBERS = (              # relative to the home directory; a missing member is reported, not fatal
    ".claude/sessions", ".claude/mementos", ".claude/heartbeat-events", ".claude/CLAUDE.md",
    ".claude/settings.json", ".lupin/arbiter",
)

# ── snapshot ──────────────────────────────────────────────────────────────────

def canonical_persona_key( name ):
    """lupin's canonical_persona_key, reduced: lowercase, accents and punctuation stripped, single spaces."""
    import unicodedata
    if not name: return ""
    text = unicodedata.normalize( "NFKD", str( name ) )
    text = "".join( c for c in text if not unicodedata.combining( c ) ).lower()
    text = "".join( c if c.isalnum() or c == " " else " " for c in text )
    return " ".join( text.split() )

def pid_alive( pid ):
    try:
        os.kill( int( pid ), 0 ); return True
    except ( ProcessLookupError, ValueError, TypeError ):
        return False
    except PermissionError:
        return True

def read_json( path, default=None ):
    try:
        return json.loads( Path( path ).read_text( encoding="utf-8" ) )
    except ( OSError, ValueError ):
        return default

def ledger_cursor( sessions_dir, template, persona_id ):
    data = read_json( sessions_dir / template.format( session_id=persona_id ), {} ) or {}
    return data.get( "cursor_ts" )

def count_lines( path ):
    try:
        with open( path, "rb" ) as f: return sum( 1 for line in f if line.strip() )
    except OSError:
        return 0

def is_live( bridge, mtime, now, pid_check=True ):
    """lupin's liveness rule: pid alive, touched within twelve hours, a voice persona allocated."""
    if not bridge.get( "voice_persona" ):           return False, "no voice persona"
    if now - mtime > STALE_SECONDS:                 return False, "stale"
    if pid_check and not pid_alive( bridge.get( "cc_pid" ) ): return False, "pid dead"
    return True, ""

def snapshot_entry( sessions_dir, bridge_path, bridge ):
    """Requires: bridge is a parsed cc-*.json. Ensures: one roster entry; nothing is re-derived."""
    stable = bridge.get( "stable_session_id" ) or bridge.get( "session_id" ) or ""
    persona_id = stable[ :8 ]
    spawned_by = bridge.get( "spawned_by" ) or ""
    return {
        "persona_id"          : persona_id,
        "name"                : canonical_persona_key( bridge.get( "voice_persona" ) ),
        "name_as_written"     : bridge.get( "voice_persona" ),
        "role"                : bridge.get( "role" ),
        "project"             : bridge.get( "project" ),
        "model"               : bridge.get( "model" ),
        "workspace"           : bridge.get( "work_dir" ) or bridge.get( "worktree" ) or bridge.get( "cwd" ),
        "manager_id"          : spawned_by[ :8 ] or None,
        "manager_name"        : canonical_persona_key( bridge.get( "spawned_by_persona" ) ) or None,
        "topic"               : bridge.get( "session_topic" ),
        "last_interaction_at" : bridge.get( "last_interaction_at" ),
        "dm_cursor"           : ledger_cursor( sessions_dir, ".dm-inbox-hwm-{session_id}.json", persona_id ),
        "answers_cursor"      : ledger_cursor( sessions_dir, ".ask-answer-hwm-{session_id}.json", persona_id ),
        "buffer_lines"        : count_lines( sessions_dir / f"cc-buffer-{persona_id}.jsonl" ),
        "pid"                 : bridge.get( "cc_pid" ),
        "bridge"              : str( bridge_path ),
    }

def snapshot( sessions_dir, pid_check=True, now=None ):
    """Ensures: { host, taken_at, sessions_dir, live: [entries], skipped: [{bridge, why}] }; read-only."""
    sessions_dir = Path( sessions_dir ); now = now or time.time()
    live, skipped = [], []
    for path in sorted( sessions_dir.glob( "cc-*.json" ) ):
        if path.name.startswith( ( "cc-buffer-", "cc-stable-", "cc-test-" ) ): continue
        bridge = read_json( path )
        if not isinstance( bridge, dict ):
            skipped.append( { "bridge": str( path ), "why": "unreadable" } ); continue
        ok, why = is_live( bridge, path.stat().st_mtime, now, pid_check )
        if ok: live.append( snapshot_entry( sessions_dir, path, bridge ) )
        else:  skipped.append( { "bridge": str( path ), "why": why } )
    return { "host": socket.gethostname(), "taken_at": datetime.now( timezone.utc ).isoformat(),
             "sessions_dir": str( sessions_dir ), "live": live, "skipped": skipped }

# ── check ─────────────────────────────────────────────────────────────────────

def http_fetcher( base_url, api_key ):
    def fetch( path, params ):
        url = base_url.rstrip( "/" ) + path + ( "?" + urllib.parse.urlencode( params ) if params else "" )
        request = urllib.request.Request( url, headers={ "X-API-Key": api_key } )
        with urllib.request.urlopen( request, timeout=5 ) as response:
            return json.loads( response.read().decode( "utf-8" ) )
    return fetch

def _items( payload ):
    if isinstance( payload, list ): return payload
    for key in ( "items", "notifications", "messages", "answers", "rows" ):
        if isinstance( payload, dict ) and isinstance( payload.get( key ), list ): return payload[ key ]
    return []

def check_entry( entry, fetch ):
    """
    Ensures: { persona_id, name, quiet: bool, blocking: {…counts…}, informational: {…counts…} }.
    Blocking: a human line newer than the seat's last turn, a DM newer than its ledger cursor,
    an undrained buffer. Informational (they survive by name): owed answers, owed task rows.
    """
    job_id, name = entry[ "persona_id" ], entry[ "name" ]
    since = entry.get( "last_interaction_at" )
    voice = _items( fetch( "/api/notifications/undelivered", { "job_id": job_id, **( { "since": since } if since else {} ) } ) )
    dms   = [ m for m in _items( fetch( "/api/dm/list", { "job_id": job_id, "limit": 200 } ) )
              if not entry.get( "dm_cursor" ) or str( m.get( "created_at", "" ) ) > str( entry[ "dm_cursor" ] ) ]
    owed_answers = _items( fetch( "/api/notifications/answers-owed", { "persona": name } ) )
    owed_tasks   = _items( fetch( "/api/tasks", { "owner_persona": name, "status": "owed" } ) )
    blocking = { "voice_after_last_turn": len( voice ), "dms_after_cursor": len( dms ), "buffer_lines": entry.get( "buffer_lines", 0 ) }
    return { "persona_id": job_id, "name": name, "quiet": not any( blocking.values() ),
             "blocking": blocking, "informational": { "owed_answers": len( owed_answers ), "owed_tasks": len( owed_tasks ) } }

def check( snap, fetch ):
    """Ensures: { checked_at, seats: [...], quiet: all seats quiet }; the caller exits 1 when not quiet."""
    seats = [ check_entry( e, fetch ) for e in snap[ "live" ] ]
    return { "checked_at": datetime.now( timezone.utc ).isoformat(), "seats": seats, "quiet": all( s[ "quiet" ] for s in seats ) }

# ── archive ───────────────────────────────────────────────────────────────────

def sha256_of( path ):
    digest = hashlib.sha256()
    with open( path, "rb" ) as f:
        for chunk in iter( lambda: f.read( 1 << 20 ), b"" ): digest.update( chunk )
    return digest.hexdigest()

def archive_plan( home, extra_files=() ):
    """Ensures: ( present: [Path], missing: [str] ) for the fixed member list plus any extra files."""
    home = Path( home ); present, missing = [], []
    for member in ARCHIVE_MEMBERS:
        path = home / member
        ( present if path.exists() else missing ).append( path if path.exists() else member )
    present += [ Path( p ) for p in extra_files if Path( p ).exists() ]
    return present, missing

def archive( home, out_dir, stamp, extra_files=(), apply=False ):
    """
    Ensures: dry run returns the plan; with apply, writes ah4l-<stamp>.tar.gz and ah4l-<stamp>.manifest.json
    under out_dir and returns the manifest. ~/.claude/projects is never a member.
    """
    present, missing = archive_plan( home, extra_files )
    plan = { "stamp": stamp, "members": [ str( p ) for p in present ], "missing": missing, "applied": False }
    if not apply: return plan
    out_dir = Path( out_dir ); out_dir.mkdir( parents=True, exist_ok=True )
    tar_path, manifest_path = out_dir / f"ah4l-{stamp}.tar.gz", out_dir / f"ah4l-{stamp}.manifest.json"
    files = []
    with tarfile.open( tar_path, "w:gz" ) as tar:
        for member in present:
            arcname = os.path.relpath( member, home ) if str( member ).startswith( str( home ) ) else member.name
            tar.add( member, arcname=arcname, recursive=True )
            for path in ( [ member ] if member.is_file() else [ p for p in member.rglob( "*" ) if p.is_file() ] ):
                files.append( { "path": str( path ), "bytes": path.stat().st_size, "sha256": sha256_of( path ) } )
    manifest = { **plan, "applied": True, "tarball": str( tar_path ), "tarball_sha256": sha256_of( tar_path ),
                 "files": files, "written_at": datetime.now( timezone.utc ).isoformat() }
    manifest_path.write_text( json.dumps( manifest, indent=2 ), encoding="utf-8" )
    return manifest

# ── self-test ─────────────────────────────────────────────────────────────────

def self_test():
    with tempfile.TemporaryDirectory() as tmp:
        home = Path( tmp ); sessions = home / ".claude" / "sessions"; sessions.mkdir( parents=True )
        live_id, dead_id = "a1b2c3d4", "deadbeef"
        ( sessions / "cc-100.json" ).write_text( json.dumps( {
            "stable_session_id": live_id + "-0000-0000", "cc_pid": os.getpid(), "voice_persona": "María",
            "role": "manager", "project": "lupin", "spawned_by": "", "session_topic": "T31",
            "last_interaction_at": "2026-11-10T20:00:00+00:00", "cwd": tmp } ) )
        ( sessions / "cc-200.json" ).write_text( json.dumps( {
            "stable_session_id": dead_id + "-0000", "cc_pid": 2**22 + 7, "voice_persona": "Mr. Radio",
            "role": "worker", "spawned_by": live_id + "-0000-0000", "spawned_by_persona": "María" } ) )
        ( sessions / "cc-300.json" ).write_text( json.dumps( { "stable_session_id": "cafe0000", "cc_pid": os.getpid() } ) )
        ( sessions / f".dm-inbox-hwm-{live_id}.json" ).write_text( json.dumps( { "cursor_ts": "2026-11-10T19:00:00+00:00", "surfaced_ids": [ "m1" ] } ) )
        ( sessions / f"cc-buffer-{live_id}.jsonl" ).write_text( '{"id":"m9"}\n' )
        ( home / ".claude" / "mementos" ).mkdir(); ( home / ".claude" / "mementos" / "x.md" ).write_text( "memento" )

        # 1. snapshot: one live seat (own pid, voice persona), two skipped with reasons
        snap = snapshot( sessions )
        assert [ e[ "persona_id" ] for e in snap[ "live" ] ] == [ live_id ], snap
        assert sorted( s[ "why" ] for s in snap[ "skipped" ] ) == [ "no voice persona", "pid dead" ], snap[ "skipped" ]
        entry = snap[ "live" ][ 0 ]
        assert entry[ "name" ] == "maria" and entry[ "manager_id" ] is None and entry[ "dm_cursor" ].startswith( "2026-11-10T19" )
        assert entry[ "buffer_lines" ] == 1 and entry[ "topic" ] == "T31"
        # 2. snapshot without the pid check admits the dead seat and keeps its lineage
        snap2 = snapshot( sessions, pid_check=False )
        dead  = next( e for e in snap2[ "live" ] if e[ "persona_id" ] == dead_id )
        assert dead[ "manager_id" ] == live_id and dead[ "manager_name" ] == "maria" and dead[ "name" ] == "mr radio"
        # 3. check: the buffer line blocks; a drained seat is quiet; informational counts never block
        calls = []
        def fetch( path, params ):
            calls.append( ( path, params ) )
            if path == "/api/notifications/answers-owed": return { "items": [ { "id": "a1" } ] }
            if path == "/api/dm/list": return { "messages": [ { "id": "m1", "created_at": "2026-11-10T18:00:00+00:00" } ] }
            return []
        report = check( snap, fetch )
        assert report[ "quiet" ] is False and report[ "seats" ][ 0 ][ "blocking" ][ "buffer_lines" ] == 1
        assert report[ "seats" ][ 0 ][ "blocking" ][ "dms_after_cursor" ] == 0 and report[ "seats" ][ 0 ][ "informational" ][ "owed_answers" ] == 1
        assert any( p == "/api/notifications/undelivered" and q.get( "since" ) for p, q in calls )
        ( sessions / f"cc-buffer-{live_id}.jsonl" ).write_text( "" )
        assert check( snapshot( sessions ), fetch )[ "quiet" ] is True
        # 4. archive: dry run writes nothing; apply writes a tarball and a manifest with hashes; projects/ excluded
        ( home / ".claude" / "projects" ).mkdir(); ( home / ".claude" / "projects" / "t.jsonl" ).write_text( "transcript" )
        plan = archive( home, home / ".lupin" / "archive", "test-20261110" )
        assert plan[ "applied" ] is False and not ( home / ".lupin" / "archive" ).exists()
        assert ".claude/heartbeat-events" in plan[ "missing" ]
        manifest = archive( home, home / ".lupin" / "archive", "test-20261110", apply=True )
        names = [ f[ "path" ] for f in manifest[ "files" ] ]
        assert any( n.endswith( "cc-100.json" ) for n in names ) and any( n.endswith( "x.md" ) for n in names )
        assert not any( "projects" in n for n in names )
        with tarfile.open( manifest[ "tarball" ] ) as tar: members = tar.getnames()
        assert ".claude/sessions/cc-100.json" in members and ".claude/mementos/x.md" in members, members
        assert Path( manifest[ "tarball" ] ).exists() and len( manifest[ "tarball_sha256" ] ) == 64
        # 5. canonical key parity with lupin's examples
        assert canonical_persona_key( "María" ) == "maria" and canonical_persona_key( "Mr. Radio" ) == "mr radio"
    print( "t31_switch_over self-test: 5 groups, all passed" )

# ── main ──────────────────────────────────────────────────────────────────────

def main( argv=None ):
    parser = argparse.ArgumentParser( description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter )
    parser.add_argument( "--self-test", action="store_true" )
    sub = parser.add_subparsers( dest="verb" )
    s = sub.add_parser( "snapshot" ); s.add_argument( "sessions_dir" ); s.add_argument( "--out" ); s.add_argument( "--no-pid-check", action="store_true" )
    c = sub.add_parser( "check" );    c.add_argument( "snapshot" ); c.add_argument( "--lupin", default="http://localhost:7999" ); c.add_argument( "--api-key-file", required=True ); c.add_argument( "--out" )
    a = sub.add_parser( "archive" );  a.add_argument( "snapshot" ); a.add_argument( "--home", default=os.path.expanduser( "~" ) ); a.add_argument( "--out-dir", default=os.path.expanduser( "~/.lupin/archive" ) ); a.add_argument( "--apply", action="store_true" )
    args = parser.parse_args( argv )
    if args.self_test: return self_test()
    if args.verb == "snapshot":
        snap = snapshot( args.sessions_dir, pid_check=not args.no_pid_check )
        out  = args.out or f"ah4l-roster-{snap[ 'host' ]}-{datetime.now().strftime( '%Y%m%d' )}.json"
        Path( out ).write_text( json.dumps( snap, indent=2 ), encoding="utf-8" )
        print( f"snapshot: live={len( snap[ 'live' ] )} skipped={len( snap[ 'skipped' ] )} -> {out}" )
        for e in snap[ "live" ]: print( f"  {e[ 'persona_id' ]}  {e[ 'name' ]:<12} {e[ 'role' ] or '-':<10} manager={e[ 'manager_id' ] or '-'}  buffer={e[ 'buffer_lines' ]}" )
        return 0
    if args.verb == "check":
        snap   = read_json( args.snapshot ); key = Path( args.api_key_file ).read_text().strip()
        report = check( snap, http_fetcher( args.lupin, key ) )
        if args.out: Path( args.out ).write_text( json.dumps( report, indent=2 ), encoding="utf-8" )
        for s in report[ "seats" ]: print( f"  {s[ 'persona_id' ]}  {s[ 'name' ]:<12} {'quiet' if s[ 'quiet' ] else 'NOT QUIET'}  {s[ 'blocking' ]}  {s[ 'informational' ]}" )
        print( "check: quiet" if report[ "quiet" ] else "check: NOT QUIET — do not stop AH4L yet" )
        return 0 if report[ "quiet" ] else 1
    if args.verb == "archive":
        snap  = read_json( args.snapshot ) or {}
        stamp = f"{snap.get( 'host', socket.gethostname() )}-{datetime.now().strftime( '%Y%m%d' )}"
        extra = [ args.snapshot ] + [ p for p in ( Path( args.snapshot ).with_suffix( ".check.json" ), ) if p.exists() ]
        result = archive( args.home, args.out_dir, stamp, extra_files=extra, apply=args.apply )
        print( json.dumps( { k: v for k, v in result.items() if k != "files" }, indent=2 ) )
        print( "archive: written" if result[ "applied" ] else "archive: dry run (add --apply to write)" )
        return 0
    parser.print_help(); return 2

if __name__ == "__main__":
    sys.exit( main() or 0 )
