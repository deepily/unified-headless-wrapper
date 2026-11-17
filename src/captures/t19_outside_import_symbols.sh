#!/usr/bin/env bash
# t19_outside_import_symbols.sh — for every file that survives the Delete clock and imports a
# Python file the list deletes, or renames, outside the hooks tree (the lines `outside` of
# t19_hook_import_survivors.sh), which names it takes from each deleted file, where, and how the
# import is written. Row 76 of "Outstanding actions".
#
#   t19_outside_import_symbols.sh <lupin checkout>
#   t19_outside_import_symbols.sh --self-test
#
# Python's own parser reads each file, so an import named only in a comment or a string is not
# counted. Output, grouped by deleted file, one line per import statement:
#
#   <deleted file>  <class> <path>:<line>  <shape> in=<enclosing function>  <name>=<uses> ...
#
# class  keep      the importing file is a Keep row of the inventory script
#        unlisted  the inventory script has no row for it
# shape  top            a module-level import: the file fails to import once the target is gone
#        top-guarded    module level, inside a try whose handler catches the import failure
#        lazy           inside a function: only that call path fails
#        lazy-guarded   inside a function and inside such a try
# name=uses  the imported name and how many times the file then reads it; for a module imported
#            whole, the attributes read off its local name, written `.attribute`.
#
# Then, for each deleted file, its size and the names it defines at module level that a survivor
# takes; one summary line per importing file; and the totals. Test files are not read.
# Read-only, zero tokens. Output is meant for
# src/captures/out/t19-outside-import-symbols-<host>-<date>.txt.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
exec python3 - "$here/t19_switch_over_inventory.sh" "$@" <<'PYTHON'
import ast, os, re, subprocess, sys

TREE      = "src/lupin_cli/claude_code"
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

def deleted_outside( checkout, rows ):
    """Dotted module name -> path, for every Python file a Delete row removes outside the tree, or a file Rename row moves."""
    doomed = { }
    for kind, _clock, disposition, target in rows:
        if not ( disposition == "Delete" or ( disposition == "Rename" and kind == "file" ) ) or target == TREE or target.startswith( TREE + "/" ): continue
        if kind == "file" and target.endswith( ".py" ): doomed[ target[ 4:-3 ].replace( "/", "." ) ] = target
        if kind == "dir":
            for directory, _directories, files in os.walk( os.path.join( checkout, target ) ):
                for name in files:
                    if name.endswith( ".py" ):
                        path = os.path.relpath( os.path.join( directory, name ), checkout )
                        doomed[ path[ 4:-3 ].replace( "/", "." ) ] = path
    return doomed

def handler_catches( handler ):
    if handler.type is None: return True
    kinds = handler.type.elts if isinstance( handler.type, ast.Tuple ) else [ handler.type ]
    return any( isinstance( kind, ast.Name ) and kind.id in CATCHES for kind in kinds )

def imports_of( text, doomed ):
    """A list of ( line, dotted module, shape, { local name: uses } ) for each import in text of a module in doomed."""
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
            if isinstance( child, ast.ImportFrom ) and child.level == 0 and child.module:
                if child.module in doomed:
                    found.append( ( child.lineno, child.module, shape,
                                    { alias.name: loads.get( alias.asname or alias.name, 0 ) for alias in child.names } ) )
                else:
                    for alias in child.names:
                        if child.module + "." + alias.name in doomed:
                            found.append( ( child.lineno, child.module + "." + alias.name, shape, whole( alias.asname or alias.name ) ) )
            elif isinstance( child, ast.Import ):
                for alias in child.names:
                    if alias.name in doomed:
                        found.append( ( child.lineno, alias.name, shape,
                                        whole( alias.asname ) if alias.asname else { "(dotted, no alias)": 0 } ) )
            visit( child, child_function, child_guarded, child_owner )

    visit( tree, False, False )
    return sorted( found )

def definitions_of( text ):
    """Module-level name -> ( kind, first line, last line ) for functions, classes and assignments."""
    found = { }
    for node in ast.parse( text ).body:
        if isinstance( node, ( ast.FunctionDef, ast.AsyncFunctionDef ) ): found[ node.name ] = ( "function", node.lineno, node.end_lineno )
        elif isinstance( node, ast.ClassDef ): found[ node.name ] = ( "class", node.lineno, node.end_lineno )
        elif isinstance( node, ( ast.Assign, ast.AnnAssign ) ):
            targets = node.targets if isinstance( node, ast.Assign ) else [ node.target ]
            for target in targets:
                if isinstance( target, ast.Name ): found[ target.id ] = ( "value", node.lineno, node.end_lineno )
        elif isinstance( node, ( ast.ImportFrom, ast.Import ) ):
            for alias in node.names: found.setdefault( alias.asname or alias.name, ( "re-export", node.lineno, node.end_lineno ) )
    return found

def self_test():
    doomed = { "pkg.gone": "src/pkg/gone.py", "pkg.sub.also": "src/pkg/sub/also.py" }
    sample = (
        "from pkg.gone import find, get as g\n"
        "from pkg.sub import also\n"
        "# from pkg.gone import no\n"
        "x = '''\nfrom pkg.gone import no\n'''\n"
        "try:\n    from pkg.gone import b\nexcept ImportError:\n    b = None\n"
        "try:\n    from pkg.gone import d\nexcept ValueError:\n    pass\n"
        "def f():\n    import pkg.sub.also as e\n    try:\n        from pkg.gone import i\n    except Exception:\n        return None\n"
        "    return find( 1 ), find( 2 ), g, also.base(), also.base, e.z, i\n"
        "from pkg.kept import no\n"
        "import pkg.gone\n"
    )
    got = imports_of( sample, doomed )
    definitions = definitions_of( "A = 1\ndef f():\n    return 1\nclass C:\n    pass\nfrom q import r\n" )
    checks = [
        ( len( got ), 7 ),
        ( got[ 0 ], ( 1, "pkg.gone", "top in=<module>", { "find": 2, "get": 1 } ) ),
        ( got[ 1 ], ( 2, "pkg.sub.also", "top in=<module>", { ".base": 2 } ) ),
        ( got[ 2 ][ 1: 3 ], ( "pkg.gone", "top-guarded in=<module>" ) ),
        ( got[ 3 ][ 1: 3 ], ( "pkg.gone", "top in=<module>" ) ),
        ( got[ 4 ], ( 16, "pkg.sub.also", "lazy in=f", { ".z": 1 } ) ),
        ( got[ 5 ], ( 18, "pkg.gone", "lazy-guarded in=f", { "i": 1 } ) ),
        ( got[ 6 ], ( 23, "pkg.gone", "top in=<module>", { "(dotted, no alias)": 0 } ) ),
        ( sum( 1 for row in got if "no" in row[ 3 ] ), 0 ),
        ( definitions, { "A": ( "value", 1, 1 ), "f": ( "function", 2, 3 ), "C": ( "class", 4, 5 ), "r": ( "re-export", 6, 6 ) } ),
        ( classify_file( "src/a.py", [ ( "file", "delete", "Delete", "src/a.py" ) ] ), "delete" ),
        ( classify_file( "src/b.py", [ ( "file", "move", "Keep", "src/b.py" ) ] ), "keep" ),
        ( classify_file( "src/c.py", [ ] ), "unlisted" ),
        ( deleted_outside( "/nonexistent", [ ( "file", "move", "Rename", "src/d/e.py" ), ( "file", "delete", "Delete", "src/a.py" ), ( "route", "delete", "Rename", "src/f.py" ), ( "file", "move", "Keep", "src/b.py" ) ] ), { "d.e": "src/d/e.py", "a": "src/a.py" } ),
    ]
    failed = [ ( number, value, expected ) for number, ( value, expected ) in enumerate( checks, 1 ) if value != expected ]
    for number, value, expected in failed: print( f"FAIL case {number}: got {value!r}, expected {expected!r}" )
    print( f"self-test: {len( checks ) - len( failed )} of {len( checks )} cases pass" )
    return 1 if failed else 0

def main( inventory_script, arguments ):
    if not arguments: print( "usage: t19_outside_import_symbols.sh <lupin checkout> | --self-test", file=sys.stderr ); return 2
    if arguments[ 0 ] == "--self-test": return self_test()
    checkout = arguments[ 0 ]
    if not os.path.isdir( os.path.join( checkout, "src" ) ): print( f"no src under {checkout}", file=sys.stderr ); return 2
    rows   = inventory_rows( open( inventory_script ).read() )
    doomed = deleted_outside( checkout, rows )
    commit = subprocess.run( [ "git", "-C", checkout, "rev-parse", "--short", "HEAD" ], capture_output=True, text=True ).stdout.strip()
    stamp  = subprocess.run( [ "date", "+%Y-%m-%dT%H:%M%z" ], capture_output=True, text=True, env={ **os.environ, "TZ": "America/New_York" } ).stdout.strip()
    print( f"# t19 outside import symbols · checkout={checkout} · commit={commit} · inventory rows={len( rows )} · deleted Python files outside the tree={len( doomed )} · {stamp}" )

    by_target, by_file, unparsed = { }, { }, [ ]
    for directory, directories, files in os.walk( os.path.join( checkout, "src" ) ):
        directories[ : ] = [ name for name in directories if name not in ( "node_modules", "__pycache__", ".git" ) ]
        for name in files:
            if not name.endswith( ".py" ): continue
            path = os.path.relpath( os.path.join( directory, name ), checkout )
            if path.startswith( TREE + "/" ) or TEST_PATH.search( path ) or path in doomed.values(): continue
            kind = classify_file( path, rows )
            if kind == "delete": continue
            try: text = open( os.path.join( checkout, path ), encoding="utf-8", errors="replace" ).read()
            except OSError: continue
            try: found = imports_of( text, doomed )
            except SyntaxError as error: unparsed.append( ( path, str( error ) ) ); continue
            for line, module, shape, names in found:
                by_target.setdefault( doomed[ module ], [ ] ).append( ( kind, path, line, shape, names ) )
                by_file.setdefault( ( kind, path ), [ ] ).append( ( doomed[ module ], shape.split( " in=" )[ 0 ] ) )

    for target in sorted( by_target, key=lambda target: ( -len( { row[ 1 ] for row in by_target[ target ] } ), target ) ):
        entries = sorted( by_target[ target ], key=lambda row: ( row[ 1 ], row[ 2 ] ) )
        names   = { }
        for _kind, path, _line, _shape, found in entries:
            for name in found: names.setdefault( name.lstrip( "." ), set() ).add( path )
        text    = open( os.path.join( checkout, target ), encoding="utf-8", errors="replace" ).read()
        defined = definitions_of( text )
        print( f"\n## {target} · lines={text.count( chr( 10 ) )} · files={len( { row[ 1 ] for row in entries } )} statements={len( entries )} distinct names={len( names )}" )
        for kind, path, line, shape, found in entries:
            print( f"{os.path.basename( target )[ :-3 ]:<26} {kind:<8} {path}:{line}  {shape:<34}  " + " ".join( f"{name}={uses}" for name, uses in found.items() ) )
        for name, paths in sorted( names.items(), key=lambda item: ( -len( item[ 1 ] ), item[ 0 ] ) ):
            if name.startswith( "(" ): continue
            kind, first, last = defined.get( name, ( "NOT DEFINED AT MODULE LEVEL", 0, 0 ) )
            print( f"#   {name:<40} files={len( paths )}  {kind} {target}:{first}-{last} ({last - first + 1 if first else 0} lines)" )

    print( "\n## per file" )
    hard = 0
    for ( kind, path ), found in sorted( by_file.items(), key=lambda item: item[ 0 ][ 1 ] ):
        shapes  = sorted( { shape for _target, shape in found } )
        hard   += "top" in shapes
        print( f"{kind:<8} {path:<52} statements={len( found ):<2} shapes={','.join( shapes ):<28} targets={','.join( sorted( { os.path.basename( target )[ :-3 ] for target, _shape in found } ) )}" )
    print( f"\n# surviving files importing a deleted file outside the tree: {len( by_file )} "
           f"(keep={sum( 1 for kind, _path in by_file if kind == 'keep' )} unlisted={sum( 1 for kind, _path in by_file if kind == 'unlisted' )})" )
    print( f"# files with at least one unguarded module-level import (fail at import after the Delete): {hard}" )
    print( f"# deleted files wanted: {len( by_target )} of {len( doomed )} · import statements: {sum( len( entries ) for entries in by_target.values() )}" )
    for path, error in unparsed: print( f"# NOT PARSED {path}: {error}" )
    return 0

sys.exit( main( sys.argv[ 1 ], sys.argv[ 2: ] ) )
PYTHON
