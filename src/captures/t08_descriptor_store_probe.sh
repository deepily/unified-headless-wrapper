#!/usr/bin/env bash
# T08 descriptor-store probe (D65, 2026-11-11). Zero tokens; a transient user service, removed at the end.
# Proves on this host's systemd what D65 assumes: a descriptor pushed with FDSTORE=1 comes back to the
# service after `systemctl --user restart`, with its name, and the pipe behind it still holds its bytes.
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
        notify( "FDSTORE=1\nFDNAME=probe-out\n", [ read_end ] )
        log.write( "first_run   pushed probe-out\n" )
    else:
        log.write( f"second_run  inherited={count} names={names} read={os.read( 3, 64 )!r}\n" )
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
grep -q "names=probe-out read=b'parked" "$out" && echo "descriptor_store ok" || echo "descriptor_store FAILED: the descriptor did not come back"
systemctl --user stop "$unit" 2>/dev/null; rm -f "$script" "$out"
