#!/usr/bin/env bash
# t19_switch_over_inventory.sh — the list of record (T19 spec Section 5) in machine form.
#
#   t19_switch_over_inventory.sh <lupin checkout> [--clock move|switch|delete] [--trace <pid> <bridge dir>]
#
# Each row is kind|clock|disposition|target. Kinds: file (path under the checkout), dir (a tree),
# symbol (a name grepped under src/), key (an INI key grepped under src/), route (a URL fragment
# grepped under src/), unit (a systemd unit file under src/). For every row the script prints
# present <lines or matches>, gone, or unknown. With --clock it prints that clock's rows only and
# exits 1 when a Delete row is present or a Keep row is gone. With --trace it watches a running
# workload for tmux processes and new bridge files and prints both counts (both must be zero).
# Read-only. Output is meant for src/captures/out/t19-inventory-<host>-<date>.txt.

set -u
checkout="${1:?usage: $0 <lupin checkout> [--clock move|switch|delete] [--trace <pid> <bridge dir>]}"; shift
clock_filter=""; trace_pid=""; bridge_directory=""
while [ $# -gt 0 ]; do
    case "$1" in
        --clock) clock_filter="$2"; shift 2 ;;
        --trace) trace_pid="$2"; bridge_directory="$3"; shift 3 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
source_root="$checkout/src"
hooks_tree="lupin_cli/claude_code/hooks"
hooks_library="$hooks_tree/lib"

rows=$(cat <<'ROWS'
dir|delete|Delete|src/lupin_cli/claude_code
file|delete|Delete|docker/lupin/claude-config/settings.json
file|delete|Delete|src/lupin_cli/claude_code/hooks/stop.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/notification.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/pre_tool_use.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/permission_request.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/post_tool_use.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/user_prompt_submit.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/register_session.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/session_end.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/heartbeat_decision.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/heartbeat_settings.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/heartbeat_work_owed.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/heartbeat_task_state.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/heartbeat_user_gates.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/heartbeat_poke_cap.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/heartbeat_poke_mute.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/heartbeat_acked_ledger.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/heartbeat_hold.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/heartbeat_hold_io.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/heartbeat_hold_warn.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/heartbeat_events.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/idle_waiter.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/idle_settings.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/anything_else_ask.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/board_sweep.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/memento_verify_tick.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/cc_notification_listener.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/listener_processes.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/hook_common.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/session_bridge.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/answer_catchup.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/dm_inbox_reconcile.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/dm_inbox_hwm_janitor.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/stale_buffer_janitor.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/bookmark_janitor.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/subagent_governance.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/hook_credentials.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/transcript_reader.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/task_store_mirror.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/task_store_drain.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/task_store_spool.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/task_store_settings.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/manager_figure.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/worktree_creator_record.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/roster_consistency.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/sessions_dir.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/process_identity.py
file|delete|Delete|src/lupin_cli/claude_code/hooks/lib/main_tree.py
symbol|delete|Delete|send-keys
symbol|delete|Delete|_try_auto_narrate
symbol|delete|Delete|speakerphone_exit_reminder
symbol|delete|Delete|_inject_exit_conversation_reminder
symbol|delete|Delete|_update_session_topic
symbol|delete|Delete|_handle_broadcast_received
symbol|delete|Delete|_DM_GRADE_SENDER_ID
symbol|delete|Delete|orphan_bridge_reaper
symbol|delete|Delete|prune_dead_persona_bridges
symbol|delete|Delete|reap_stale_spawned
symbol|delete|Delete|poke_wake_mechanism
file|delete|Delete|src/lupin_mcp/bridge_liveness_middleware.py
file|delete|Delete|src/lupin_mcp/self_respin_core.py
file|delete|Delete|src/cosa/agents/heartbeat_arbiter/self_respin_observer.py
file|delete|Delete|src/cosa/agents/heartbeat_arbiter/respin_wake_check.py
file|delete|Delete|src/cosa/agents/heartbeat_arbiter/context_pressure.py
file|delete|Delete|src/cosa/agents/heartbeat_arbiter/turn_age_watchdog.py
file|delete|Delete|src/lupin_arbiter_app/context_pressure_writer.py
file|delete|Delete|src/lupin_arbiter_app/arbiter_live_notify.py
dir|delete|Delete|src/lupin_arbiter_app
unit|delete|Delete|lupin-arbiter-app.service
file|delete|Delete|src/scripts/run-heartbeat-arbiter.py
file|delete|Delete|src/scripts/start-cc-with-tmux.sh
file|delete|Delete|src/cosa/rest/routers/claude_code_queue.py
file|delete|Delete|src/cosa/rest/cc_transcript_mapper.py
file|delete|Delete|src/lupin_mcp/session_spawner.py
file|delete|Delete|src/lupin_mcp/fleet_size_cap.py
file|delete|Delete|src/lupin_mcp/fleet_cap_admission.py
file|delete|Delete|src/lupin_mcp/fleet_cap_ini_io.py
file|delete|Delete|src/lupin_mcp/skeleton_crew.py
file|delete|Delete|src/lupin_mcp/respin_credit.py
file|delete|Delete|src/lupin_mcp/reap_memento.py
file|delete|Delete|src/scripts/provision-seat-worktree.sh
file|delete|Delete|src/cosa/utils/seat_worktree.py
file|delete|Delete|src/scripts/stale-seat-scan.py
file|delete|Delete|src/cosa/utils/cc_memory_watch.py
file|delete|Delete|src/scripts/watch-cc-memory.sh
file|delete|Delete|src/scripts/install-cc-memory-watch.sh
unit|delete|Delete|lupin-cc-memory-watch.service
file|delete|Delete|src/scripts/derive_cc_memory_peak.py
file|delete|Delete|src/lupin_mcp/broadcast_handler.py
file|delete|Delete|src/lupin_mcp/commons_persona_matcher.py
file|delete|Delete|src/scripts/heartbeat-poke-toggle.sh
file|delete|Delete|src/scripts/purge-offline-heartbeat-events.py
file|delete|Delete|src/scripts/check-cc-listener-status.sh
file|delete|Delete|src/scripts/restart-cc-listeners.sh
file|delete|Delete|src/scripts/tail-cc-listeners.sh
file|delete|Delete|src/scripts/backfill_bridge_sender_id.py
file|delete|Delete|src/scripts/bridge_pin_sweep.py
file|delete|Delete|src/scripts/run-serial-bridge-guard.sh
file|delete|Delete|src/scripts/voice-send.sh
file|delete|Delete|src/scripts/probe_cc_bounded_billing.py
file|delete|Delete|src/scripts/tfe_to_cc_matrix.sh
file|delete|Delete|src/scripts/tfe_to_cc_phase1_smoke.py
file|delete|Delete|src/scripts/tfe_to_cc_phase3_live.py
key|delete|Delete|stop hook idle behavior
unit|needed|Disposition needed|tmux-execve-killtrace.service
unit|needed|Disposition needed|lupin-bounce-watcher.service
unit|needed|Disposition needed|lupin-credential-watcher.service
file|move|Keep and import|src/lupin_cli/claude_code/hooks/lib/kill_guard.py
file|move|Keep and import|src/lupin_cli/claude_code/hooks/lib/commit_scope_guard.py
file|move|Keep and import|src/lupin_cli/claude_code/hooks/lib/branch_lock_guard.py
file|move|Keep and import|src/lupin_cli/claude_code/hooks/lib/merge_head_guard.py
file|move|Keep and import|src/lupin_cli/claude_code/hooks/lib/stash_guard.py
file|move|Keep and import|src/lupin_cli/claude_code/hooks/lib/task_store_client.py
file|move|Keep and import|src/lupin_cli/claude_code/hooks/lib/task_store_map.py
file|move|Keep and import|src/lupin_mcp/reap_branch.py
file|move|Keep and import|src/cosa/agents/shared/seat_teardown.py
file|move|Keep and import|src/cosa/agents/shared/worktree_reaper.py
file|move|Keep and import|src/cosa/agents/shared/worktree_refusal_ledger.py
file|move|Keep and import|src/cosa/agents/shared/worktree_straggler_tickets.py
file|move|Keep and import|src/scripts/link-worktree-venv.sh
file|move|Keep and import|src/cosa/utils/vertex_env.py
symbol|move|Keep|HeartbeatPokerJob
file|move|Keep|src/cosa/rest/routers/cc_transcript.py
file|move|Keep|src/lupin_mcp/cosa_voice_mcp.py
route|switch|Rename|cc-listener-
route|switch|Rename|broadcast-to-cc-sessions
route|delete|Rename|/api/cc-transcript
route|move|Rename (repoint)|/api/arbiter/context-pressure
route|move|Rename (repoint)|/api/arbiter/fleet-state
route|move|Rename (repoint)|/api/arbiter/fleet-size-cap
key|switch|Flip|legacy notifications redirect enabled
key|switch|Flip|kernel grant required
key|move|Move key|cc session fleet size cap
key|move|Move key|cc session spawn
key|move|Move key|cc session skeleton crew enabled
key|move|Move key|cc session reap memento
key|move|Move key|arbiter worktree janitor
symbol|move|Move key|CC_MEM_LIMIT
symbol|move|Move key|LUPIN_CC_MEMORY_MAX
symbol|move|Move key|LUPIN_CC_MEMORY_SWAP_MAX
symbol|move|Move key|LUPIN_CC_WINDOW_TOKENS
ROWS
)

resolve() {
    local kind="$1" target="$2"
    case "$kind" in
        file)   [ -f "$checkout/$target" ] && echo "present $(wc -l < "$checkout/$target")" || echo gone ;;
        dir)    [ -d "$checkout/$target" ] && echo "present $(find "$checkout/$target" -name '*.py' -o -name '*.sh' | xargs cat 2>/dev/null | wc -l)" || echo gone ;;
        unit)   local found; found=$(find "$source_root" -name "$target" 2>/dev/null | head -1); [ -n "$found" ] && echo "present $(wc -l < "$found")" || echo gone ;;
        symbol|key|route)
                local matches; matches=$(grep -rIl --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=__pycache__ -F -- "$target" "$source_root" 2>/dev/null | grep -v '/tests\?/' | wc -l)
                [ "$matches" -gt 0 ] && echo "present $matches files" || echo gone ;;
        *)      echo unknown ;;
    esac
}

if [ -n "$trace_pid" ]; then
    before=$(find "$bridge_directory" -maxdepth 1 -name 'cc-*.json' 2>/dev/null | wc -l)
    tmux_seen=0
    while kill -0 "$trace_pid" 2>/dev/null; do
        if pstree -p "$trace_pid" 2>/dev/null | grep -q tmux; then tmux_seen=$(( tmux_seen + 1 )); fi
        sleep 2
    done
    after=$(find "$bridge_directory" -maxdepth 1 -name 'cc-*.json' 2>/dev/null | wc -l)
    echo "trace pid=$trace_pid tmux_sightings=$tmux_seen bridge_files_written=$(( after - before ))"
    exit 0
fi

echo "# t19 switch-over inventory · checkout=$checkout · commit=$(git -C "$checkout" rev-parse --short HEAD 2>/dev/null) · $(date -u +%Y-%m-%dT%H:%MZ)${clock_filter:+ · clock=$clock_filter}"
failures=0; total=0; unknown=0
while IFS='|' read -r kind clock disposition target; do
    [ -z "$kind" ] && continue
    [ -n "$clock_filter" ] && [ "$clock" != "$clock_filter" ] && continue
    total=$(( total + 1 ))
    state=$(resolve "$kind" "$target")
    printf '%-7s %-7s %-20s %-70s %s\n' "$kind" "$clock" "$disposition" "$target" "$state"
    case "$state" in unknown) unknown=$(( unknown + 1 )) ;; esac
    if [ -n "$clock_filter" ]; then
        case "$disposition:$state" in
            Delete:present*|Rename:present*) failures=$(( failures + 1 )) ;;
            Keep*:gone|"Move key:gone"|Flip:gone) failures=$(( failures + 1 )) ;;
        esac
    fi
done <<< "$rows"
echo "# rows=$total unknown=$unknown${clock_filter:+ failures=$failures}"
[ "$unknown" -eq 0 ] && [ "$failures" -eq 0 ]
