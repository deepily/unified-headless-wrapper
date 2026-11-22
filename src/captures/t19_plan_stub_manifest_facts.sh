#!/usr/bin/env bash
# t19_plan_stub_manifest_facts.sh — what the record and this host hold that the Phase 1 plan stub
# manifest must fit, for row 116 of "Outstanding actions": the manifest that seeds the task store
# with the builder's list of work (T19 spec, the amendment of 2026-11-22, row 93, ruling 4).
#
#   t19_plan_stub_manifest_facts.sh [kit root] [correlation key]
#       defaults: $PLANNING_IS_PROMPTING_ROOT or /mnt/lupin-data/planning-is-prompting;
#                 epic:uhw-phase1-kernel
#
# Five parts, one line per fact, `name value`:
#
#   (a) the plan as written   steps in the Phase 1 spec's Section 13, Kernel rows in its Section 12,
#                             and the headings the kit's importer would read as phase headings
#   (b) the kit               the manifest rule, the importer, its sample; the importer's own limits
#   (c) this repository       whether the kit's folder for manifests exists; what the builder's
#                             clone leaves out of its tree
#   (d) the task store        the instance the importer reads by default: reachable or not, rows in
#                             all, rows under the correlation key, projects, owners, managers
#   (e) the title budget      characters left for a step's name under the store's cap
#
# Read-only: `grep`, `sed`, `wc`, `git -C … sparse-checkout list`, and GET requests to the task
# store through the importer's own `call` (the API key is read, never printed). It writes nothing
# and creates no row. Zero tokens, a few seconds.
# Output is meant for src/captures/out/t19-plan-stub-manifest-facts-<host>-<date>.txt.

set -u
kit="${1:-${PLANNING_IS_PROMPTING_ROOT:-/mnt/lupin-data/planning-is-prompting}}"
correlation_key="${2:-epic:uhw-phase1-kernel}"
here="$(cd "$(dirname "$0")/../.." && pwd)"
spec="$here/src/rnd/v0.0.1/specs/2026.10.24-phase1-kernel-and-jetski-family-adapter-spec.md"
builder="/mnt/lupin-data/unified-headless-wrapper-builder"
importer="$kit/workflow/scripts/plan_stub_import.py"
export LUPIN_ROOT="${LUPIN_ROOT:-/mnt/lupin-data/lupin}"
say() { printf '%-44s %s\n' "$1" "$2"; }
yes_no() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

echo "# (a) the plan as written"
say host "$(hostname)"
say read_at "$(TZ=America/New_York date '+%Y-%m-%d %H:%M %Z')"
[ -r "$spec" ] || { say phase1_spec "MISSING $spec"; exit 2; }
say order_of_work_steps "$(sed -n '/^## 13\. /,/^## 14\. /p' "$spec" | grep -cE '^[0-9]+\. ')"
say kernel_gate_rows "$(sed -n '/^## 12\. /,/^## 13\. /p' "$spec" | grep -cE '^\| Kernel-[0-9]+ ')"
say spec_amendments "$(grep -cE '^## Amend' "$spec")"

echo "# (b) the kit"
for file in workflow/plan-stub-manifest.md workflow/scripts/plan_stub_import.py src/docs/plan-stubs/plan-stub-sample.stubs.json; do
    if [ -r "$kit/$file" ]; then say "$file" "$(wc -c < "$kit/$file") bytes, $(wc -l < "$kit/$file") lines"
    else say "$file" MISSING; fi
done
say kit_is_a_git_checkout "$(yes_no git -C "$kit" rev-parse --git-dir)"
[ -r "$importer" ] || { say importer "MISSING"; exit 2; }

echo "# (c) this repository"
say src_docs_exists "$(yes_no test -d "$here/src/docs")"
say json_files_under_src_rnd "$(find "$here/src/rnd" -name '*.json' | wc -l)"
say builder_sparse_patterns "$(git -C "$builder" sparse-checkout list 2>/dev/null | tr '\n' ' ')"

PYTHONDONTWRITEBYTECODE=1 python3 - "$importer" "$spec" "$correlation_key" <<'EOF'
import collections, importlib.util, sys

importer_path, spec_path, correlation_key = sys.argv[ 1 ], sys.argv[ 2 ], sys.argv[ 3 ]
loader = importlib.util.spec_from_file_location( "plan_stub_import", importer_path )
kit    = importlib.util.module_from_spec( loader )
loader.loader.exec_module( kit )

def say( name, value ): print( f"{name:<44} {value}" )

print( "# (a, continued) what the importer reads as phase headings in the Phase 1 spec" )
say( "phase_heading_ids_in_spec", kit.plan_phase_ids( open( spec_path, encoding="utf-8" ).read() ) )

print( "# (a, continued) the modules of the spec's Section 3 layout, against its Section 13 order of work" )
import re
text    = open( spec_path, encoding="utf-8" ).read()
layout  = text.split( "\n## 3. ", 1 )[ 1 ].split( "\n## 4. ", 1 )[ 0 ]
order   = text.split( "\n## 13. ", 1 )[ 1 ].split( "\n## 14. ", 1 )[ 0 ]
modules = re.findall( r"^ +((?:[a-z_]+/)?[a-z_]+\.py) +(.*)$", layout, re.MULTILINE )
later   = [ name for name, note in modules if note.rstrip().endswith( "Phase 2" ) ]
named   = [ name for name, note in modules if name.split( "/" )[ -1 ] in order ]
unnamed = [ name for name, note in modules if name not in named and name not in later ]
say( "layout_modules", len( modules ) )
say( "marked_phase_2_in_layout", f"{len( later )}: {' '.join( later )}" )
say( "named_by_file_in_order_of_work", f"{len( named )}: {' '.join( named )}" )
say( "not_named_by_file_in_order_of_work", f"{len( unnamed )}: {' '.join( unnamed )}" )
say( "py_files_in_order_of_work_not_in_layout", " ".join( sorted( { f for f in re.findall( r"`((?:[a-z_]+/)?[a-z_]+\.py)`", order ) if f.split( "/" )[ -1 ] not in layout } ) ) )

print( "# (b, continued) the importer's limits" )
say( "title_cap", kit.TITLE_CAP )
say( "item_classes", kit.ITEM_CLASSES )
say( "gate_classes", kit.GATE_CLASSES )

print( "# (d) the task store" )
say( "api_base", kit.api_base() )
say( "api_key_readable", "yes" if kit.read_api_key() else "no" )
code, body = kit.call( "GET", "/api/tasks", params={ "correlation_key": correlation_key, "include_terminal": "true", "hide_parked": "false", "limit": 500 } )
say( "rows_under_" + correlation_key, len( body.get( "tasks", [] ) ) if code == 200 and isinstance( body, dict ) else f"HTTP {code}" )
code, body = kit.call( "GET", "/api/tasks", params={ "include_terminal": "true", "hide_parked": "false", "limit": 500 } )
if code != 200 or not isinstance( body, dict ):
    say( "rows_in_all", f"HTTP {code}" )
else:
    rows = body.get( "tasks", [] )
    say( "rows_in_all", f"{len( rows )} (has_more {body.get( 'has_more' )})" )
    for field in ( "project", "owner_persona", "accountable_manager", "status" ):
        counts = collections.Counter( str( row.get( field ) ) for row in rows )
        say( field, ", ".join( f"{name} {count}" for name, count in counts.most_common() ) )
    say( "rows_titled_[UHW]", sum( 1 for row in rows if ( row.get( "title" ) or "" ).startswith( "[UHW]" ) ) )

print( "# (e) the title budget, for a plan named as the second argument's slug suggests" )
for plan_name in ( "Kernel first build", "Kernel build" ):
    head = f"[UHW] {plan_name} · Phase 9 of 9 · Step 6 of 6 · "
    say( f"name_room[{plan_name}]", kit.TITLE_CAP - len( head ) )
    stub = f"[UHW] {plan_name} · Phase 9 of 9 · STUB ·  (expand when )"
    say( f"stub_name_and_trigger_room[{plan_name}]", kit.TITLE_CAP - len( stub ) )
EOF
