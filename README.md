# Play Store Self-Update Lock (Magisk Module)

A lightweight background shell daemon for rooted Android devices that prevents the Google Play Store (`com.android.vending`) from silently self-updating. It combines proactive self-update service restrictions with a low-overhead monitoring loop to automatically revert background updates back to either your ROM's factory stock baseline or a custom APK bundle.

## Features

* **Dual Lock Modes:** Supports locking to the device's built-in system APK (`stock` mode) or a user-supplied APK/App Bundle (`custom` mode).
* **Zero-Dependency Custom APK Auto-Configuration:** `customize.sh` automatically detects single or split APKs inside `customapks/` during flashing and extracts `versionCode` directly from `AndroidManifest.xml` using pure BusyBox utilities.
* **SELinux-Safe Split & Single APK Staging:** Temporarily stages custom APKs in `/data/local/tmp/` with `0644` permissions and `u:object_r:shell_data_file:s0` context before running `pm install` or `pm install-create`, preventing SELinux denials on strict Android 10–11 kernels.
* **Proactive Component Restrictions:** Disables known Play Store self-update and Instant App hygiene services (`DailyHygiene`, `SelfUpdateService`, `AppPreloadHygieneService`, `InstantAppHygieneService`) for user `0` on boot and after every restoration.
* **Near-Zero Binder Overhead:** Monitors `/data/system/packages.xml` and cached APK paths via lightweight kernel `stat` checks paired with randomized sleep jitter (`50–70s`), invoking `pm`/`dumpsys` only when package changes occur or every 30 cycles.
* **Smart Pause & Live Magisk State Handling:** Automatically pauses checks while Play Store is disabled for user `0`, resumes immediately when re-enabled, and exits cleanly while restoring default component states if the module is toggled off (`disable`) or marked for removal (`remove`) in Magisk Manager.
* **Multi-User & Work Profile Isolation:** Explicitly targets `--user 0` so Work Profiles (Shelter, Island, MDM) or Dual Apps do not interfere with primary profile protection.

## Compatibility & Prerequisites

* **Root Solution:** Magisk `v20.4` – `v23.x` (enforces `ASH_STANDALONE=1` and Magisk BusyBox `PATH` resolution)
* **Android Version:** Android 8.0 (Oreo / API 26) through Android 11+
* **Required Binaries:** Magisk built-in BusyBox applets (`stat`, `od`, `awk`, `sed`, `grep`, `unzip`, `pkill`) and Android `pm`/`dumpsys`

## Installation

### Option 1: Download from GitHub Releases (Stock Mode)
1. Download the latest `playstore_update_lock-v*.zip` archive from the **Releases** page.
2. Open **Magisk Manager** -> **Modules** -> **Install from storage**.
3. Select the downloaded `.zip` file and wait for installation to finish.
4. **Reboot** your device.

### Option 2: Custom APK / App Bundle Lock
If you want to lock the Play Store to a specific version instead of your ROM's factory stock APK:
1. Extract the release `.zip` (or clone this repository).
2. Create a `customapks/` folder at the root of the module directory and place your target Play Store `base.apk` inside it (along with any `split_config.*.apk` files if using an App Bundle).
3. Re-zip the module contents.
4. Flash the resulting `.zip` via **Magisk Manager** -> **Modules** -> **Install from storage**, then **reboot**.

> **Note:** During flashing, `customize.sh` automatically detects `customapks/`, extracts the `versionCode` from `base.apk`, and patches `service.sh` for `custom` mode.

## Repository & Installed Layout

### Repository Structure
```text
.
├── META-INF/
│   └── com/google/android/
│       ├── update-binary
│       └── updater-script
├── customize.sh
├── module.prop
├── README.md
├── service.sh
└── uninstall.sh
```

### Installed Module Layout (`/data/adb/modules/playstore_update_lock/`)
```text
/data/adb/modules/playstore_update_lock/
├── module.prop
├── service.sh
├── uninstall.sh
└── customapks/                   # Present only when bundled for custom mode
    ├── base.apk                  # Required for single & split bundles
    └── split_config.*.apk        # Optional split APKs
```

## Manual Configuration Reference

`customize.sh` configures `service.sh` automatically during installation, or you can edit the variables at the top of `/data/adb/modules/playstore_update_lock/service.sh` directly:

| Variable | Default | Description |
| :--- | :--- | :--- |
| `LOCK_MODE` | `"stock"` | `"stock"` locks to the factory APK on `/system`, `/product`, or `/system_ext`; `"custom"` locks to `$MODDIR/customapks/`. |
| `CUSTOM_TARGET_VER` | `""` | Exact integer `versionCode` of `customapks/base.apk` (auto-filled by `customize.sh` in `custom` mode). |
| `BUNDLE_TYPE` | `"none"` | `"none"` (stock mode), `"single"` (`base.apk` only), or `"split"` (`base.apk` + split APKs). |

## Uninstallation

1. Open **Magisk Manager** -> **Modules**.
2. Tap **Remove** on **Play Store Self-Update Lock**.
3. **Reboot** your device.

When toggled off or removed, the daemon immediately restores default component states (`pm default-state --user 0`) and exits cleanly. On reboot, `uninstall.sh` ensures any lingering processes are stopped, deletes temporary files from `/data/local/tmp/`, and resets the Play Store app standby bucket to `active`.

## Monitoring & Logs

Runtime logs and PID tracking are stored in `/data/local/tmp/`:

* **Log File:** `/data/local/tmp/playstore-lock-daemon.log` *(automatically trimmed to the last 500 lines every 120 checks)*
* **PID File:** `/data/local/tmp/playstore-daemon.pid`

Follow the daemon log live via ADB or a root shell:
```bash
su -c "tail -f /data/local/tmp/playstore-lock-daemon.log"
```

Verify the daemon process is running:
```bash
su -c "ps -p \$(cat /data/local/tmp/playstore-daemon.pid)"
```

## Troubleshooting

* **`SYSTEM_APK not found!` in log:** Your ROM stores the Play Store under a non-standard APK name or partition path. Bundle your target APK inside `customapks/` and re-flash to use `custom` mode.
* **`Play Store is disabled. Pausing checks until re-enabled...`:** Expected behavior when `com.android.vending` is disabled for user `0`. Monitoring resumes automatically once you re-enable the Play Store in Android Settings.
* **`Failed to get stock versionCode`:** Ensure `com.android.vending` is not completely uninstalled for user `0` before booting.
* **Downgrade fails repeatedly:** If `pm install -r -d --user 0` is rejected by Android, `stock` mode automatically falls back to `pm uninstall -k --user 0 com.android.vending` followed by `pm install-existing --user 0 com.android.vending` (or a clean `pm install -r`). For `custom` mode, ensure your APKs carry the official Google signing certificate.
