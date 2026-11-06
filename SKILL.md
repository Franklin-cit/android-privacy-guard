---
name: android-privacy-guard
description: >-
  Audit, explain, remediate, and verify Android/HyperOS/MIUI/OEM privacy and telemetry
  leakage (carrier DM probes, 72-hour behavior profile databases, XSOF cross-app risk
  interfaces, cloud antivirus scanners, HTMLViewer cloud-control host telemetry, and
  OneTrack/MSA telemetry) via Root or ADB. Use this skill when the user wants to detect
  phone/tablet privacy leaks, block system telemetry or anti-fraud profiling, or verify
  privacy hardening across reboots without causing app crashes, breaking cloud control
  or system updates, breaking VPNs, or exposing Root hiding.
---

# Android Privacy Guard (Audit, Conservative Remediation & Reboot Verification)

This skill guides you through a rigorous **3-Step Workflow** to detect, explain, remediate, and verify system-level privacy and telemetry leakage on Android devices (especially Xiaomi HyperOS/MIUI, and generalizable to OPPO ColorOS, vivo OriginOS, Honor MagicOS, and other China ROMs).

> [!IMPORTANT]
> **Core Safety Principles (Must Follow at All Times)**
> 1. **Privacy Redaction**: Never log or persist the user's personal identifiers (IMEI, IMSI, ICCID, phone number MD5, GPS coordinates, Wi-Fi SSID/BSSID, or device serial) into shared notes or skill files.
> 2. **Clear & Objective Communication**: Always explain findings and technical mechanisms to the user in clear, objective natural language without exaggerated metaphors before executing changes.
> 3. **Conservative Zero-Crash Architecture**:
>    - **Never** uninstall or disable core system packages (`com.miui.securitycenter`, `com.miui.securitycore`, `com.xiaomi.xmsf`, `com.xiaomi.finddevice`, `com.android.htmlviewer`) to prevent bootloops, settings failures, or cloud-control loss.
>    - **Never** delete `/data/data/com.android.htmlviewer/databases/cloud_all_data.db` or `/data/user_de/0/com.android.htmlviewer/databases/cloud_all_data.db` (which stores system-wide cloud control configurations via `SettingsCloudControlService`). Only revoke its identifier permissions (`READ_PHONE_STATE` and `READ_DEVICE_IDENTIFIERS`) and remove its OneTrack/MiPush telemetry files.
>    - **Never** lock SQLite databases with `chmod 000` or `chattr +i` on 0-byte files (which throws `SQLiteCantOpenDatabaseException`), and **never** `pm disable` cross-app providers like `XSOFProvider` (which can throw `IllegalArgumentException: Unknown authority`). Instead, use the **SQLite `RAISE(IGNORE)` Trigger + Provider Shell** pattern.
> 4. **Zero Root-Hiding Footprint**: Never bind-mount `/system/etc/hosts` or modify read-only system partitions so `/proc/mounts` and `/proc/self/mountinfo` stay 100% clean for `Zygisk Next` / `Shamiko`.
> 5. **100% VPN Compatibility**: Never alter `ip rule`, `ip route`, `fwmark`, or `nat`/`mangle` tables. Constrain domain string matching to DNS port `53` and TCP ports `80,443,8080,18080` (`--to 350`).
> 6. **Full Reversibility**: Always create a pre-execution backup and ensure 1-click rollback via [`scripts/rollback_privacy_guard.sh`](./scripts/rollback_privacy_guard.sh).

---

## Step 1: Detect Privacy Leakage & Consult Reference Memo

1. **Read the Cross-Brand Leakage Reference Memo**:
   - Before running the audit, read [`references/leakage_reference_memo.md`](./references/leakage_reference_memo.md) to understand all known telemetry interfaces, background daemons, local databases, cross-app risk permissions, dual-purpose system hosts (`com.android.htmlviewer`), and domain purposes (including which domains **must NOT be blocked** to preserve NFC access cards and 110/120 emergency call location).
2. **Determine Connection & Privilege Level**:
   - Check connected devices (`adb devices -l`) and check whether the shell has Root access (`adb shell "su -c id"`).
3. **Run the Automated Read-Only Audit**:
   - Push and execute [`scripts/audit_privacy_leaks.sh`](./scripts/audit_privacy_leaks.sh) on the target device:
     ```powershell
     adb push scripts/audit_privacy_leaks.sh /data/local/tmp/audit_privacy_leaks.sh
     adb shell "sh /data/local/tmp/audit_privacy_leaks.sh"
     ```
   - If Root is available and `/data/local/tmp/audit_fd_copy.db` was extracted, inspect its table row counts and triggers using Python (`sqlite3`).
4. **Present Findings to the User**:
   - Summarize what was found on their device in clear, natural language:
     - Which background probes/processes are running and how often they wake up the hardware.
     - Whether the local 72-hour behavior database (`fraud_detection_data.db`) exists and what types of records (screenshots, screen recordings, call MD5s, installed apps) are inside.
     - Which installed third-party commercial apps hold the `ACCESS_XSOF` permission to query that profile.
     - Whether `com.android.htmlviewer` (`HTML查看器`) is running `com.android.htmlviewer:remote`, whether it has invoked `READ_PHONE_STATE` / `READ_DEVICE_IDENTIFIERS`, and what OneTrack/MiPush telemetry files exist alongside `cloud_all_data.db`.
     - Whether telemetry traffic has been bypassing or penetrating their VPN tunnel (`type=17 / TYPE_VPN`).

---

## Step 2: Formulate & Explain the Conservative Solution (Root vs. ADB)

Based on the user's permission level (**Root** vs. **Standard ADB**), present a clear, conservative remediation plan in plain natural language and **wait for user confirmation before executing**.

### Key Technical Explanations to Share with the User

- **Why third-party apps won't crash**:
  - Instead of deleting `fraud_detection_data.db` or setting its permissions to `000` (which causes `SQLiteCantOpenDatabaseException` and retry loops), we empty the 8 tables, run `VACUUM`, and install `BEFORE INSERT` / `BEFORE UPDATE` SQLite triggers (`SELECT RAISE(IGNORE);`). Write requests are silently ignored without error, and when third-party apps query `XSOFProvider`, it returns `0` rows normally.
- **Why system updates and cloud control won't break (`com.android.htmlviewer`)**:
  - On HyperOS/MIUI, `com.android.htmlviewer` (`HTML查看器`) hosts `SettingsCloudControlService` and `SettingsProvider` (`cloud_all_data.db`) as well as Settings search indexing (`global_search_result_database`). We keep the package enabled and preserve `cloud_all_data.db`, while revoking its `READ_PHONE_STATE` and `READ_DEVICE_IDENTIFIERS` AppOps permissions and deleting only its OneTrack databases (`onetrack_cache`, `universal_ot_monitor_db`), MiPush performance logs (`files/perf/`), and WebView origin logs.
- **Why VPNs (`FlClash`, etc.) won't break**:
  - The firewall creates an isolated `PRIVACY_GUARD` chain in `iptables`/`ip6tables` `OUTPUT` without flushing existing chains or modifying `ip rule` / `ip route` / `tun0` routing tables. It blocks traffic only by target telemetry UID or by matching the 11 telemetry domains on DNS (`53`) and HTTP/HTTPS (`80,443,8080,18080`).
- **Why Root hiding (`Zygisk Next`) isn't affected**:
  - We do not bind-mount `/system/etc/hosts` or modify read-only partitions. All rules run in kernel netfilter memory and persist via `/data/adb/service.d/99_privacy_guard.sh`, leaving zero extra mount entries in `/proc/mounts`.
- **Why NFC door cards & 110/120 emergency calls still work**:
  - We keep the NFC access-card configuration domain (`fraud-detection.engine.miui.com`) and the national 110/120 emergency rescue location domains (`eps.caict.ac.cn` / `gateway-papa.cloud.weizhi.com`) unblocked.
- **Full Reversibility**:
  - Original databases, package states, and settings are backed up before changes are applied, and [`scripts/rollback_privacy_guard.sh`](./scripts/rollback_privacy_guard.sh) restores the initial state in one step.

### Execution Path A: Root Permission Available (Permanent Root or Temporary Root)

1. If `/data/local/tmp/audit_fd_copy.db` was pulled from the device, run [`scripts/build_trigger_blackhole_db.py`](./scripts/build_trigger_blackhole_db.py) locally to generate `fd_clean.db` (preserving the original `PRAGMA user_version` and schema while injecting 16 `BEFORE INSERT` / `BEFORE UPDATE` `SELECT RAISE(IGNORE);` triggers), and push `fd_clean.db` to `/data/local/tmp/fd_clean.db`.
2. Push and run [`scripts/apply_root_remediation.sh`](./scripts/apply_root_remediation.sh) via `su -c`:
   - Automatically backs up original files and package states to `/data/adb/privacy_guard_backup/`.
   - Deploys the trigger-protected empty `fraud_detection_data.db` and removes leaked copies on `/sdcard/`.
   - Keeps `XSOFProvider` and `FraudDetectionProvider` enabled (returning 0-row clean data) while disabling internal background collectors (`MiFraudDetectionService`, `MiSafetyDetectService`, `GuardService`, `ImageProtectService`, `OperationListCollectService`, `AppPredictService`, `AiService`, `AnalyticsService`).
   - Cleans `com.android.htmlviewer` telemetry (`onetrack*`, `one_track_cloud*`, `universal_ot_monitor_db*`, `one_track_pref.xml`, `sp_client_report_status.xml`, `AwOriginVisitLoggerPrefs.xml`, `files/perf/*`) across `/data/data/` and `/data/user_de/0/` and revokes `READ_PHONE_STATE` (UID and package level) and `READ_DEVICE_IDENTIFIERS`, while preserving `cloud_all_data.db` and `global_search_result_database`.
   - Wipes telemetry databases and disables/uninstalls carrier probes (`com.mobiletools.systemhelper`, `com.miui.dmregservice`, `com.xiaomi.registration`) and telemetry suites (`com.miui.guardprovider`, `com.xiaomi.security.onetrack`, `com.miui.analytics` in both `User 0` and Dual-Apps `User 999`, `com.miui.systemAdSolution`, `com.bsp.catchlog`, `com.miui.daemon`, `com.miui.bugreport`, `com.miui.uireporter`, `com.miui.misightservice`).
   - Installs the persistent boot script `/data/adb/service.d/99_privacy_guard.sh` and immediately loads the `PRIVACY_GUARD` `iptables`/`ip6tables` + eBPF firewall rules.
3. **Special Note for Temporary Root (`fastboot boot` patched image / one-time Root)**:
   - **90%+ of the Root remediation lives in `/data` and permanently survives reboot even after Root is gone**:
     - The 16 `RAISE(IGNORE)` SQLite triggers inside `/data/misc/user/0/securitycenter/fraud_detection_data.db` are stored inside the database file on `/data` and remain permanently active after losing Root.
     - Component-level `pm disable` (`MiFraudDetectionService`, `MiSafetyDetectService`, `GuardService`, etc.) and package-level `pm disable-user` / `pm uninstall -k` are saved in `/data/system/users/0/package-restrictions.xml` and remain permanently disabled after losing Root.
     - Wiped probe/telemetry databases (`/data/data/com.mobiletools.systemhelper/databases/*`, etc.) and `settings` flags remain permanently cleaned.
   - **What does NOT auto-run after losing Root**: `/data/adb/service.d/99_privacy_guard.sh` (which reloads `iptables`/`ip6tables` kernel memory rules and kills Dual-Apps `User 999` `com.miui.analytics` on boot). For Temporary Root users, advise adding the 11 telemetry domains (`DOMAIN-SUFFIX,flash.sec.miui.com,REJECT`, `DOMAIN-SUFFIX,dm.wo.com.cn,REJECT`, etc.) into their VPN client (`FlClash` / `Clash`) rule list to replace the `iptables` domain rules after rebooting to stock boot.

### Execution Path B: Standard ADB Only (Non-Root Conservative Defense)

1. Push and run [`scripts/apply_adb_remediation.sh`](./scripts/apply_adb_remediation.sh) via standard `adb shell`:
   - Records pre-execution package states in `/data/local/tmp/privacy_guard_adb_backup/`.
   - Disables and uninstalls (`pm disable-user --user 0` / `pm uninstall -k --user 0`) all removable carrier probes and telemetry packages (`com.mobiletools.systemhelper`, `com.miui.dmregservice`, `com.xiaomi.registration`, `com.miui.guardprovider`, `com.xiaomi.security.onetrack`, `com.miui.analytics`, `com.miui.systemAdSolution`, `com.bsp.catchlog`, `com.miui.daemon`, `com.miui.bugreport`, `com.miui.uireporter`, `com.miui.misightservice`) across `User 0` and `User 999`.
   - Restricts background execution (`cmd appops set <pkg> RUN_IN_BACKGROUND ignore`, `RUN_ANY_IN_BACKGROUND ignore`) and disables background networking where permitted.
   - Turns off accessible `secure`/`global` telemetry settings (`upload_apk_enable=0`, `cloud_antispam=0`, `fraud_num_state=0`, `sec_pc_config_scenario_policies_open=0`, `FBO_UPLOAD_LIST=[]`).
   - Deletes any user-accessible copies of `fraud_detection_data.db` on `/sdcard/`.

---

## Step 3: Reboot & Verify Persistence and Stability

After executing Step 2, perform a real reboot test (with user permission) to guarantee that the protections survive reboot and cause zero instability or battery drain:

1. Reboot the device:
   ```powershell
   adb reboot
   adb wait-for-device
   ```
2. Push and run [`scripts/verify_post_reboot.sh`](./scripts/verify_post_reboot.sh):
   - Waits for `sys.boot_completed=1` plus 8 seconds for boot scripts (`service.d`) and Dual-Apps (`XSpaceManagerService`) initialization to settle.
   - Verifies all **7 Persistence & Stability Checkpoints**:
     1. **Boot Uptime**: Confirms fresh boot state (`uptime`).
     2. **72h Behavior Database (`fraud_detection_data.db`)**: Confirms all 8 tables still contain `0 rows` and all 16 `RAISE(IGNORE)` triggers remain intact after boot events.
     3. **Zero Process & Dual-Apps (`User 999`) Residue**: Confirms `ps -A` has zero running target processes (`systemhelper`, `guardprovider`, `analytics` in `u0` and `u999`, `onetrack`, `systemAdSolution`, `daemon`, `catchlog`, `misight`).
     4. **Zero Wakeup Alarms**: Confirms `dumpsys alarm` has zero wakeup timers for removed probes/telemetry packages.
     5. **SecurityCenter Sub-Services & CPU**: Confirms disabled collector services stay stopped and `com.miui.securitycenter` CPU usage in `top` is `0.0%` (no infinite retry loops).
     6. **Stealth Firewall & Clean Mount Table**: Confirms `PRIVACY_GUARD` is at position `#1` in `iptables`/`ip6tables` `OUTPUT` chain and `/proc/mounts` contains zero `/system/etc/hosts` mounts.
     7. **Zero Crash Logs**: Confirms `logcat -b crash` has zero application or system crashes.

---

## Rollback Procedure (Restore to Pre-Execution State)

Whenever the user requests a rollback (or wants to restore a specific component such as cloud virus scanning):
- Run [`scripts/rollback_privacy_guard.sh`](./scripts/rollback_privacy_guard.sh) on the device. It removes `/data/adb/service.d/99_privacy_guard.sh`, flushes and deletes the `PRIVACY_GUARD` firewall chain, restores the backed-up `fraud_detection_data.db`, re-enables all SecurityCenter components and system packages (`cmd package install-existing` & `pm enable`), and restores system settings.
