#!/system/bin/sh

LOGFILE="/data/local/tmp/playstore-lock-daemon.log"
PIDFILE="/data/local/tmp/playstore-daemon.pid"

# Stop the background daemon if it is still running
if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill -TERM "$OLD_PID" 2>/dev/null
        sleep 1
        kill -KILL "$OLD_PID" 2>/dev/null
    fi
fi

# Remove temporary runtime files
rm -f "$PIDFILE"
rm -f "$LOGFILE"
rm -f "$LOGFILE.tmp"

# Ensure Play Store package is enabled and unrestricted for user 0
# so normal updates and app behavior resume cleanly
pm enable com.android.vending >/dev/null 2>&1
cmd package set-app-standby-bucket com.android.vending active >/dev/null 2>&1
