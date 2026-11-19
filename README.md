# Play Store Version-Lock Daemon (Magisk Module)

A lightweight background shell daemon for rooted Android devices that prevents the Google Play Store (`com.android.vending`) from silently self-updating. It automatically detects silent background updates and downgrades the app back to either your ROM's factory stock version or a custom APK bundle.

## Features

* **Dual Lock Modes:** Supports locking to the device's built-in system APK (`stock` mode) or a user-supplied APK/App Bundle (`custom` mode).
* **Split APK Support:** Handles both single `base.apk` files and multi-part split APK bundles using Android's `pm install-create` session manager.
* **Boot-Time Alignment:** Automatically checks and aligns the installed Play Store version right after Android finishes booting.
* **Low-Overhead Monitoring:** Uses APK file modification timestamps (`mtime`) paired with randomized sleep jitter (`50–70s`) to minimize CPU wakeups and battery drain, running a full `dumpsys` check only when file changes occur or every 15 cycles.
* **Self-Cleaning Logs & PID Management:** Prevents duplicate daemon instances via a PID lockfile and automatically trims logs every 120 checks to preserve storage.

## Compatibility & Prerequisites

* **Root Solution:** Magisk `v20.x` – `v23.x` (or compatible root managers supporting `service.sh` boot scripts)
* **Android Version:** Android 8.0 (Oreo) through Android 11+
* **Required Binaries:** Standard Android/BusyBox shell utilities (`pm`, `dumpsys`, `stat`, `find`, `awk`, `sed`, `od`)

## Configuration

Before deploying the script, open `service.sh` and adjust the configuration variables near the top of the file:

```sh
LOCK_MODE="stock"          # Options: "stock" | "custom"
CUSTOM_TARGET_VER=""       # Required for "custom" mode (e.g., "83511210")
BUNDLE_TYPE="none"         # Options: "none" | "single" | "split"
```

### Configuration Modes

| Variable | Value | Description |
| :--- | :--- | :--- |
| `LOCK_MODE` | `"stock"` | Automatically locates `Phonesky.apk` or `Vending.apk` on system partitions (`/system`, `/product`, `/system_ext`, etc.) and locks to its factory `versionCode`. |
| `LOCK_MODE` | `"custom"` | Locks to a specific Play Store version located inside `$MODDIR/customapks/`. |
| `CUSTOM_TARGET_VER` | `<integer>` | The exact integer `versionCode` of your custom APK(s) (ignored in `stock` mode). |
| `BUNDLE_TYPE` | `"single"` | Installs `$MODDIR/customapks/base.apk` using `pm install -r -d`. |
| `BUNDLE_TYPE` | `"split"` | Installs all `*.apk` files inside `$MODDIR/customapks/` as a staged multi-APK session. |

## Installation

### Option 1: Flash via Magisk Manager (Recommended)
1. Download the latest `PlayStore-Version-Lock-vX.X.X.zip` release (or package the repository files into a `.zip` archive).
2. *(Optional — Custom Mode)* Before flashing, place your target Play Store `base.apk` (and any split `.apk` files) inside a `customapks/` folder at the root of the ZIP.
3. Open **Magisk Manager** -> **Modules** -> **Install from storage**.
4. Select the `.zip` file and wait for the installer to finish.
5. **Reboot** your device.

> **Note:** During flashing, `customize.sh` automatically detects whether `customapks/` is present and configures `service.sh` accordingly.

### Option 2: Manual Setup (Advanced)
If deploying manually without flashing a ZIP, copy `module.prop`, `service.sh`, and `uninstall.sh` into `/data/adb/modules/playstore-version-lock/`, set executable permissions (`chmod 0755 service.sh uninstall.sh`), and reboot.

## Uninstallation

1. Open **Magisk Manager** -> **Modules**.
2. Tap **Remove** on **Play Store Version-Lock Daemon**.
3. **Reboot** your device.

On reboot, `uninstall.sh` automatically stops the background daemon, deletes temporary log/PID files from `/data/local/tmp/`, and restores normal Play Store updates.

### Directory Layout (Stock Mode)
```text
/data/adb/modules/playstore-lock/
├── module.prop
└── service.sh
```

### Directory Layout (Custom Mode)
If using `LOCK_MODE="custom"`, create a `customapks` folder in the same directory as the script:

```text
/data/adb/modules/playstore-lock/
├── module.prop
├── service.sh
└── customapks/
    ├── base.apk                  # Required for BUNDLE_TYPE="single"
    └── split_config.*.apk        # Additional splits for BUNDLE_TYPE="split"
```

Reboot your device after placing the files. The daemon will wait until `sys.boot_completed=1` before starting.

## Monitoring & Logs

The daemon writes runtime status, downgrade events, and error output to `/data/local/tmp/`:

* **Log File:** `/data/local/tmp/playstore-lock-daemon.log` *(automatically capped at the last 500 lines)*
* **PID File:** `/data/local/tmp/playstore-daemon.pid`

To monitor the daemon in real time via ADB or a root terminal:
```bash
su -c "tail -f /data/local/tmp/playstore-lock-daemon.log"
```

To verify the daemon is currently active:
```bash
su -c "ps -p \$(cat /data/local/tmp/playstore-daemon.pid)"
```

## Troubleshooting

* **`SYSTEM_APK not found!` in log:** Your ROM stores the Play Store under a non-standard APK name or path. Switch to `LOCK_MODE="custom"` and supply the APK manually in `customapks/`.
* **`Failed to get stock versionCode`:** Ensure `com.android.vending` is not completely uninstalled or frozen for user `0` before booting.
* **Downgrade fails repeatedly:** If a direct downgrade (`pm install -r -d`) is rejected by Android due to signature or SDK mismatches, `stock` mode automatically falls back to `pm uninstall -k --user 0 com.android.vending` followed by a clean reinstall. Ensure your custom APKs share the official Google signing certificate.