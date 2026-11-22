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

if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        pkill -P "$OLD_PID" 2>/dev/null
        kill -TERM "$OLD_PID" 2>/dev/null
        sleep 1
        kill -KILL "$OLD_PID" 2>/dev/null
    fi
fi

rm -rf "$PIDFILE" "$LOGFILE" "$LOGFILE.tmp" /data/local/tmp/playstore_stage_*

SELF_UPDATE_COMPONENTS="
com.android.vending/com.google.android.finsky.services.DailyHygiene
com.android.vending/com.google.android.finsky.hygiene.DailyHygiene\$DailyHygieneService
com.android.vending/com.google.android.finsky.selfupdate.SelfUpdateService
com.android.vending/com.google.android.finsky.selfupdate.SelfUpdateReceiver
com.android.vending/com.google.android.finsky.instantapps.hint.AppPreloadHygieneService
com.android.vending/com.google.android.finsky.instantapps.InstantAppHygieneService
"

# Reset app standby bucket and restore components after boot completes
(
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 5
    done
    for comp in $SELF_UPDATE_COMPONENTS; do
        pm default-state --user 0 "$comp" >/dev/null 2>&1
    done
    cmd package set-app-standby-bucket --user 0 com.android.vending active >/dev/null 2>&1
) &
