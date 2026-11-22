#!/system/bin/sh
# Compatible with Magisk v20.4 - v23.x (Android 8 - 11+)

export ASH_STANDALONE=1
for bb_dir in /sbin/.magisk/busybox /debug_ramdisk/.magisk/busybox /data/adb/magisk; do
    if [ -d "$bb_dir" ]; then
        case ":$PATH:" in
            *":$bb_dir:"*) ;;
            *) export PATH="$bb_dir:$PATH" ;;
        esac
    fi
done

MODDIR=${0%/*}
LOGFILE="/data/local/tmp/playstore-lock-daemon.log"
PIDFILE="/data/local/tmp/playstore-daemon.pid"

LOCK_MODE="stock"
CUSTOM_TARGET_VER=""
BUNDLE_TYPE="none"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 5
done

if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        log "Daemon already running with PID $OLD_PID"
        exit 0
    fi
fi

echo $$ > "$PIDFILE"

cleanup() {
    rm -rf "$PIDFILE" "$LOGFILE" "/data/local/tmp/playstore_stage_$$"
    log "Daemon exiting, removed PID file and logs"
}
trap cleanup EXIT INT TERM

: > "$LOGFILE"
log "Environment: PATH=$PATH | stat=$(command -v stat) | od=$(command -v od)"

sleep 5

# Check primary user (user 0) specifically so Work Profiles/Dual Apps don't cause false pauses
is_playstore_disabled() {
    pm list packages -d --user 0 2>/dev/null | grep -q "^package:com\.android\.vending$"
}

SELF_UPDATE_COMPONENTS="
com.android.vending/com.google.android.finsky.services.DailyHygiene
com.android.vending/com.google.android.finsky.hygiene.DailyHygiene\$DailyHygieneService
com.android.vending/com.google.android.finsky.selfupdate.SelfUpdateService
com.android.vending/com.google.android.finsky.selfupdate.SelfUpdateReceiver
com.android.vending/com.google.android.finsky.instantapps.hint.AppPreloadHygieneService
com.android.vending/com.google.android.finsky.instantapps.InstantAppHygieneService
"

disable_self_update_components() {
    for comp in $SELF_UPDATE_COMPONENTS; do
        pm disable --user 0 "$comp" >/dev/null 2>&1
    done
    log "Applied self-update component restrictions"
}

restore_self_update_components() {
    for comp in $SELF_UPDATE_COMPONENTS; do
        pm default-state --user 0 "$comp" >/dev/null 2>&1
    done
    log "Restored self-update component default states"
}

get_installed_ver() {
    dumpsys package com.android.vending 2>/dev/null \
        | awk '/^Packages:/,/^Hidden system packages:/' \
        | grep -m 1 "versionCode=" \
        | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p'
}

# Helper function to install/downgrade either stock single APK or custom single/split APKs
install_target_playstore() {
    if [ "$LOCK_MODE" = "custom" ]; then
        STAGE_DIR="/data/local/tmp/playstore_stage_$$"
        rm -rf "$STAGE_DIR"
        mkdir -p "$STAGE_DIR" || {
            log "Failed to create staging directory: $STAGE_DIR"
            return 1
        }
        chmod 0755 "$STAGE_DIR"

        if [ "$BUNDLE_TYPE" = "single" ] && [ -f "$MODDIR/customapks/base.apk" ]; then
            cp -f "$MODDIR/customapks/base.apk" "$STAGE_DIR/base.apk" || {
                rm -rf "$STAGE_DIR"
                return 1
            }
            chmod 0644 "$STAGE_DIR/base.apk"
            chcon u:object_r:shell_data_file:s0 "$STAGE_DIR/base.apk" >/dev/null 2>&1

            pm install -r -d --user 0 "$STAGE_DIR/base.apk" >> "$LOGFILE" 2>&1
            INSTALL_RET=$?
            rm -rf "$STAGE_DIR"
            return $INSTALL_RET

        elif [ "$BUNDLE_TYPE" = "split" ] && [ -d "$MODDIR/customapks" ]; then
            SESSION_OUT=$(pm install-create -r -d --user 0 2>&1)
            SESSION_ID=$(echo "$SESSION_OUT" | sed -n 's/.*\[\([0-9]*\)\].*/\1/p')
            if [ -z "$SESSION_ID" ]; then
                log "Failed to create pm install session: $SESSION_OUT"
                rm -rf "$STAGE_DIR"
                return 1
            fi
            for split_apk in "$MODDIR/customapks/"*.apk; do
                [ -f "$split_apk" ] || continue
                NAME=$(basename "$split_apk")
                STAGED_APK="$STAGE_DIR/$NAME"
                cp -f "$split_apk" "$STAGED_APK" || {
                    pm install-abandon "$SESSION_ID" >/dev/null 2>&1
                    rm -rf "$STAGE_DIR"
                    return 1
                }
                chmod 0644 "$STAGED_APK"
                chcon u:object_r:shell_data_file:s0 "$STAGED_APK" >/dev/null 2>&1

                SIZE=$(wc -c < "$STAGED_APK" | tr -d ' ')
                pm install-write -S "$SIZE" "$SESSION_ID" "$NAME" "$STAGED_APK" >> "$LOGFILE" 2>&1 || {
                    pm install-abandon "$SESSION_ID" >/dev/null 2>&1
                    rm -rf "$STAGE_DIR"
                    return 1
                }
            done
            pm install-commit "$SESSION_ID" >> "$LOGFILE" 2>&1
            INSTALL_RET=$?
            rm -rf "$STAGE_DIR"
            return $INSTALL_RET
        fi

        rm -rf "$STAGE_DIR"
        return 1
    else
        # Stock mode: try direct downgrade for user 0 first
        if pm install -r -d --user 0 "$SYSTEM_APK" >> "$LOGFILE" 2>&1; then
            return 0
        else
            pm uninstall -k --user 0 com.android.vending >> "$LOGFILE" 2>&1
            sleep 3
            if pm install-existing --user 0 com.android.vending >> "$LOGFILE" 2>&1; then
                return 0
            fi
            pm install -r --user 0 "$SYSTEM_APK" >> "$LOGFILE" 2>&1
            return $?
        fi
    fi
}

if [ "$LOCK_MODE" = "custom" ]; then
    if [ ! -d "$MODDIR/customapks" ]; then
        log "Custom APK directory missing in module!"
        exit 1
    fi
    TARGET_VER="$CUSTOM_TARGET_VER"
    if [ -z "$TARGET_VER" ] || [ "$TARGET_VER" -eq 0 ] 2>/dev/null; then
        log "CUSTOM_TARGET_VER is empty or invalid!"
        exit 1
    fi
    log "Custom lock versionCode: $TARGET_VER ($BUNDLE_TYPE)"
else
    SYSTEM_APK=$(find /system /system_ext /product /vendor /odm /system_root \
        -type f \( -name "Phonesky.apk" -o -name "Vending.apk" \) 2>/dev/null | head -n 1)

    if [ -z "$SYSTEM_APK" ] || [ ! -f "$SYSTEM_APK" ]; then
        log "SYSTEM_APK not found!"
        exit 1
    fi

    TARGET_VER=$(dumpsys package com.android.vending 2>/dev/null \
        | awk '/Hidden system packages:/,0' \
        | grep -m 1 "versionCode=" \
        | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p')

    [ -z "$TARGET_VER" ] && TARGET_VER=$(get_installed_ver)

    if [ -z "$TARGET_VER" ] || [ "$TARGET_VER" -eq 0 ] 2>/dev/null; then
        log "Failed to get stock versionCode"
        exit 1
    fi
    log "Baseline stock versionCode: $TARGET_VER ($SYSTEM_APK)"
fi

# Align Play Store version on boot if mismatched (only when enabled)
if ! is_playstore_disabled; then
    CUR_BOOT_VER=$(get_installed_ver)
    if [ -n "$CUR_BOOT_VER" ] && [ "$CUR_BOOT_VER" != "$TARGET_VER" ] 2>/dev/null; then
        log "Aligning Play Store on boot ($CUR_BOOT_VER -> $TARGET_VER)..."
        install_target_playstore
        sleep 10
    fi
    disable_self_update_components
else
    log "Play Store is disabled at boot; skipping initial alignment."
fi

CHECK_COUNT=0
SLEEP_INTERVAL=60
JITTER=10
FULL_CHECK_INTERVAL=30
checks_since_full=$FULL_CHECK_INTERVAL
LAST_MTIME=""
LAST_PKG_XML_MTIME=""
WAS_DISABLED=0

PACKAGES_XML="/data/system/packages.xml"
[ -f "$PACKAGES_XML" ] && LAST_PKG_XML_MTIME=$(stat -c %Y "$PACKAGES_XML" 2>/dev/null)

APK_PATH=$(pm path com.android.vending 2>/dev/null | head -n 1 | cut -d':' -f2)
[ -n "$APK_PATH" ] && [ -f "$APK_PATH" ] && LAST_MTIME=$(stat -c %Y "$APK_PATH" 2>/dev/null)

while true; do
    RAND_BYTE=$(od -An -N1 -tu1 /dev/urandom 2>/dev/null | tr -d ' ')
    [ -z "$RAND_BYTE" ] && RAND_BYTE=5
    J=$(( (RAND_BYTE % (JITTER * 2 + 1)) - JITTER ))
    SLEEP_TIME=$(( SLEEP_INTERVAL + J ))
    [ "$SLEEP_TIME" -lt 50 ] && SLEEP_TIME=50
    sleep "$SLEEP_TIME"

    if [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ] || [ ! -d "$MODDIR" ]; then
        log "Module disabled or marked for removal. Restoring components and stopping daemon..."
        restore_self_update_components
        exit 0
    fi

    CHECK_COUNT=$((CHECK_COUNT + 1))
    checks_since_full=$((checks_since_full + 1))

    PKG_DB_CHANGED=0
    if [ -f "$PACKAGES_XML" ]; then
        CUR_PKG_XML_MTIME=$(stat -c %Y "$PACKAGES_XML" 2>/dev/null)
        if [ -n "$CUR_PKG_XML_MTIME" ] && [ "$CUR_PKG_XML_MTIME" != "$LAST_PKG_XML_MTIME" ]; then
            PKG_DB_CHANGED=1
            LAST_PKG_XML_MTIME="$CUR_PKG_XML_MTIME"
        fi
    fi

    if [ "$PKG_DB_CHANGED" -eq 1 ] || [ "$WAS_DISABLED" -eq 1 ] || [ "$checks_since_full" -ge "$FULL_CHECK_INTERVAL" ]; then
        if is_playstore_disabled; then
            if [ "$WAS_DISABLED" -eq 0 ]; then
                log "Play Store is disabled. Pausing checks until re-enabled..."
                WAS_DISABLED=1
            fi
            sleep 60
            continue
        elif [ "$WAS_DISABLED" -eq 1 ]; then
            log "Play Store re-enabled! Resuming version checks..."
            WAS_DISABLED=0
            checks_since_full=$FULL_CHECK_INTERVAL
        fi
    fi

    MTIME_CHANGED=0
    # If cached APK_PATH vanished (moved during update) or packages.xml changed, refresh APK_PATH
    if [ -z "$APK_PATH" ] || [ ! -f "$APK_PATH" ] || [ "$PKG_DB_CHANGED" -eq 1 ]; then
        NEW_APK_PATH=$(pm path com.android.vending 2>/dev/null | head -n 1 | cut -d':' -f2)
        if [ -n "$NEW_APK_PATH" ] && [ "$NEW_APK_PATH" != "$APK_PATH" ]; then
            APK_PATH="$NEW_APK_PATH"
            MTIME_CHANGED=1
        fi
    fi

    if [ -n "$APK_PATH" ] && [ -f "$APK_PATH" ]; then
        APK_MTIME=$(stat -c %Y "$APK_PATH" 2>/dev/null)
        if [ -n "$APK_MTIME" ] && [ "$APK_MTIME" != "$LAST_MTIME" ]; then
            MTIME_CHANGED=1
            LAST_MTIME="$APK_MTIME"
        fi
    fi

    if [ "$MTIME_CHANGED" -eq 1 ] || [ "$checks_since_full" -ge "$FULL_CHECK_INTERVAL" ]; then
        checks_since_full=0
        CUR_VER=$(get_installed_ver)
    else
        continue
    fi

    if [ -z "$CUR_VER" ]; then
        log "Check #$CHECK_COUNT - failed to read versionCode"
        continue
    fi

    log "Check #$CHECK_COUNT - versionCode: $CUR_VER (target=$TARGET_VER, mt_changed=$MTIME_CHANGED)"

    if [ "$CUR_VER" -gt "$TARGET_VER" ] 2>/dev/null; then
        log "Self-update detected! ($CUR_VER > $TARGET_VER)"
        log "Restoring target Play Store ($TARGET_VER)..."

        if install_target_playstore; then
            log "Successfully restored to $TARGET_VER"
            disable_self_update_components
        else
            log "Restoration failed on check #$CHECK_COUNT"
        fi

        sleep 5
        APK_PATH=$(pm path com.android.vending 2>/dev/null | head -n 1 | cut -d':' -f2)
        [ -f "$APK_PATH" ] && LAST_MTIME=$(stat -c %Y "$APK_PATH" 2>/dev/null)
        [ -f "$PACKAGES_XML" ] && LAST_PKG_XML_MTIME=$(stat -c %Y "$PACKAGES_XML" 2>/dev/null)
    fi

    if [ $((CHECK_COUNT % 120)) -eq 0 ] && [ -f "$LOGFILE" ]; then
        tail -n 500 "$LOGFILE" > "$LOGFILE.tmp" && mv "$LOGFILE.tmp" "$LOGFILE"
    fi
done
