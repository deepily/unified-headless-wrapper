#!/usr/bin/env bash
# T25 host inventory (D60, 2026-11-10). Read-only; no model call; prints no secrets.
# Answers, for one host: the memory budget the kernel will compute, whether a per-persona
# scope can be made for this account, which cgroup files exist, and what the engines' Node does.
# Run as the persona account on the test VM and on the development server; paste the whole output back.
set -u
hr() { printf '\n== %s ==\n' "$1"; }
val() { printf '%-34s %s\n' "$1" "$2"; }

hr "host"
val host "$( hostname )"
val kernel "$( uname -r )"
val os "$( . /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" )"
val account "$( id -un ) uid=$( id -u )"

hr "memory (the budget is MemTotal minus max(4 GiB, 25%))"
mem_kb=$( awk '/^MemTotal/ { print $2 }' /proc/meminfo )
avail_kb=$( awk '/^MemAvailable/ { print $2 }' /proc/meminfo )
swap_kb=$( awk '/^SwapTotal/ { print $2 }' /proc/meminfo )
total=$(( mem_kb * 1024 )); reserve=$(( total / 4 )); floor=$(( 4 * 1024 * 1024 * 1024 ))
[ "$reserve" -lt "$floor" ] && reserve=$floor
budget=$(( total - reserve ))
val MemTotal_GiB "$( awk "BEGIN { printf \"%.1f\", $total / 1073741824 }" )"
val MemAvailable_GiB "$( awk "BEGIN { printf \"%.1f\", $avail_kb * 1024 / 1073741824 }" )"
val SwapTotal_GiB "$( awk "BEGIN { printf \"%.1f\", $swap_kb * 1024 / 1073741824 }" )"
val budget_GiB "$( awk "BEGIN { printf \"%.1f\", $budget / 1073741824 }" )"
val fit_at_2GiB_reserve "$(( budget / 2147483648 ))"
val fit_at_8GiB_cap "$(( budget / 8589934592 ))"

hr "cgroup v2"
val cgroup_root_type "$( stat -f -c %T /sys/fs/cgroup 2>/dev/null )"
val controllers "$( cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null )"
own=$( grep '^0::' /proc/self/cgroup 2>/dev/null | cut -d: -f3 )   # the cgroup-v2 line only
val own_cgroup "$own"
val own_subtree_control "$( cat "/sys/fs/cgroup$own/cgroup.subtree_control" 2>/dev/null || echo unreadable )"
val memory_peak_file "$( [ -e "/sys/fs/cgroup$own/memory.peak" ] && echo present || echo absent )"
val memory_pressure_file "$( [ -e "/sys/fs/cgroup$own/memory.pressure" ] && echo present || echo absent )"
val psi_global "$( head -1 /proc/pressure/memory 2>/dev/null || echo absent )"

hr "systemd user manager (needed for systemd-run --user --scope)"
val systemd_run "$( command -v systemd-run || echo absent )"
val XDG_RUNTIME_DIR "${XDG_RUNTIME_DIR:-unset}"
val linger "$( loginctl show-user "$( id -un )" -p Linger --value 2>/dev/null || echo unknown )"
val user_manager "$( systemctl --user is-system-running 2>&1 | head -1 )"
if command -v systemd-run >/dev/null && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
  if out=$( systemd-run --user --scope --quiet --collect -p MemoryAccounting=yes -p MemoryMax=64M -p MemorySwapMax=0 \
            --slice=lupin-personas.slice --unit="t25-probe-$$" -- /bin/sh -c 'cut -d: -f3 /proc/self/cgroup' 2>&1 ); then
    val scope_probe "ok: $out"
  else
    val scope_probe "FAILED: $( echo "$out" | head -1 )"
  fi
else
  val scope_probe "skipped (no systemd-run or no XDG_RUNTIME_DIR)"
fi
val systemd_oomd "$( systemctl is-active systemd-oomd 2>/dev/null || echo absent )"
val oomd_user_slice "$( systemctl show user@$( id -u ).service -p ManagedOOMMemoryPressure --value 2>/dev/null || echo unknown )"
val memory_max_user_slice "$( systemctl show user-$( id -u ).slice -p MemoryMax --value 2>/dev/null || echo unknown )"
val ptrace_scope "$( cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null || echo absent )"

hr "kernel unit prerequisites (D65, T08): user unit, linger, the descriptor store"
val systemd_version "$( systemctl --version 2>/dev/null | head -1 || echo absent )"
val linger "$( loginctl show-user "$( id -un )" -p Linger --value 2>/dev/null || echo unknown )"
if command -v systemd-run >/dev/null && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
  # A transient service sees NOTIFY_SOCKET only when it is Type=notify; the store rides the same socket.
  out=$( systemd-run --user --wait --quiet --collect -p Type=notify -p NotifyAccess=all -p FileDescriptorStoreMax=4          /bin/sh -c 'printf "%s" "${NOTIFY_SOCKET:-unset}"; systemd-notify --ready' 2>&1 )     && val notify_socket_probe "ok: $out" || val notify_socket_probe "FAILED: $( echo "$out" | head -1 )"
else
  val notify_socket_probe "skipped (no systemd-run or no XDG_RUNTIME_DIR)"
fi

hr "engines"
for e in agy jetski claude; do
  p=$( command -v "$e" 2>/dev/null ) || { val "$e" absent; continue; }
  val "$e" "$p"
  val "$e.file" "$( file -bL "$p" 2>/dev/null | cut -c1-80 )"
  head -c 200 "$p" 2>/dev/null | grep -q node && val "$e.shebang" "$( head -1 "$p" | cut -c1-80 )"
done
if command -v node >/dev/null; then
  val node "$( node --version )"
  val node_default_heap_GiB "$( node -e 'console.log((require("v8").getHeapStatistics().heap_size_limit/1073741824).toFixed(2))' )"
fi
for f in "$HOME/.gemini/settings.json" "$HOME/.agy/settings.json" "$HOME/.antigravity/settings.json"; do
  [ -f "$f" ] && val "autoConfigureMemory($f)" "$( grep -o '"autoConfigureMemory"[^,}]*' "$f" || echo 'not set (default true)' )"
done
val GEMINI_CLI_NO_RELAUNCH "${GEMINI_CLI_NO_RELAUNCH:-unset}"
val NODE_OPTIONS "${NODE_OPTIONS:-unset}"

hr "live engine processes now (RSS GiB, comm, pid; shared pages counted per process)"
ps -eo rss,comm,pid --sort=-rss | awk 'NR==1 || /node|claude|agy|gemini/ { printf "%8.2f %-12s %s\n", $1/1048576, $2, $3 }' | head -15
