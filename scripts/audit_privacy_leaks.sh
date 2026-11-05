#!/system/bin/sh
# Step 1: Read-Only Android Privacy & Telemetry Leakage Audit Script
# Supports both Root (su -c) and Standard ADB shell.

HAS_ROOT=0
if [ "$(id -u)" = "0" ]; then
    HAS_ROOT=1
elif su -c id >/dev/null 2>&1; then
    HAS_ROOT=2
fi

run_priv() {
    if [ "$HAS_ROOT" = "1" ]; then
        sh -c "$1"
    elif [ "$HAS_ROOT" = "2" ]; then
        su -c "$1"
    else
        return 1
    fi
}

echo "=== [1/9] DEVICE & PRIVILEGE OVERVIEW ==="
echo "Brand/Model : $(getprop ro.product.brand) / $(getprop ro.product.model) ($(getprop ro.product.name))"
echo "ROM Version : $(getprop ro.build.version.incremental) (Android $(getprop ro.build.version.release))"
echo "Shell UID   : $(id)"
echo "Root Status : HAS_ROOT=$HAS_ROOT (0=ADB-only, 1=Root-shell, 2=su-available)"

echo "=== [2/9] TARGET PROBE, TELEMETRY & AD PACKAGES (ALL USERS) ==="
pm list packages -f -u | grep -E "systemhelper|dmreg|registration|guardprovider|onetrack|analytics|systemAdSolution|catchlog|daemon|bugreport|uireporter|misight|aiasst|securitycenter|securityadd|virtualsim|vsimcore|redteamobile|statistics\.rom|logkit|obrain" | grep -v "qualcomm.qti"
echo "--- Currently Disabled Packages (User 0) ---"
pm list packages -d --user 0
echo "--- Currently Disabled Packages (User 999 / Dual Apps) ---"
pm list packages -d --user 999 2>/dev/null

echo "=== [3/9] ACTIVE TARGET PROCESSES ==="
ps -A | grep -E "systemhelper|guardprovider|analytics|catchlog|misight|miui\.daemon|bugreport|uireporter|onetrack|dmreg|systemAdSolution|statistics|logkit" | grep -v "qualcomm.qti"

echo "=== [4/9] WAKEUP ALARMS FOR PROBES & TELEMETRY ==="
dumpsys alarm | grep -E "systemhelper|guardprovider|analytics|onetrack|dmreg|systemAdSolution|WakeupService|GetSignalInfoReceiver|SignalInfoRegisterReceiver|AppInfoRegisterReceiver"

echo "=== [5/9] THIRD-PARTY APPS GRANTED ACCESS_XSOF / FRAUD DETECTION ==="
dumpsys package | grep -B 35 -E "ACCESS_XSOF:|ACCESS_XSOF_FRAUD_DETECTION:" | grep -E "Package \[|ACCESS_XSOF"

echo "=== [6/9] SECURITYCENTER ACTIVE SERVICES & PROVIDERS ==="
dumpsys activity services com.miui.securitycenter 2>/dev/null | grep "ServiceRecord{"

echo "=== [7/9] SYSTEM SETTINGS TELEMETRY FLAGS ==="
for k in upload_apk_enable cloud_antispam fraud_num_state fraud_num_state_sim_2 sec_pc_config_scenario_policies_open upload_log_pref upload_debug_log_pref; do
    echo "secure.$k=$(settings get secure $k)"
done
echo "global.FBO_UPLOAD_LIST=$(settings get global FBO_UPLOAD_LIST)"

echo "=== [8/9] ROOT-LEVEL DATABASE & XSOF CALLER INSPECTION ==="
if [ "$HAS_ROOT" != "0" ]; then
    echo "--- /data/misc/user/0/securitycenter/ ---"
    run_priv "ls -laZ /data/misc/user/0/securitycenter/ 2>/dev/null"
    run_priv "if [ -f /data/misc/user/0/securitycenter/fraud_detection_data.db ]; then cp /data/misc/user/0/securitycenter/fraud_detection_data.db /data/local/tmp/audit_fd_copy.db && chmod 644 /data/local/tmp/audit_fd_copy.db && echo 'Copied fraud_detection_data.db to /data/local/tmp/audit_fd_copy.db'; fi"
    echo "--- Leaked copies of fraud_detection_data.db on storage ---"
    run_priv "find /data/media/0 -name '*fraud_detection*' 2>/dev/null"
    echo "--- XSOF Active Callers (xsof_authority_preferences.xml) ---"
    run_priv "cat /data/data/com.miui.securitycenter/shared_prefs/xsof_authority_preferences.xml 2>/dev/null || echo 'None'"
    echo "--- Carrier Probe Databases (com.mobiletools.systemhelper) ---"
    run_priv "ls -la /data/data/com.mobiletools.systemhelper/databases/ 2>/dev/null"
    echo "--- GuardProvider Databases (com.miui.guardprovider) ---"
    run_priv "ls -la /data/data/com.miui.guardprovider/databases/ 2>/dev/null"
    echo "--- SecurityCenter Databases (com.miui.securitycenter) ---"
    run_priv "ls -la /data/data/com.miui.securitycenter/databases/ 2>/dev/null"
    echo "--- Existing Boot Scripts & Firewall ---"
    run_priv "ls -la /data/adb/service.d/ 2>/dev/null"
    run_priv "iptables -S PRIVACY_GUARD 2>/dev/null | head -n 10"
else
    echo "Root not available; skipping /data/misc and /data/data database inspection."
    find /sdcard -name "*fraud_detection*" 2>/dev/null
fi

echo "=== [9/9] MOUNT TABLE CHECK (/system/etc/hosts) ==="
grep "/system/etc/hosts" /proc/mounts || echo "CLEAN: Zero hosts mount in /proc/mounts"
echo "=== AUDIT COMPLETE ==="
