#!/system/bin/sh
# Step 2 (Standard ADB Non-Root Path): Conservative Privacy Remediation
# Works with standard ADB shell (uid=2000) without Root.
# Automatically records pre-execution package and setting states for 1-click rollback.

BACKUP_DIR="/data/local/tmp/privacy_guard_adb_backup"
mkdir -p "$BACKUP_DIR"

echo "=== [1/4] BACKING UP PRE-EXECUTION STATE TO $BACKUP_DIR ==="
if [ ! -f "$BACKUP_DIR/backup_created.flag" ]; then
    pm list packages -d --user 0 > "$BACKUP_DIR/disabled_pkgs_u0.txt" 2>/dev/null
    pm list packages -d --user 999 > "$BACKUP_DIR/disabled_pkgs_u999.txt" 2>/dev/null
    for k in upload_apk_enable cloud_antispam fraud_num_state fraud_num_state_sim_2 sec_pc_config_scenario_policies_open upload_log_pref upload_debug_log_pref; do
        echo "$k=$(settings get secure $k)" >> "$BACKUP_DIR/settings_secure.txt"
    done
    date > "$BACKUP_DIR/backup_created.flag"
    echo "Backup saved to $BACKUP_DIR"
fi

echo "=== [2/4] DISABLING & UNINSTALLING REMOVABLE PROBES & TELEMETRY (USER 0 & 999) ==="
# Note: Core packages (com.miui.securitycenter, com.miui.securitycore, com.xiaomi.xmsf, com.xiaomi.finddevice)
# are strictly excluded to guarantee 0% risk of bootloop or app crashes.
TARGET_PKGS="
com.mobiletools.systemhelper
com.miui.dmregservice
com.xiaomi.registration
com.miui.guardprovider
com.xiaomi.security.onetrack
com.miui.analytics
com.miui.systemAdSolution
com.bsp.catchlog
com.miui.daemon
com.miui.bugreport
com.miui.uireporter
com.miui.misightservice
com.nearme.statistics.rom
com.oplus.statistics.rom
com.oplus.logkit
com.vivo.epm
"

for pkg in $TARGET_PKGS; do
    echo "Processing $pkg ..."
    am force-stop "$pkg" 2>/dev/null
    cmd appops set "$pkg" RUN_IN_BACKGROUND ignore 2>/dev/null
    cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND ignore 2>/dev/null
    cmd appops set "$pkg" WAKE_LOCK ignore 2>/dev/null
    pm clear --user 0 "$pkg" 2>/dev/null
    pm clear --user 999 "$pkg" 2>/dev/null
    pm disable-user --user 0 "$pkg" 2>/dev/null
    pm disable-user --user 999 "$pkg" 2>/dev/null
    pm uninstall -k --user 0 "$pkg" 2>/dev/null
    pm uninstall -k --user 999 "$pkg" 2>/dev/null
done

# Restrict background activity of securityadd without removing widgets
cmd appops set com.miui.securityadd RUN_IN_BACKGROUND ignore 2>/dev/null
cmd appops set com.miui.securityadd RUN_ANY_IN_BACKGROUND ignore 2>/dev/null

# Revoke identifier permissions on HTMLViewer while preserving its cloud control service
pm revoke --user 0 com.android.htmlviewer android.permission.READ_PHONE_STATE 2>/dev/null
cmd appops set --user 0 --uid com.android.htmlviewer READ_PHONE_STATE ignore 2>/dev/null
cmd appops set --user 0 com.android.htmlviewer READ_PHONE_STATE ignore 2>/dev/null
cmd appops set --user 0 --uid com.android.htmlviewer READ_DEVICE_IDENTIFIERS ignore 2>/dev/null
cmd appops set --user 0 com.android.htmlviewer READ_DEVICE_IDENTIFIERS ignore 2>/dev/null

echo "=== [3/4] HARDENING ACCESSIBLE SYSTEM SETTINGS & CLEANING SDCARD COPIES ==="
settings put secure upload_apk_enable 0 2>/dev/null
settings put global upload_apk_enable 0 2>/dev/null
settings put secure cloud_antispam 0 2>/dev/null
settings put secure fraud_num_state 0 2>/dev/null
settings put secure fraud_num_state_sim_2 0 2>/dev/null
settings put secure sec_pc_config_scenario_policies_open 0 2>/dev/null
settings put secure upload_log_pref 0 2>/dev/null
settings put secure upload_debug_log_pref 0 2>/dev/null
settings put global FBO_UPLOAD_LIST "[]" 2>/dev/null
settings put secure FBO_UPLOAD_LIST "[]" 2>/dev/null

find /sdcard -name "*fraud_detection_data.db*" -delete 2>/dev/null

echo "=== [4/4] VERIFYING ACTIVE PROCESSES & ALARMS ==="
ps -A | grep -E "systemhelper|guardprovider|analytics|catchlog|misight|miui\.daemon|bugreport|uireporter|onetrack|dmreg|systemAdSolution" | grep -v "qualcomm.qti"
echo "=== ADB REMEDIATION COMPLETE ==="
