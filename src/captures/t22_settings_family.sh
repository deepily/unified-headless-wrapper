#!/usr/bin/env bash
# t22_settings_family.sh: what this host holds behind the ten sign-in and quota settings that have
# no ruling on presence or legal values (engine sign-in and quota, D68, register item T22).
# Rows 124 and 125 of "Outstanding actions".
#
# Zero tokens: it starts no engine turn. It reads each engine's binary on disk (counts of marker
# strings), the mode and age of the sign-in file (never its contents), two named boolean fields of
# the engine's settings files, lupin's settings file (a count), and this checkout's specs (counts).
# It writes one file under src/captures/out/ and nothing else. It prints no secret, token or
# email address.
#
# Usage: src/captures/t22_settings_family.sh [path of the lupin checkout, default /mnt/lupin-data/lupin]

set -u
HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$( cd "$HERE/../.." && pwd )"
LUPIN="${1:-/mnt/lupin-data/lupin}"
STAMP="$( TZ=America/New_York date +%Y%m%d )"
OUT="$HERE/out/t22-settings-family-$( hostname -s )-$STAMP.txt"
DESIGN="$ROOT/src/rnd/v0.0.1"
SPEC="$DESIGN/specs/2026.11.11-t22-engine-sign-in-and-quota-spec.md"

KEYS=( "kernel engine login check seconds" "kernel engine login remind hours" "kernel engine login warn hours"
       "kernel engine meter seconds" "kernel engine meter max age seconds" "kernel engine quota reopen card min minutes"
       "kernel engine overage" "kernel engine force file storage" "kernel engine prices" "kernel usage rollup at" )

count_marker() { grep -a -c -e "$2" "$1" 2>/dev/null || true; }
show() { printf '%-52s %s\n' "$1" "$2"; }

report_engine() {
  local engine="$1" found path marker
  found="$( command -v "$engine" 2>/dev/null || true )"
  if [ -z "$found" ]; then show "$engine.binary" "not on PATH"; return; fi
  path="$( readlink -f "$found" )"
  show "$engine.version" "$( timeout 20 "$found" --version 2>/dev/null | head -1 )"
  for marker in GEMINI_FORCE_FILE_STORAGE FORCE_FILE_STORAGE antigravity-oauth-token oauth-token useG1Credits useAiCredits AGY_ADC_AUTH keyring; do
    show "$engine.marker[$marker]" "$( count_marker "$path" "$marker" )"
  done
}

report_path() {
  local label="$1" path="$2"
  if [ -e "$path" ]; then
    show "$label.mode" "$( stat -c %a "$path" )"
    show "$label.age_hours" "$(( ( $( date +%s ) - $( stat -c %Y "$path" ) ) / 3600 ))"
  else
    show "$label" "absent"
  fi
}

report_overage_fields() {
  local label="$1" path="$2"
  if [ ! -r "$path" ]; then show "$label" "absent"; return; fi
  python3 - "$label" "$path" <<'PY'
import json, sys
label, path = sys.argv[1], sys.argv[2]
try:
    data = json.load( open( path ) )
except Exception as error:
    print( f"{label:<52} unreadable as JSON ({type( error ).__name__})" ); sys.exit( 0 )
def find( node, name ):
    if isinstance( node, dict ):
        for key, value in node.items():
            if key == name: yield value
            yield from find( value, name )
    elif isinstance( node, list ):
        for item in node: yield from find( item, name )
for name in ( "useG1Credits", "useAiCredits" ):
    found = [ value for value in find( data, name ) if isinstance( value, bool ) ]
    print( f"{label + '.' + name:<52} {found if found else 'not present'}" )
PY
}

{
  echo "# t22_settings_family.sh on $( hostname -s ), $( TZ=America/New_York date '+%Y-%m-%d %H:%M' ) US Eastern"
  echo "# A marker count is the number of lines of the binary that hold the string; 0 means the string is absent."
  for engine in agy jetski claude; do report_engine "$engine"; echo; done

  show "GEMINI_FORCE_FILE_STORAGE_in_this_shell" "${GEMINI_FORCE_FILE_STORAGE:-unset}"
  report_path "sign_in_directory" "$HOME/.gemini/antigravity-cli"
  report_path "sign_in_file" "$HOME/.gemini/antigravity-cli/antigravity-oauth-token"
  show "other_files_named_oauth_or_credentials" "$( find "$HOME/.gemini" -maxdepth 3 \( -iname '*oauth*' -o -iname '*credentials*' \) 2>/dev/null | grep -v -c 'antigravity-cli/antigravity-oauth-token$' || true )"
  report_overage_fields "engine_settings" "$HOME/.gemini/antigravity-cli/settings.json"
  report_overage_fields "shared_config" "$HOME/.gemini/config/config.json"
  echo

  INI="$LUPIN/src/conf/lupin-app.ini"
  if [ -r "$INI" ]; then
    show "lupin_ini.kernel_keys" "$( grep -c -i '^kernel ' "$INI" || true )"
  else
    show "lupin_ini" "not readable at $INI"
  fi
  echo

  echo "# Each key: lines naming it in the sign-in and quota spec; lines naming it in every other spec and the framework."
  for key in "${KEYS[@]}"; do
    short="${key#kernel engine }"
    here="$( grep -c -F -e "$key" -e "\`$short\`" "$SPEC" || true )"
    elsewhere="$( grep -h -c -F "$key" "$DESIGN"/specs/*.md "$DESIGN/01-framework.md" | paste -sd+ | bc )"
    show "key[$key]" "$here here; $(( elsewhere - $( grep -c -F "$key" "$SPEC" || true ) )) elsewhere"
  done
  show "keys_in_the_spec_section_14_block" "$( awk '/^## 14\. /{ on=1 } /^## 15\. /{ on=0 } on && /^kernel /' "$SPEC" | wc -l )"
  show "keys_of_this_family_already_ruled" "$( grep -c '; required' "$SPEC" || true )"
  show "pool_name_keys_named_in_the_spec" "$( grep -c -F 'kernel engine pool name third party models' "$SPEC" || true ) lines"
  echo
  echo "# Fields of the reference code (the spec's latest engine_account.py) that hold one of the ten settings."
  for field in sample_max_age login_check remind warn_hours meter_seconds reopen overage force_file prices rollup; do
    show "reference_code_lines[$field]" "$( awk '/^```python/{ on=1; next } /^```/{ on=0 } on' "$SPEC" | grep -c -i "$field" || true )"
  done
} | tee "$OUT"
echo "written: $OUT"
