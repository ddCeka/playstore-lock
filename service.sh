#!/system/bin/sh
# Compatible with Magisk v20.x - v23.x (Android 8 - 11+)

MODDIR=${0%/*}
LOGFILE="/data/local/tmp/playstore-lock-daemon.log"
PIDFILE="/data/local/tmp/playstore-daemon.pid"

LOCK_MODE="stock"
CUSTOM_TARGET_VER=""
BUNDLE_TYPE="none"

# Wait until Android boot has completely finished
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 5
done

# Check if daemon is already running
if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "  Daemon already running with PID $OLD_PID" >> "$LOGFILE"
        exit 0
    fi
fi

echo $$ > "$PIDFILE"

cleanup() {
    rm -f "$PIDFILE"
    echo "  Daemon exiting, removed PID file" >> "$LOGFILE"
}
trap cleanup EXIT INT TERM

echo "  Play Store Daemon Started (PID: $$, Mode: $LOCK_MODE)" > "$LOGFILE"
echo "  $(date)" >> "$LOGFILE"

sleep 5

# Helper function to install/downgrade either stock single APK or custom single/split APKs
install_target_playstore() {
    if [ "$LOCK_MODE" = "custom" ]; then
        if [ "$BUNDLE_TYPE" = "single" ] && [ -f "$MODDIR/custom_apks/base.apk" ]; then
            pm install -r -d "$MODDIR/custom_apks/base.apk" >> "$LOGFILE" 2>&1
            return $?
        elif [ "$BUNDLE_TYPE" = "split" ] && [ -d "$MODDIR/custom_apks" ]; then
            SESSION_OUT=$(pm install-create -r -d 2>&1)
            SESSION_ID=$(echo "$SESSION_OUT" | sed -n 's/.*\[\([0-9]*\)\].*/\1/p')
            if [ -z "$SESSION_ID" ]; then
                echo "  Failed to create pm install session: $SESSION_OUT" >> "$LOGFILE"
                return 1
            fi
            IDX=0
            for split_apk in "$MODDIR/custom_apks/"*.apk; do
                [ -f "$split_apk" ] || continue
                SIZE=$(wc -c < "$split_apk" | tr -d ' ')
                pm install-write -S "$SIZE" "$SESSION_ID" "split_${IDX}.apk" "$split_apk" >> "$LOGFILE" 2>&1 || {
                    pm install-abandon "$SESSION_ID" >/dev/null 2>&1
                    return 1
                }
                IDX=$((IDX + 1))
            done
            pm install-commit "$SESSION_ID" >> "$LOGFILE" 2>&1
            return $?
        fi
        return 1
    else
        # Stock mode
        if pm install -r -d "$SYSTEM_APK" >> "$LOGFILE" 2>&1; then
            return 0
        else
            pm uninstall -k --user 0 com.android.vending >> "$LOGFILE" 2>&1
            sleep 5
            pm install -r "$SYSTEM_APK" >> "$LOGFILE" 2>&1
            return $?
        fi
    fi
}

if [ "$LOCK_MODE" = "custom" ]; then
    if [ ! -d "$MODDIR/custom_apks" ]; then
        echo "  Custom APK directory missing in module!" >> "$LOGFILE"
        exit 1
    fi
    TARGET_VER="$CUSTOM_TARGET_VER"
    echo "  Custom lock versionCode: $TARGET_VER ($BUNDLE_TYPE)" >> "$LOGFILE"
else
    SYSTEM_APK=$(find /system /system_ext /product /vendor /odm /system_root \
        -type f \( -name "Phonesky.apk" -o -name "Vending.apk" \) 2>/dev/null | head -n 1)

    if [ -z "$SYSTEM_APK" ] || [ ! -f "$SYSTEM_APK" ]; then
        echo "  SYSTEM_APK not found!" >> "$LOGFILE"
        exit 1
    fi

    TARGET_VER=$(dumpsys package com.android.vending 2>/dev/null | awk '/Hidden system packages:/,0' \
        | grep "versionCode=" | head -n 1 | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p')

    if [ -z "$TARGET_VER" ]; then
        TARGET_VER=$(dumpsys package com.android.vending 2>/dev/null \
            | grep "versionCode=" | head -n 1 | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p')
    fi

    if [ -z "$TARGET_VER" ] || [ "$TARGET_VER" -eq 0 ] 2>/dev/null; then
        echo "  Failed to get stock versionCode" >> "$LOGFILE"
        exit 1
    fi
    echo "  Baseline stock versionCode: $TARGET_VER ($SYSTEM_APK)" >> "$LOGFILE"
fi

# Align Play Store version on boot if mismatched
CUR_BOOT_VER=$(dumpsys package com.android.vending 2>/dev/null \
    | grep "versionCode=" | head -n 1 | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p')

if [ -n "$CUR_BOOT_VER" ] && [ "$CUR_BOOT_VER" != "$TARGET_VER" ] 2>/dev/null; then
    echo "  Aligning Play Store on boot ($CUR_BOOT_VER -> $TARGET_VER)..." >> "$LOGFILE"
    install_target_playstore
    sleep 10
fi

CHECK_COUNT=0
SLEEP_INTERVAL=60
JITTER=10
FULL_CHECK_INTERVAL=15
checks_since_full=$FULL_CHECK_INTERVAL
LAST_MTIME=""

APK_PATH=$(pm path com.android.vending 2>/dev/null | head -n 1 | cut -d':' -f2)
if [ -n "$APK_PATH" ] && [ -f "$APK_PATH" ]; then
    LAST_MTIME=$(stat -c %Y "$APK_PATH" 2>/dev/null)
fi

while true; do
    RAND_BYTE=$(od -An -N1 -tu1 /dev/urandom 2>/dev/null | tr -d ' ')
    [ -z "$RAND_BYTE" ] && RAND_BYTE=5
    J=$(( (RAND_BYTE % (JITTER * 2 + 1)) - JITTER ))
    SLEEP_TIME=$(( SLEEP_INTERVAL + J ))
    [ "$SLEEP_TIME" -lt 50 ] && SLEEP_TIME=50
    sleep "$SLEEP_TIME"

    CHECK_COUNT=$((CHECK_COUNT + 1))
    checks_since_full=$((checks_since_full + 1))

    APK_PATH=$(pm path com.android.vending 2>/dev/null | head -n 1 | cut -d':' -f2)

    MTIME_CHANGED=0
    if [ -n "$APK_PATH" ] && [ -f "$APK_PATH" ]; then
        APK_MTIME=$(stat -c %Y "$APK_PATH" 2>/dev/null)
        if [ -n "$APK_MTIME" ] && [ "$APK_MTIME" != "$LAST_MTIME" ]; then
            MTIME_CHANGED=1
            LAST_MTIME="$APK_MTIME"
        fi
    fi

    if [ "$MTIME_CHANGED" -eq 1 ] || [ "$checks_since_full" -ge "$FULL_CHECK_INTERVAL" ]; then
        checks_since_full=0
        CUR_VER=$(dumpsys package com.android.vending 2>/dev/null \
            | grep "versionCode=" | head -n 1 | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p')
    else
        continue
    fi

    if [ -z "$CUR_VER" ]; then
        echo "  Check #$CHECK_COUNT - failed to read versionCode" >> "$LOGFILE"
        continue
    fi

    echo "  Check #$CHECK_COUNT - versionCode: $CUR_VER (target=$TARGET_VER, mt_changed=$MTIME_CHANGED)" >> "$LOGFILE"

    if [ "$CUR_VER" -gt "$TARGET_VER" ] 2>/dev/null; then
        echo "  Self-update detected! ($CUR_VER > $TARGET_VER)" >> "$LOGFILE"
        echo "  Restoring target Play Store ($TARGET_VER)..." >> "$LOGFILE"

        if install_target_playstore; then
            echo "  Successfully restored to $TARGET_VER" >> "$LOGFILE"
        else
            echo "  Restoration failed on check #$CHECK_COUNT" >> "$LOGFILE"
        fi

        sleep 5
        APK_PATH=$(pm path com.android.vending 2>/dev/null | head -n 1 | cut -d':' -f2)
        [ -f "$APK_PATH" ] && LAST_MTIME=$(stat -c %Y "$APK_PATH" 2>/dev/null)
    fi

    if [ $((CHECK_COUNT % 120)) -eq 0 ] && [ -f "$LOGFILE" ]; then
        tail -n 500 "$LOGFILE" > "$LOGFILE.tmp" && mv "$LOGFILE.tmp" "$LOGFILE"
    fi
done
