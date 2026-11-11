#!/usr/bin/env bash
# T08 descriptor-store probe (D65, 2026-11-11). Zero tokens; a transient user service, removed at the end.
# Proves on this host's systemd what D65 assumes: a descriptor pushed with FDSTORE=1 comes back to the
# service after `systemctl --user restart`, with its name, and the pipe behind it still holds its bytes.
# Expect: stored_before_restart 2, stored_after_restart 2, a second_run line, descriptor_store ok.
# Run as the persona account on every fleet host; paste the output back.
set -u
unit="t08-store-probe-$$"; out="${XDG_RUNTIME_DIR:?no XDG_RUNTIME_DIR}/$unit.txt"; script="$XDG_RUNTIME_DIR/$unit.py"
cat > "$script" <<'PY'
import array, os, signal, socket, sys, time

def notify( text, descriptors=() ):
    path = os.environ[ "NOTIFY_SOCKET" ]
    path = "\0" + path[ 1: ] if path.startswith( "@" ) else path
    rights = [ ( socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array( "i", descriptors ) ) ] if descriptors else []
    socket.socket( socket.AF_UNIX, socket.SOCK_DGRAM ).sendmsg( [ text.encode() ], rights, 0, path )

mine      = os.environ.get( "LISTEN_PID" ) == str( os.getpid() )
count     = int( os.environ.get( "LISTEN_FDS", "0" ) ) if mine else 0
names     = os.environ.get( "LISTEN_FDNAMES", "" )
with open( sys.argv[ 1 ], "a" ) as log:
    if count == 0:
        read_end, write_end = os.pipe()
        os.write( write_end, b"parked\n" )
        # Both ends are parked. systemd drops a stored descriptor the moment its peer hangs up, so a pipe
        # whose other end dies with this process is gone before the restart (the 2026-11-11 first run).
        # Under the kernel the other end is held by the engine, which lives in its own scope.
        notify( "FDSTORE=1\nFDNAME=probe-out\n", [ read_end ] )
        notify( "FDSTORE=1\nFDNAME=probe-in\n", [ write_end ] )
        log.write( "first_run   pushed probe-out probe-in\n" )
    else:
        read_end = 3 + names.split( ":" ).index( "probe-out" ) if "probe-out" in names.split( ":" ) else None
        data = os.read( read_end, 64 ) if read_end is not None else None
        log.write( f"second_run  inherited={count} names={names} read={data!r}\n" )
signal.signal( signal.SIGUSR1, lambda *_: sys.exit( 0 ) )
notify( "READY=1" )
time.sleep( 60 )
PY
systemd-run --user --quiet --unit="$unit" -p Type=notify -p NotifyAccess=main -p FileDescriptorStoreMax=4 \
  -p RestartKillSignal=SIGUSR1 -- "$( command -v python3 )" "$script" "$out" || { echo "descriptor_store FAILED: the probe service did not start"; exit 1; }
printf '%-34s %s\n' systemd_version "$( systemctl --version | head -1 )"
printf '%-34s %s\n' stored_before_restart "$( systemctl --user show "$unit" -p NFileDescriptorStore --value )"
systemctl --user restart "$unit"
printf '%-34s %s\n' stored_after_restart "$( systemctl --user show "$unit" -p NFileDescriptorStore --value )"
cat "$out"
grep -q "read=b'parked" "$out" && echo "descriptor_store ok" || echo "descriptor_store FAILED: the descriptor did not come back"
systemctl --user stop "$unit" 2>/dev/null; rm -f "$script" "$out"
