#!/system/bin/sh

SKIPUNZIP=0

ui_print "********************************************"
ui_print "       Play Store Version-Lock Daemon       "
ui_print "********************************************"

# Check Android API level (Android 8.0 Oreo = API 26+)
if [ "$API" -lt 26 ]; then
    abort "! Unsupported Android version (API $API). Requires Android 8.0+."
fi

# Verify service.sh exists in the extracted module directory
if [ ! -f "$MODPATH/service.sh" ]; then
    abort "! Missing service.sh inside module archive!"
fi

# Auto-detect if custom APKs were bundled inside the ZIP
if [ -d "$MODPATH/custom_apks" ] && [ -n "$(ls -A "$MODPATH/custom_apks/"*.apk 2>/dev/null)" ]; then
    APK_COUNT=$(ls -1 "$MODPATH/custom_apks/"*.apk 2>/dev/null | wc -l)
    ui_print "- Custom APKs detected ($APK_COUNT file(s))."

    if [ "$APK_COUNT" -eq 1 ] && [ -f "$MODPATH/custom_apks/base.apk" ]; then
        DETECTED_BUNDLE="single"
    elif [ "$APK_COUNT" -gt 1 ]; then
        DETECTED_BUNDLE="split"
    else
        abort "! Single custom APK must be named 'base.apk' inside custom_apks/."
    fi

    # Extract versionCode from base.apk using aapt/aapt2 if available
    CUSTOM_VER=""
    if command -v aapt >/dev/null 2>&1; then
        CUSTOM_VER=$(aapt dump badging "$MODPATH/custom_apks/base.apk" 2>/dev/null | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p")
    elif command -v aapt2 >/dev/null 2>&1; then
        CUSTOM_VER=$(aapt2 dump badging "$MODPATH/custom_apks/base.apk" 2>/dev/null | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p")
    fi

    # Patch service.sh automatically if a versionCode was detected
    if [ -n "$CUSTOM_VER" ]; then
        ui_print "- Detected custom versionCode: $CUSTOM_VER ($DETECTED_BUNDLE)"
        sed -i 's/^LOCK_MODE=.*/LOCK_MODE="custom"/' "$MODPATH/service.sh"
        sed -i "s/^CUSTOM_TARGET_VER=.*/CUSTOM_TARGET_VER=\"$CUSTOM_VER\"/" "$MODPATH/service.sh"
        sed -i "s/^BUNDLE_TYPE=.*/BUNDLE_TYPE=\"$DETECTED_BUNDLE\"/" "$MODPATH/service.sh"
    else
        ui_print "! Warning: Could not auto-detect versionCode from base.apk."
        ui_print "! Make sure LOCK_MODE, CUSTOM_TARGET_VER, and BUNDLE_TYPE are set in service.sh."
    fi
else
    ui_print "- No custom APKs bundled. Configuring for STOCK mode..."
    SYSTEM_APK=$(find /system /system_ext /product /vendor /odm /system_root \
        -type f \( -name "Phonesky.apk" -o -name "Vending.apk" \) 2>/dev/null | head -n 1)

    if [ -z "$SYSTEM_APK" ]; then
        ui_print "! Warning: Stock Phonesky.apk/Vending.apk not found on system partitions."
        ui_print "! Stock mode may fail unless custom_apks are configured later."
    else
        ui_print "- Found stock APK: $SYSTEM_APK"
    fi
fi

# Set required permissions for Magisk service and uninstall execution
ui_print "- Setting permissions..."
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755
[ -f "$MODPATH/uninstall.sh" ] && set_perm "$MODPATH/uninstall.sh" 0 0 0755

ui_print "- Installation complete! Reboot your device to start the daemon."
