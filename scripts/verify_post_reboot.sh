#!/system/bin/sh
# Step 3: Post-Reboot Persistence, CPU Usage & Zero-Crash Verification Script
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

echo "Waiting for sys.boot_completed=1..."
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done
echo "Boot completed! Waiting 8 seconds for post-boot scripts (service.d / XSpace) to settle..."
sleep 8

echo "=== [1/7] UPTIME & BOOT VERIFICATION ==="
uptime
echo "sys.boot_completed=$(getprop sys.boot_completed)"

echo "=== [2/7] TARGET PROCESSES CHECK (USER 0 & USER 999) ==="
ps -A | grep -E "systemhelper|guardprovider|analytics|catchlog|misight|miui\.daemon|bugreport|uireporter|onetrack|dmreg|systemAdSolution" | grep -v "qualcomm.qti"

echo "=== [3/7] WAKEUP ALARMS CHECK ==="
dumpsys alarm | grep -E "systemhelper|guardprovider|analytics|onetrack|dmreg|systemAdSolution|WakeupService|GetSignalInfoReceiver"

echo "=== [4/7] SECURITYCENTER SERVICES & CPU USAGE CHECK ==="
dumpsys activity services com.miui.securitycenter 2>/dev/null | grep "ServiceRecord{"
top -b -n 1 | grep "securitycenter"

echo "=== [5/7] SYSTEM SETTINGS PERSISTENCE CHECK ==="
for k in upload_apk_enable cloud_antispam fraud_num_state sec_pc_config_scenario_policies_open; do
    echo "secure.$k=$(settings get secure $k)"
done
echo "global.FBO_UPLOAD_LIST=$(settings get global FBO_UPLOAD_LIST)"

echo "=== [6/7] ROOT FIREWALL, MOUNT TABLE & 72H DB PERSISTENCE ==="
grep "/system/etc/hosts" /proc/mounts || echo "CLEAN: Zero hosts mount in /proc/mounts"
if [ "$HAS_ROOT" != "0" ]; then
    echo "IPv4 PRIVACY_GUARD rules: $(run_priv 'iptables -S PRIVACY_GUARD 2>/dev/null | wc -l')"
    echo "IPv6 PRIVACY_GUARD rules: $(run_priv 'ip6tables -S PRIVACY_GUARD 2>/dev/null | wc -l')"
    run_priv "iptables -S OUTPUT | head -n 5"
    run_priv "ls -laZ /data/misc/user/0/securitycenter/fraud_detection_data.db 2>/dev/null"
    run_priv "if [ -f /data/misc/user/0/securitycenter/fraud_detection_data.db ]; then cp /data/misc/user/0/securitycenter/fraud_detection_data.db /data/local/tmp/verify_fd_post_reboot.db && chmod 644 /data/local/tmp/verify_fd_post_reboot.db; fi"
fi

echo "=== [7/7] APPLICATION & SYSTEM CRASH LOG CHECK ==="
logcat -b crash -d -t 20
echo "=== POST-REBOOT VERIFICATION COMPLETE ==="
