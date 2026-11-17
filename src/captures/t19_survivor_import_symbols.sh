#!/usr/bin/env bash
# t19_survivor_import_symbols.sh — for every file that survives the Delete clock and imports a
# module the Delete removes (the files t19_hook_import_survivors.sh counts), which names it takes
# from each removed module, where, and how the import is written. Row 66 of "Outstanding actions".
#
#   t19_survivor_import_symbols.sh <lupin checkout>
#   t19_survivor_import_symbols.sh --self-test
#
# Python's own parser reads each file, so an import named only in a comment or a string is not
# counted. Output, grouped by removed module, one line per import statement:
#
#   <module>  <class> <path>:<line>  <shape> in=<enclosing function>  <name>=<uses> ...
#
# class  keep      the file is a Keep row of the inventory script
#        unlisted  the inventory script has no row for the file
#        moved     a module of the tree itself that the list keeps ("Keep and import"): it moves out at
#                  the Move clock, so an import of a removed sibling fails the same way. The Delete
#                  check of t19_hook_import_survivors.sh does not read these files.
# shape  top            a module-level import: the file fails to import once the module is gone
#        top-guarded    module level, inside a try whose handler catches the import failure
#        lazy           inside a function: only that call path fails
#        lazy-guarded   inside a function and inside such a try
# name=uses  the imported name and how many times the file then reads it; for a module imported
#            whole (`from …lib import heartbeat_hold`), the attributes read off it instead.
#
# Then one summary line per module (files, statements, distinct names) and one per file, and a
# last section asking the same of the Python files the list deletes outside the tree.
# Read-only, zero tokens. Output is meant for
# src/captures/out/t19-survivor-import-symbols-<host>-<date>.txt.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
exec python3 - "$here/t19_switch_over_inventory.sh" "$@" <<'PYTHON'
import ast, os, re, subprocess, sys

TREE      = "src/lupin_cli/claude_code"
PACKAGE   = "lupin_cli.claude_code"
TEST_PATH = re.compile( r"(^|/)tests?/|(^|/)test_[^/]*\.py$|_test\.py$" )
CATCHES   = { "ImportError", "ModuleNotFoundError", "Exception", "BaseException" }

def inventory_rows( script_text ):
    rows, inside = [ ], False
    for line in script_text.splitlines():
        if line.startswith( "rows=$(cat" ): inside = True; continue
        if line.strip() == "ROWS": inside = False
        if inside and line.count( "|" ) >= 3: rows.append( tuple( line.split( "|", 3 ) ) )
    return rows

def classify_file( path, rows ):
    stem = os.path.splitext( os.path.basename( path ) )[ 0 ]
    for kind, _clock, disposition, target in rows:
        hit = ( kind == "file" and target == path ) or ( kind == "dir" and path.startswith( target + "/" ) ) \
              or ( kind == "symbol" and target == stem )
        if not hit: continue
        if disposition == "Delete": return "delete"
        if disposition.startswith( "Keep" ): return "keep"
    return "unlisted"

def kept_modules( rows ):
    return { os.path.splitext( os.path.basename( target ) )[ 0 ]
             for kind, _clock, disposition, target in rows
             if kind == "file" and disposition == "Keep and import" and target.startswith( TREE + "/" ) }

def handler_catches( handler ):
    if handler.type is None: return True
    kinds = handler.type.elts if isinstance( handler.type, ast.Tuple ) else [ handler.type ]
    return any( isinstance( kind, ast.Name ) and kind.id in CATCHES for kind in kinds )

def imports_of( text ):
    """A list of ( line, module, shape, { local name: uses } ) for each import of the tree in text.

    module is the tree module's own name (the last dotted part); a whole-module import reports the
    attributes read off its local name, written `.attribute`.
    """
    tree  = ast.parse( text )
    loads, attributes = { }, { }
    for node in ast.walk( tree ):
        if isinstance( node, ast.Name ) and isinstance( node.ctx, ast.Load ): loads[ node.id ] = loads.get( node.id, 0 ) + 1
        if isinstance( node, ast.Attribute ) and isinstance( node.value, ast.Name ):
            attributes.setdefault( node.value.id, { } )
            attributes[ node.value.id ][ node.attr ] = attributes[ node.value.id ].get( node.attr, 0 ) + 1
    found = [ ]

    def whole( local ):
        read = attributes.get( local, { } )
        return { "." + name: count for name, count in sorted( read.items() ) } or { "(module, never read)": 0 }

    def visit( node, in_function, guarded, owner="<module>" ):
        for child in ast.iter_child_nodes( node ):
            child_function, child_guarded, child_owner = in_function, guarded, owner
            if isinstance( child, ( ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda ) ): child_function = True
            if isinstance( child, ( ast.FunctionDef, ast.AsyncFunctionDef ) ) and not in_function: child_owner = child.name
            if isinstance( node, ast.Try ) and child in node.body and any( handler_catches( handler ) for handler in node.handlers ):
                child_guarded = True
            shape = ( "lazy" if child_function else "top" ) + ( "-guarded" if child_guarded else "" ) + " in=" + child_owner
            if isinstance( child, ast.ImportFrom ) and child.level == 0 and child.module and \
               ( child.module == PACKAGE or child.module.startswith( PACKAGE + "." ) ):
                last = child.module.split( "." )[ -1 ]
                if last in ( "claude_code", "hooks", "lib" ):
                    for alias in child.names: found.append( ( child.lineno, alias.name, shape, whole( alias.asname or alias.name ) ) )
                else:
                    found.append( ( child.lineno, last, shape,
                                    { alias.name: loads.get( alias.asname or alias.name, 0 ) for alias in child.names } ) )
            elif isinstance( child, ast.Import ):
                for alias in child.names:
                    if alias.name == PACKAGE or alias.name.startswith( PACKAGE + "." ):
                        found.append( ( child.lineno, alias.name.split( "." )[ -1 ], shape,
                                        whole( alias.asname ) if alias.asname else { "(dotted, no alias)": 0 } ) )
            visit( child, child_function, child_guarded, child_owner )

    visit( tree, False, False )
    return sorted( found )

def outside_tree( checkout, rows ):
    """The same question for the Python files the list deletes outside the tree: which survivors import them."""
    doomed = { }                                        # dotted module name -> path
    for kind, _clock, disposition, target in rows:
        if not ( disposition == "Delete" or ( disposition == "Rename" and kind == "file" ) ) or target == TREE or target.startswith( TREE + "/" ): continue
        if kind == "file" and target.endswith( ".py" ): doomed[ target[ 4:-3 ].replace( "/", "." ) ] = target
        if kind == "dir":
            for directory, _directories, files in os.walk( os.path.join( checkout, target ) ):
                for name in files:
                    if name.endswith( ".py" ):
                        path = os.path.relpath( os.path.join( directory, name ), checkout )
                        doomed[ path[ 4:-3 ].replace( "/", "." ) ] = path
    wanted = { }
    for directory, directories, files in os.walk( os.path.join( checkout, "src" ) ):
        directories[ : ] = [ name for name in directories if name not in ( "node_modules", "__pycache__", ".git" ) ]
        for name in files:
            if not name.endswith( ".py" ): continue
            path = os.path.relpath( os.path.join( directory, name ), checkout )
            if path.startswith( TREE + "/" ) or TEST_PATH.search( path ) or path in doomed.values(): continue
            kind = classify_file( path, rows )
            if kind == "delete": continue
            try: tree = ast.parse( open( os.path.join( checkout, path ), encoding="utf-8", errors="replace" ).read() )
            except ( OSError, SyntaxError ): continue
            for node in ast.walk( tree ):
                names = [ ]
                if isinstance( node, ast.ImportFrom ) and node.module and node.level == 0:
                    names = [ node.module ] + [ node.module + "." + alias.name for alias in node.names ]
                elif isinstance( node, ast.Import ): names = [ alias.name for alias in node.names ]
                for dotted in names:
                    if dotted in doomed: wanted.setdefault( doomed[ dotted ], set() ).add( ( kind, path ) )
    print( "\n## deleted Python files outside the tree that a surviving file imports" )
    for target in sorted( wanted ):
        print( f"{target:<58} <- " + " ".join( f"{path}({kind})" for kind, path in sorted( wanted[ target ], key=lambda item: item[ 1 ] ) ) )
    survivors = { path for found in wanted.values() for _kind, path in found }
    print( f"# deleted Python files outside the tree: {len( doomed )} · imported by a survivor: {len( wanted )} · surviving files that import one: {len( survivors )}" )

def self_test():
    sample = (
        "from lupin_cli.claude_code.hooks.lib.session_bridge import find, get as g\n"
        "from lupin_cli.claude_code.hooks.lib import heartbeat_hold\n"
        "# from lupin_cli.claude_code.hooks.lib.no import no\n"
        "x = '''\nfrom lupin_cli.claude_code.hooks.lib.no import no\n'''\n"
        "try:\n    from lupin_cli.claude_code.hooks.lib.a import b\nexcept ImportError:\n    b = None\n"
        "try:\n    from lupin_cli.claude_code.hooks.lib.c import d\nexcept ValueError:\n    pass\n"
        "def f():\n    import lupin_cli.claude_code.hooks.lib.e as e\n    try:\n        from lupin_cli.claude_code.hooks.lib.h import i\n    except Exception:\n        return None\n"
        "    return find( 1 ), find( 2 ), g, heartbeat_hold.base(), heartbeat_hold.base, e.z, i\n"
        "from other.package import no\n"
    )
    got = imports_of( sample )
    checks = [
        ( len( got ), 6 ),
        ( got[ 0 ], ( 1, "session_bridge", "top in=<module>", { "find": 2, "get": 1 } ) ),
        ( got[ 1 ], ( 2, "heartbeat_hold", "top in=<module>", { ".base": 2 } ) ),
        ( got[ 2 ][ 1: 3 ], ( "a", "top-guarded in=<module>" ) ),
        ( got[ 3 ][ 1: 3 ], ( "c", "top in=<module>" ) ),
        ( got[ 4 ], ( 16, "e", "lazy in=f", { ".z": 1 } ) ),
        ( got[ 5 ], ( 18, "h", "lazy-guarded in=f", { "i": 1 } ) ),
        ( [ row[ 1 ] for row in got ].count( "no" ), 0 ),
        ( imports_of( "from lupin_cli.claude_code.hooks.lib import a\n" )[ 0 ][ 3 ], { "(module, never read)": 0 } ),
    ]
    failed = [ ( number, value, expected ) for number, ( value, expected ) in enumerate( checks, 1 ) if value != expected ]
    for number, value, expected in failed: print( f"FAIL case {number}: got {value!r}, expected {expected!r}" )
    print( f"self-test: {len( checks ) - len( failed )} of {len( checks )} cases pass" )
    return 1 if failed else 0

def main( inventory_script, arguments ):
    if not arguments: print( "usage: t19_survivor_import_symbols.sh <lupin checkout> | --self-test", file=sys.stderr ); return 2
    if arguments[ 0 ] == "--self-test": return self_test()
    checkout = arguments[ 0 ]
    if not os.path.isdir( os.path.join( checkout, TREE ) ): print( f"no {TREE} under {checkout}", file=sys.stderr ); return 2
    rows   = inventory_rows( open( inventory_script ).read() )
    kept   = kept_modules( rows )
    commit = subprocess.run( [ "git", "-C", checkout, "rev-parse", "--short", "HEAD" ], capture_output=True, text=True ).stdout.strip()
    stamp  = subprocess.run( [ "date", "+%Y-%m-%dT%H:%M%z" ], capture_output=True, text=True, env={ **os.environ, "TZ": "America/New_York" } ).stdout.strip()
    print( f"# t19 survivor import symbols · checkout={checkout} · commit={commit} · inventory rows={len( rows )} · kept modules={len( kept )} · {stamp}" )

    by_module, by_file, unparsed = { }, { }, [ ]
    for directory, directories, files in os.walk( os.path.join( checkout, "src" ) ):
        directories[ : ] = [ name for name in directories if name not in ( "node_modules", "__pycache__", ".git" ) ]
        for name in files:
            if not name.endswith( ".py" ): continue
            path = os.path.relpath( os.path.join( directory, name ), checkout )
            if TEST_PATH.search( path ): continue
            inside = path.startswith( TREE + "/" )
            if inside and os.path.splitext( name )[ 0 ] not in kept: continue
            kind = "moved" if inside else classify_file( path, rows )
            if kind == "delete": continue
            try: text = open( os.path.join( checkout, path ), encoding="utf-8", errors="replace" ).read()
            except OSError: continue
            if PACKAGE not in text: continue
            try: found = imports_of( text )
            except SyntaxError as error: unparsed.append( ( path, str( error ) ) ); continue
            for line, module, shape, names in found:
                if module in kept: continue
                by_module.setdefault( module, [ ] ).append( ( kind, path, line, shape, names ) )
                by_file.setdefault( ( kind, path ), [ ] ).append( ( module, shape.split( " in=" )[ 0 ] ) )

    for module in sorted( by_module, key=lambda module: ( -len( { row[ 1 ] for row in by_module[ module ] } ), module ) ):
        entries = sorted( by_module[ module ], key=lambda row: ( row[ 1 ], row[ 2 ] ) )
        names   = { }
        for _kind, path, _line, _shape, found in entries:
            for name in found: names.setdefault( name, set() ).add( path )
        print( f"\n## {module} · files={len( { row[ 1 ] for row in entries } )} statements={len( entries )} distinct names={len( names )}" )
        for kind, path, line, shape, found in entries:
            print( f"{module:<24} {kind:<8} {path}:{line}  {shape:<34}  " + " ".join( f"{name}={uses}" for name, uses in found.items() ) )
        print( "#   names (files): " + " ".join( f"{name}({len( paths )})" for name, paths in sorted( names.items(), key=lambda item: ( -len( item[ 1 ] ), item[ 0 ] ) ) ) )

    print( "\n## per file" )
    hard = 0
    for ( kind, path ), found in sorted( by_file.items() ):
        shapes  = sorted( { shape for _module, shape in found } )
        hard   += "top" in shapes
        print( f"{kind:<8} {path:<62} modules={','.join( sorted( { module for module, _shape in found } ) )}  shapes={','.join( shapes )}" )
    print( f"\n# surviving files importing a removed module: {len( by_file )} "
           f"(keep={sum( 1 for kind, _path in by_file if kind == 'keep' )} unlisted={sum( 1 for kind, _path in by_file if kind == 'unlisted' )} moved={sum( 1 for kind, _path in by_file if kind == 'moved' )})" )
    print( f"# files with at least one unguarded module-level import (fail at import after the Delete): {hard}" )
    print( f"# removed modules wanted: {len( by_module )} · import statements: {sum( len( entries ) for entries in by_module.values() )}" )
    for path, error in unparsed: print( f"# NOT PARSED {path}: {error}" )
    outside_tree( checkout, rows )
    return 0

sys.exit( main( sys.argv[ 1 ], sys.argv[ 2: ] ) )
PYTHON
