#!/system/bin/sh
# Compatible with Magisk v20.4 - v23.x (Android 8 - 11+)

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

# Pure BusyBox binary AndroidManifest.xml versionCode extractor
extract_version_code() {
    APK_FILE="$1"
    [ ! -f "$APK_FILE" ] && return 1

    # Try aapt/aapt2 first if present on host/device
    if command -v aapt >/dev/null 2>&1; then
        VER=$(aapt dump badging "$APK_FILE" 2>/dev/null | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p")
        [ -n "$VER" ] && echo "$VER" && return 0
    elif command -v aapt2 >/dev/null 2>&1; then
        VER=$(aapt2 dump badging "$APK_FILE" 2>/dev/null | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p")
        [ -n "$VER" ] && echo "$VER" && return 0
    fi

    # Fallback: parse AXML versionCode attribute (resId 0x0101021b -> bytes 1b 02 01 01)
    # In AXML attributes: [nameNs(4)][nameIdx(4)][rawValue(4)][size(2)][0][dataType(1)][data(4)]
    # Here we match the 4-byte little-endian resource ID 1b020101 in the resource ID table or attribute
    HEX_STREAM=$(unzip -p "$APK_FILE" AndroidManifest.xml 2>/dev/null | od -An -tx1 -v | tr -d ' \n')
    [ -z "$HEX_STREAM" ] && return 1

    # Locate resource ID 0x0101021b (1b020101 in little-endian) in the XML resource map
    PREFIX="${HEX_STREAM%%1b020101*}"
    if [ "$PREFIX" != "$HEX_STREAM" ]; then
        # Resource map starts after XML header (8 bytes = 16 hex chars) + StringPool chunk
        SP_SIZE_HEX=$(echo "$HEX_STREAM" | cut -c 25-32)
        B1=$(echo "$SP_SIZE_HEX" | cut -c 1-2)
        B2=$(echo "$SP_SIZE_HEX" | cut -c 3-4)
        B3=$(echo "$SP_SIZE_HEX" | cut -c 5-6)
        B4=$(echo "$SP_SIZE_HEX" | cut -c 7-8)
        SP_SIZE=$((0x${B4}${B3}${B2}${B1}))
        RES_MAP_START=$(( 16 + SP_SIZE * 2 + 16 ))
        OFFSET_HEX=$(( ${#PREFIX} - RES_MAP_START ))
        if [ "$OFFSET_HEX" -ge 0 ]; then
            ATTR_IDX=$(( OFFSET_HEX / 8 ))
            IDX_LE=$(printf "%08x" "$ATTR_IDX" | sed 's/\(..\)\(..\)\(..\)\(..\)/\4\3\2\1/')
            # Match attribute entry with nameIdx == IDX_LE and dataType == 0x10 (TYPE_INT_DEC)
            ATTR_MATCH=$(echo "$HEX_STREAM" | grep -o "${IDX_LE}ffffffff08000010........" | head -n 1)
            if [ -n "$ATTR_MATCH" ]; then
                VAL_HEX=$(echo "$ATTR_MATCH" | cut -c 25-32)
                V1=$(echo "$VAL_HEX" | cut -c 1-2)
                V2=$(echo "$VAL_HEX" | cut -c 3-4)
                V3=$(echo "$VAL_HEX" | cut -c 5-6)
                V4=$(echo "$VAL_HEX" | cut -c 7-8)
                VER_NUM=$((0x${V4}${V3}${V2}${V1}))
                if [ "$VER_NUM" -gt 10000000 ] 2>/dev/null; then
                    echo "$VER_NUM"
                    return 0
                fi
            fi
        fi
    fi
    return 1
}

# Auto-detect if custom APKs were bundled inside the ZIP
if [ -d "$MODPATH/customapks" ] && [ -n "$(ls -A "$MODPATH/customapks/"*.apk 2>/dev/null)" ]; then
    APK_COUNT=$(ls -1 "$MODPATH/customapks/"*.apk 2>/dev/null | wc -l)
    ui_print "- Custom APKs detected ($APK_COUNT file(s))."

    if [ "$APK_COUNT" -eq 1 ] && [ -f "$MODPATH/customapks/base.apk" ]; then
        DETECTED_BUNDLE="single"
    elif [ "$APK_COUNT" -gt 1 ] && [ -f "$MODPATH/customapks/base.apk" ]; then
        DETECTED_BUNDLE="split"
    else
        abort "! Custom APK bundle must include 'base.apk' inside customapks/."
    fi

    CUSTOM_VER=$(extract_version_code "$MODPATH/customapks/base.apk")

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
        ui_print "! Stock mode may fail unless customapks are configured later."
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
