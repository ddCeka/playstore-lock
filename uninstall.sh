#!/system/bin/sh
# Compatible with Magisk v20.4 - v23.x (Android 8 - 11+)

LOGFILE="/data/local/tmp/playstore-lock-daemon.log"
PIDFILE="/data/local/tmp/playstore-daemon.pid"

# Enforce Magisk BusyBox environment for Magisk v20.4 - v23.x
export ASH_STANDALONE=1
for bb_dir in /sbin/.magisk/busybox /debug_ramdisk/.magisk/busybox /data/adb/magisk; do
    if [ -d "$bb_dir" ]; then
        case ":$PATH:" in
            *":$bb_dir:"*) ;;
            *) export PATH="$bb_dir:$PATH" ;;
        esac
    fi
done

# Stop the background daemon and any child sleep processes
if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        pkill -P "$OLD_PID" 2>/dev/null
        kill -TERM "$OLD_PID" 2>/dev/null
        sleep 1
        kill -KILL "$OLD_PID" 2>/dev/null
    fi
fi

# Remove temporary runtime files
rm -f "$PIDFILE" "$LOGFILE" "$LOGFILE.tmp"

# Reset app standby bucket only after Android boot is completed
# (Avoids blocking early boot when Magisk executes uninstall.sh)
(
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 5
    done
    cmd package set-app-standby-bucket com.android.vending active >/dev/null 2>&1
) &
