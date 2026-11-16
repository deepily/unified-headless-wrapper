#!/usr/bin/env bash
# T35 persona-name seam inventory (2026-11-15). No model call; reads a lupin checkout, writes nothing to it.
# Answers, for one checkout: is the pool line in key form, which per-persona configuration keys are not,
# which code normalizes a persona name outside lupin_mcp/persona_normalization.py, which code compares a
# persona name raw, and whether the three local copies named by D69 (canonical persona name) still exist.
# Rerun on both hosts after each lupin change on the D69 list; the counts under "summary" should fall to
# the values in the T35 spec, Section 13.
# Usage: t35_name_seam_inventory.sh <path to the lupin checkout>
set -u
LUPIN=${1:?usage: t35_name_seam_inventory.sh <path to the lupin checkout>}
SRC="$LUPIN/src"
INI="$SRC/conf/lupin-app.ini"
MODULE="$SRC/lupin_mcp/persona_normalization.py"
KEY_FORM='^[a-z0-9]+( [a-z0-9]+)*$'
hr()  { printf '\n== %s ==\n' "$1"; }
val() { printf '%-44s %s\n' "$1" "$2"; }
code_files() {  # python files under src, tests and the shared module left out
    grep -rlE --include='*.py' "$1" "$SRC" 2>/dev/null \
        | grep -vE '/tests?/|/test_[^/]*\.py$|_test\.py$|conftest\.py$' \
        | grep -vF "$MODULE" | sed "s|^$LUPIN/||" | sort
}

hr "checkout"
val host "$( hostname )"
val clock "$( TZ=America/New_York date '+%Y-%m-%d %H:%M:%S %Z' )"
val lupin_head "$( git -C "$LUPIN" rev-parse --short=9 HEAD 2>/dev/null || echo 'no git' )"
val configuration_file "$( git -C "$LUPIN" diff --quiet -- src/conf/lupin-app.ini 2>/dev/null && echo 'as committed' || echo 'MODIFIED in the working tree; line numbers are the working tree'"'"'s' )"
val shared_module "$( [ -f "$MODULE" ] && echo present || echo ABSENT )"
[ -f "$MODULE" ] && val shared_functions "$( grep -oE '^def [a-z_]+' "$MODULE" | sed 's/def //' | tr '\n' ' ' )"

hr "pool line"
POOL_LINE=$( grep -nE '^cc session voice persona pool *=' "$INI" | head -1 )
val pool_line_number "${POOL_LINE%%:*}"
POOL=$( printf '%s' "$POOL_LINE" | sed 's/^[^=]*= *//' )
TOTAL=0; BAD=0
IFS=',' read -ra ENTRIES <<< "$POOL"
for RAW in "${ENTRIES[@]}"; do
    ENTRY=$( printf '%s' "$RAW" | sed 's/^ *//; s/ *$//' )
    TOTAL=$(( TOTAL + 1 ))
    if printf '%s' "$ENTRY" | grep -qE "$KEY_FORM"; then val "pool_entry" "$ENTRY  key_form"
    else val "pool_entry" "$ENTRY  NOT_KEY_FORM"; BAD=$(( BAD + 1 )); fi
done
DUPLICATES=$( printf '%s\n' "${ENTRIES[@]}" | sed 's/^ *//; s/ *$//' | sort | uniq -d | wc -l )

hr "per-persona configuration keys not in key form"
BAD_KEYS=$( grep -nE '^cc session voice persona [^=]*[A-Z][^=]*=' "$INI" | grep -vE '^[0-9]+:cc session voice persona pool' )
printf '%s\n' "$BAD_KEYS" | sed -E 's/ *=.*$//' | grep . || echo none
BAD_KEY_COUNT=$( printf '%s\n' "$BAD_KEYS" | grep -c . )
DISPLAY_KEYS=$( grep -cE '^cc session voice persona .* display name *=' "$INI" )

hr "normalization outside the shared module (accent or punctuation handling near a persona name)"
OUTSIDE=$( code_files 'unicodedata\.normalize|\[\^a-z0-9' | xargs -r -I{} sh -c "grep -lE 'persona' '$LUPIN/{}' >/dev/null && echo {}" )
printf '%s\n' "$OUTSIDE" | grep . || echo none
OUTSIDE_COUNT=$( printf '%s\n' "$OUTSIDE" | grep -c . )

hr "raw persona-name comparisons (== or != beside a persona name, no shared function on the line)"
RAW_LINES=$( grep -rnE --include='*.py' '(persona(_name|_key)?|owner_persona|accountable_manager|voice_persona)[]a-z_[" ]*(\.(lower|casefold|strip)\(\))* *(==|!=)' "$SRC" 2>/dev/null \
    | grep -vE '/tests?/|/test_[^/]*\.py:|_test\.py:|conftest\.py:' \
    | grep -vE 'canonical_persona_key|normalize_for_match|persona_slug|dm_topic_for|persona_id|persona_state|is None|== *None|!= *None|^[^:]*:[0-9]+: *assert |^[^:]*:[0-9]+: *#' \
    | sed "s|^$LUPIN/||" | cut -c1-170 )
printf '%s\n' "$RAW_LINES" | grep . || echo none
RAW_COUNT=$( printf '%s\n' "$RAW_LINES" | grep -c . )

hr "the local copies D69 names"
for CANDIDATE in $( cd "$SRC" && git ls-files 2>/dev/null | grep -E '(board_sweep|train_builder|self_respin_core|voice_persona_helpers)\.py$' | grep -v test ); do
    case "$CANDIDATE" in
        *board_sweep.py)           grep -qE 'def persona_slug'      "$SRC/$CANDIDATE" && val local_copy "present  $CANDIDATE (persona_slug)" ;;
        *train_builder.py)         grep -qE '\[\^a-z0-9|\.lower\(\)' "$SRC/$CANDIDATE" && val local_copy "present  $CANDIDATE (actor-name form)" ;;
        *self_respin_core.py)      grep -qE '\.casefold\(\) *=='    "$SRC/$CANDIDATE" && val local_copy "present  $CANDIDATE (case-only match)" ;;
        *voice_persona_helpers.py) grep -qE '_DISPLAY_OVERRIDES *=' "$SRC/$CANDIDATE" && val display_table "present  $CANDIDATE (_DISPLAY_OVERRIDES)" ;;
    esac
done

hr "callers of the shared module"
for FUNCTION in canonical_persona_key normalize_for_match persona_slug dm_topic_for memento_slugs; do
    val "$FUNCTION" "$( code_files "\b$FUNCTION\b" | wc -l ) files"
done

hr "summary"
val pool_entries "$TOTAL"
val pool_entries_not_key_form "$BAD"
val pool_duplicates "$DUPLICATES"
val configuration_keys_not_key_form "$BAD_KEY_COUNT"
val display_name_keys "$DISPLAY_KEYS"
val files_normalizing_outside_module "$OUTSIDE_COUNT"
val raw_comparison_lines "$RAW_COUNT"
