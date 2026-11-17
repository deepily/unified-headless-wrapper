#!/usr/bin/env bash
# t19_hook_import_survivors.sh — which files outside the hooks tree import it, and what the
# switch-over list of record (T19 spec Section 5, in machine form in t19_switch_over_inventory.sh)
# says happens to each importing file and to each imported module.
#
#   t19_hook_import_survivors.sh <lupin checkout> [--check]
#   t19_hook_import_survivors.sh --self-test
#
# The tree src/lupin_cli/claude_code is deleted whole at the Delete clock, except the modules the
# list marks "Keep and import", which move out of it at the Move clock. A file outside the tree
# that imports a module that is deleted, and is not itself deleted, fails at import after Delete.
# For every importing file outside the tree (tests left out) the script prints one line:
#
#   <class> <import lines> <path>  gone: <modules deleted>  kept: <modules that move>
#
# class is  delete    the file is a Delete row (file row, a dir row above it, or a symbol row
#                     equal to its name), so its imports leave with it
#           keep      the file is a Keep row of the inventory script; it survives
#           unlisted  the inventory script has no row for the file; it survives by default
#           moved     a module of the tree that the list keeps ("Keep and import"); it moves out at
#                     the Move clock, so a deleted sibling it imports fails it the same way
#
# Then, for the Python files the list deletes outside the tree (file rows, and every file under a
# dir row), one line per surviving file that imports one:
#
#   outside <class> <path>  gone files: <deleted files it imports>
#
# Both were added on 2026-11-17 (row 66 of "Outstanding actions", ruling 9).
#
# With --check the script exits 1 while any surviving file imports a deleted module or file: the Delete
# clock's condition (row 28 of "Outstanding actions", ruled 2026-11-16), which
# t19_switch_over_inventory.sh --clock delete runs.
#
# Read-only, zero tokens. Output is meant for
# src/captures/out/t19-hook-import-survivors-<host>-<date>.txt.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
exec python3 - "$here/t19_switch_over_inventory.sh" "$@" <<'PYTHON'
import ast, os, re, subprocess, sys, datetime

TREE         = "src/lupin_cli/claude_code"
IMPORT_LINE  = re.compile( r"^\s*(from|import)\s+lupin_cli\.claude_code(\.[\w.]+)?(\s+import\s+(.*))?" )
TEST_PATH    = re.compile( r"(^|/)tests?/|(^|/)test_[^/]*\.py$|_test\.py$" )

def inventory_rows( script_text ):
    """The rows between `rows=$(cat <<'ROWS'` and `ROWS`, as ( kind, clock, disposition, target )."""
    rows, inside = [ ], False
    for line in script_text.splitlines():
        if line.startswith( "rows=$(cat" ): inside = True; continue
        if line.strip() == "ROWS": inside = False
        if inside and line.count( "|" ) >= 3: rows.append( tuple( line.split( "|", 3 ) ) )
    return rows

def classify_file( path, rows ):
    """delete, keep or unlisted, for a path relative to the checkout."""
    stem = os.path.splitext( os.path.basename( path ) )[ 0 ]
    for kind, _clock, disposition, target in rows:
        hit = ( kind == "file" and target == path ) or ( kind == "dir" and path.startswith( target + "/" ) ) \
              or ( kind == "symbol" and target == stem )
        if not hit: continue
        if disposition == "Delete": return "delete"
        if disposition.startswith( "Keep" ): return "keep"
    return "unlisted"

def kept_modules( rows ):
    """Names of the tree's modules that the list keeps (they move out at the Move clock)."""
    return { os.path.splitext( os.path.basename( target ) )[ 0 ]
             for kind, _clock, disposition, target in rows
             if kind == "file" and disposition == "Keep and import" and target.startswith( TREE + "/" ) }

def imported_modules( text ):
    """( import line count, set of module names under the tree that the text imports )."""
    count, modules, lines = 0, set(), text.splitlines()
    index = 0
    while index < len( lines ):
        match = IMPORT_LINE.match( lines[ index ] )
        index += 1
        if not match: continue
        count += 1
        dotted = ( match.group( 2 ) or "" ).strip( "." )
        last   = dotted.split( "." )[ -1 ] if dotted else ""
        if last in ( "", "hooks", "lib" ):
            # `from …hooks.lib import a, b` (possibly parenthesized over several lines): the names are the modules
            names = match.group( 4 ) or ""
            while "(" in names and ")" not in names and index < len( lines ):
                names += " " + lines[ index ]; index += 1
            names = re.sub( r"\bas\s+\w+", "", names.split( "#" )[ 0 ] )      # an alias is not a module
            for name in re.split( r"[,\s()]+", names ):
                if name.isidentifier(): modules.add( name )
        else:
            modules.add( last )
    return count, modules

def doomed_outside( rows, python_files_under ):
    """Dotted module name -> path, for every Python file the list deletes outside the tree.

    python_files_under( directory ) yields the Python paths below a `dir` row, relative to the checkout.
    """
    doomed = { }
    for kind, _clock, disposition, target in rows:
        if disposition != "Delete" or target == TREE or target.startswith( TREE + "/" ): continue
        paths = [ target ] if kind == "file" and target.endswith( ".py" ) else list( python_files_under( target ) ) if kind == "dir" else [ ]
        for path in paths: doomed[ path[ len( "src/" ):-len( ".py" ) ].replace( "/", "." ) ] = path
    return doomed

def dotted_imports( text ):
    """Every dotted name the text imports, read by Python's parser: `a.b`, and `a.b.c` for `from a.b import c`."""
    names = set()
    for node in ast.walk( ast.parse( text ) ):
        if isinstance( node, ast.ImportFrom ) and node.module and node.level == 0:
            names.add( node.module ); names.update( node.module + "." + alias.name for alias in node.names )
        elif isinstance( node, ast.Import ): names.update( alias.name for alias in node.names )
    return names

def self_test():
    rows = inventory_rows( "x\nrows=$(cat <<'ROWS'\ndir|delete|Delete|src/gone_tree\nfile|delete|Delete|src/a.py\nfile|move|Keep|src/b.py\n"
                           "file|move|Keep and import|src/lupin_cli/claude_code/hooks/lib/kept_one.py\nsymbol|delete|Delete|reaper\nsymbol|delete|Delete|send-keys\nROWS\n)\nfile|x|Delete|src/not_a_row.py\n" )
    checks = [
        ( len( rows ), 6 ),
        ( classify_file( "src/a.py", rows ), "delete" ),
        ( classify_file( "src/gone_tree/x/y.py", rows ), "delete" ),
        ( classify_file( "src/gone_tree_other/z.py", rows ), "unlisted" ),
        ( classify_file( "src/b.py", rows ), "keep" ),
        ( classify_file( "src/deep/reaper.py", rows ), "delete" ),
        ( classify_file( "src/not_a_row.py", rows ), "unlisted" ),
        ( kept_modules( rows ), { "kept_one" } ),
        ( imported_modules( "from lupin_cli.claude_code.hooks.lib.session_bridge import a, b\n" ), ( 1, { "session_bridge" } ) ),
        ( imported_modules( "    from lupin_cli.claude_code.hooks.lib import kept_one, other as o\n" ), ( 1, { "kept_one", "other" } ) ),
        ( imported_modules( "from lupin_cli.claude_code.hooks.lib import (\n    one,\n    two,\n)\nx = 1\n" ), ( 1, { "one", "two" } ) ),
        ( imported_modules( "import lupin_cli.claude_code.hooks.lib.main_tree as m\n# from lupin_cli.claude_code import no\nfrom lupin_cli.other import no\n" ), ( 1, { "main_tree" } ) ),
        ( bool( TEST_PATH.search( "src/tests/unit/x.py" ) ), True ), ( bool( TEST_PATH.search( "src/a/test_x.py" ) ), True ),
        ( bool( TEST_PATH.search( "src/a/latest_run.py" ) ), False ),
        ( doomed_outside( rows, lambda directory: [ directory + "/x/y.py" ] ), { "gone_tree.x.y": "src/gone_tree/x/y.py", "a": "src/a.py" } ),
        ( doomed_outside( [ ( "dir", "delete", "Delete", TREE ), ( "file", "move", "Keep", "src/b.py" ), ( "file", "delete", "Delete", "src/c.sh" ) ], lambda directory: [ "src/no.py" ] ), { } ),
        ( dotted_imports( "from a.b import c, d as e\nimport f.g\n# import no\ndef h():\n    from i import j\nfrom . import k\n" ), { "a.b", "a.b.c", "a.b.d", "f.g", "i", "i.j" } ),
    ]
    failed = [ ( number, got, expected ) for number, ( got, expected ) in enumerate( checks, 1 ) if got != expected ]
    for number, got, expected in failed: print( f"FAIL case {number}: got {got!r}, expected {expected!r}" )
    print( f"self-test: {len( checks ) - len( failed )} of {len( checks )} cases pass" )
    return 1 if failed else 0

def main( inventory_script, arguments ):
    if not arguments: print( "usage: t19_hook_import_survivors.sh <lupin checkout> [--check] | --self-test", file=sys.stderr ); return 2
    if arguments[ 0 ] == "--self-test": return self_test()
    checkout = arguments[ 0 ]
    if not os.path.isdir( os.path.join( checkout, TREE ) ): print( f"no {TREE} under {checkout}", file=sys.stderr ); return 2
    rows   = inventory_rows( open( inventory_script ).read() )
    kept   = kept_modules( rows )
    commit = subprocess.run( [ "git", "-C", checkout, "rev-parse", "--short", "HEAD" ], capture_output=True, text=True ).stdout.strip()
    stamp  = subprocess.run( [ "date", "+%Y-%m-%dT%H:%M%z" ], capture_output=True, text=True, env={ **os.environ, "TZ": "America/New_York" } ).stdout.strip()
    print( f"# t19 hook-import survivors · checkout={checkout} · commit={commit} · inventory rows={len( rows )} · kept modules={len( kept )} · {stamp}" )

    def python_files_under( target ):
        for directory, _directories, files in os.walk( os.path.join( checkout, target ) ):
            for name in files:
                if name.endswith( ".py" ): yield os.path.relpath( os.path.join( directory, name ), checkout )
    doomed = doomed_outside( rows, python_files_under )

    found, outside = [ ], [ ]
    for directory, directories, files in os.walk( os.path.join( checkout, "src" ) ):
        directories[ : ] = [ name for name in directories if name not in ( "node_modules", "__pycache__", ".git" ) ]
        for name in files:
            if not name.endswith( ".py" ): continue
            path = os.path.relpath( os.path.join( directory, name ), checkout )
            if TEST_PATH.search( path ): continue
            inside = path.startswith( TREE + "/" )
            if inside and os.path.splitext( name )[ 0 ] not in kept: continue      # of the tree, only the modules that move out are read
            try: text = open( os.path.join( checkout, path ), encoding="utf-8", errors="replace" ).read()
            except OSError: continue
            kind = "moved" if inside else classify_file( path, rows )
            count, modules = imported_modules( text )
            if count and not ( inside and not modules - kept ):
                found.append( ( kind, count, path, sorted( modules - kept ), sorted( modules & kept ) ) )
            if kind != "delete" and path not in doomed.values():
                try: wanted = sorted( { doomed[ dotted ] for dotted in dotted_imports( text ) if dotted in doomed } )
                except SyntaxError: wanted = [ ]
                if wanted: outside.append( ( kind, path, wanted ) )

    totals      = { "delete": 0, "keep": 0, "unlisted": 0, "moved": 0 }
    broken      = { "keep": 0, "unlisted": 0, "moved": 0 }   # survivors importing at least one deleted module
    gone_demand = { }                                   # deleted module -> surviving files that import it
    for kind, count, path, gone, moving in sorted( found, key=lambda row: ( row[ 0 ], row[ 2 ] ) ):
        totals[ kind ] += 1
        if kind != "delete" and gone:
            broken[ kind ] += 1
            for module in gone: gone_demand[ module ] = gone_demand.get( module, 0 ) + 1
        print( f"{kind:<9}{count:>3} {path:<62} gone: {','.join( gone ) or '-':<60} kept: {','.join( moving ) or '-'}" )
    print( f"# files={len( found )} delete={totals[ 'delete' ]} keep={totals[ 'keep' ]} unlisted={totals[ 'unlisted' ]} moved={totals[ 'moved' ]}" )
    print( f"# survivors that import a deleted module: keep={broken[ 'keep' ]} unlisted={broken[ 'unlisted' ]} moved={broken[ 'moved' ]} total={sum( broken.values() )}" )
    print( "# deleted modules still imported by survivors (module=files): " + " ".join( f"{module}={files}" for module, files in sorted( gone_demand.items(), key=lambda item: ( -item[ 1 ], item[ 0 ] ) ) ) )
    for kind, path, wanted in sorted( outside, key=lambda row: row[ 1 ] ):
        print( f"outside  {kind:<9}{path:<62} gone files: {','.join( wanted )}" )
    print( f"# deleted Python files outside the tree={len( doomed )} · imported by a survivor={len( { target for _kind, _path, wanted in outside for target in wanted } )} · survivors that import one={len( outside )}" )
    return 1 if "--check" in arguments[ 1: ] and ( sum( broken.values() ) or outside ) else 0

sys.exit( main( sys.argv[ 1 ], sys.argv[ 2: ] ) )
PYTHON
