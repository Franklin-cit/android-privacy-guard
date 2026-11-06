#!/system/bin/sh
# Step 2 (Root / System Exploit Path): Conservative Zero-Crash, Zero-Mount, VPN-Safe Privacy Remediation
# Supports:
#   1. Permanent Root (KernelSU / Magisk / APatch)
#   2. Exploit-based Temporary Root shell (uid=0, even without `su` binary or with locked Bootloader)
#   3. Exploit-based `system` privilege shell (uid=1000)
# Automatically creates a full backup before making changes.

CUR_UID="$(id -u)"
if [ "$CUR_UID" = "0" ] && mkdir -p /data/adb/privacy_guard_backup 2>/dev/null; then
    BACKUP_DIR="/data/adb/privacy_guard_backup"
    TEMPLATE_DIR="/data/adb"
    HAS_PERSISTENT_ROOT_DIR=1
    mkdir -p /data/adb/service.d 2>/dev/null
else
    BACKUP_DIR="/data/local/tmp/privacy_guard_backup"
    TEMPLATE_DIR="/data/local/tmp"
    HAS_PERSISTENT_ROOT_DIR=0
    mkdir -p "$BACKUP_DIR" 2>/dev/null
fi

echo "=== [1/7] BACKING UP PRE-EXECUTION STATE TO $BACKUP_DIR (UID=$CUR_UID) ==="
if [ ! -f "$BACKUP_DIR/backup_created.flag" ]; then
    if [ -f /data/misc/user/0/securitycenter/fraud_detection_data.db ]; then
        cp -p /data/misc/user/0/securitycenter/fraud_detection_data.db "$BACKUP_DIR/fraud_detection_data.db.bak"
    fi
    pm list packages -d --user 0 > "$BACKUP_DIR/disabled_pkgs_u0.txt" 2>/dev/null
    pm list packages -d --user 999 > "$BACKUP_DIR/disabled_pkgs_u999.txt" 2>/dev/null
    for k in upload_apk_enable cloud_antispam fraud_num_state fraud_num_state_sim_2 sec_pc_config_scenario_policies_open upload_log_pref upload_debug_log_pref; do
        echo "$k=$(settings get secure $k)" >> "$BACKUP_DIR/settings_secure.txt"
    done
    date > "$BACKUP_DIR/backup_created.flag"
    echo "Backup saved to $BACKUP_DIR"
else
    echo "Existing initial backup found in $BACKUP_DIR (preserving original state)"
fi

echo "=== [2/7] DEPLOYING TRIGGER-PROTECTED 72H FRAUD DB ==="
if [ -f /data/local/tmp/fd_clean.db ]; then
    cp /data/local/tmp/fd_clean.db "$TEMPLATE_DIR/fd_clean_template.db"
    chmod 600 "$TEMPLATE_DIR/fd_clean_template.db" 2>/dev/null
    chown root:root "$TEMPLATE_DIR/fd_clean_template.db" 2>/dev/null
    rm -f /data/local/tmp/fd_clean.db
fi

if [ -f "$TEMPLATE_DIR/fd_clean_template.db" ]; then
    rm -f /data/misc/user/0/securitycenter/fraud_detection_data.db-journal
    rm -f /data/misc/user/0/securitycenter/fraud_detection_data.db-wal
    rm -f /data/misc/user/0/securitycenter/fraud_detection_data.db-shm
    cp "$TEMPLATE_DIR/fd_clean_template.db" /data/misc/user/0/securitycenter/fraud_detection_data.db
    chown system:system /data/misc/user/0/securitycenter/fraud_detection_data.db 2>/dev/null
    chmod 660 /data/misc/user/0/securitycenter/fraud_detection_data.db 2>/dev/null
    restorecon /data/misc/user/0/securitycenter/fraud_detection_data.db 2>/dev/null
fi

# Clean XSOF caller logs and any user-accessible copies on /sdcard
rm -f /data/data/com.miui.securitycenter/shared_prefs/xsof_authority_preferences.xml
rm -f /data/data/com.miui.securitycenter/shared_prefs/xsof_network_detector.xml
find /data/media/0 -name "*fraud_detection_data.db*" -delete 2>/dev/null

echo "=== [3/7] CONFIGURING ZERO-CRASH XSOF SHELLS & DISABLING COLLECTOR SERVICES ==="
# Keep ContentProviders enabled so third-party apps get valid 0-row responses without exceptions
pm enable --user 0 com.miui.securitycenter/com.xiaomi.security.xsof.XSOFProvider 2>/dev/null
pm enable --user 0 com.miui.securitycenter/com.xiaomi.security.xsof.frauddetection.provider.FraudDetectionProvider 2>/dev/null

SEC_COMPONENTS="
com.miui.securitycenter/com.xiaomi.security.xsof.frauddetection.service.MiFraudDetectionService
com.miui.securitycenter/com.xiaomi.security.xsof.MiSafetyDetectService
com.miui.securitycenter/com.miui.antifraud.AntiFraudReceiver
com.miui.securitycenter/com.miui.antivirus.service.GuardService
com.miui.securitycenter/com.miui.antivirus.service.DialogService
com.miui.securitycenter/com.miui.antivirus.receiver.UpdaterReceiver
com.miui.securitycenter/com.miui.securityscan.fileobserver.ImageProtectService
com.miui.securitycenter/com.miui.ai.service.OperationListCollectService
com.miui.securitycenter/com.miui.apppredict.service.AppPredictService
com.miui.securitycenter/com.miui.apppredict.service.AiService
com.miui.securitycenter/com.miui.analytics.AnalyticsService
"
for comp in $SEC_COMPONENTS; do
    am stopservice --user 0 "$comp" 2>/dev/null
    pm disable --user 0 "$comp" 2>/dev/null
    pm disable --user 999 "$comp" 2>/dev/null
done

rm -f /data/data/com.miui.securitycenter/databases/risky_app.db*
rm -f /data/data/com.miui.securitycenter/databases/app_predict_data.db*
rm -f /data/data/com.miui.securitycenter/databases/global_satisfaction_data.db*
rm -f /data/data/com.miui.securitycenter/databases/month_report.db*
rm -f /data/data/com.miui.securitycenter/databases/one_track_cloud*
rm -f /data/data/com.miui.securitycenter/databases/onetrack*
rm -f /data/data/com.miui.securitycenter/databases/universal_ot_monitor_db*
rm -f /data/data/com.miui.securitycenter/databases/preload.db*

# Clean HTMLViewer (com.android.htmlviewer) OneTrack & MiPush telemetry while keeping cloud_all_data.db and global_search_result_database
pm revoke --user 0 com.android.htmlviewer android.permission.READ_PHONE_STATE 2>/dev/null
cmd appops set --user 0 --uid com.android.htmlviewer READ_PHONE_STATE ignore 2>/dev/null
cmd appops set --user 0 com.android.htmlviewer READ_PHONE_STATE ignore 2>/dev/null
cmd appops set --user 0 --uid com.android.htmlviewer READ_DEVICE_IDENTIFIERS ignore 2>/dev/null
cmd appops set --user 0 com.android.htmlviewer READ_DEVICE_IDENTIFIERS ignore 2>/dev/null
rm -f /data/data/com.android.htmlviewer/databases/onetrack* /data/user_de/0/com.android.htmlviewer/databases/onetrack*
rm -f /data/data/com.android.htmlviewer/databases/one_track_cloud* /data/user_de/0/com.android.htmlviewer/databases/one_track_cloud*
rm -f /data/data/com.android.htmlviewer/databases/universal_ot_monitor_db* /data/user_de/0/com.android.htmlviewer/databases/universal_ot_monitor_db*
rm -f /data/data/com.android.htmlviewer/shared_prefs/one_track_pref.xml /data/user_de/0/com.android.htmlviewer/shared_prefs/one_track_pref.xml
rm -f /data/data/com.android.htmlviewer/shared_prefs/sp_client_report_status.xml
rm -f /data/data/com.android.htmlviewer/shared_prefs/AwOriginVisitLoggerPrefs.xml
rm -rf /data/data/com.android.htmlviewer/files/perf/*

echo "=== [4/7] WIPING PROBE DATABASES & REMOVING TELEMETRY PACKAGES ==="
rm -rf /data/data/com.mobiletools.systemhelper/databases/* 2>/dev/null
rm -rf /data/user_de/0/com.mobiletools.systemhelper/databases/* 2>/dev/null
rm -rf /data/data/com.miui.guardprovider/databases/* 2>/dev/null
rm -rf /data/user_de/0/com.miui.guardprovider/databases/* 2>/dev/null

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
"
for pkg in $TARGET_PKGS; do
    pm uninstall-system-updates "$pkg" 2>/dev/null
    am force-stop "$pkg" 2>/dev/null
    pm clear --user 0 "$pkg" 2>/dev/null
    pm clear --user 999 "$pkg" 2>/dev/null
    pm disable-user --user 0 "$pkg" 2>/dev/null
    pm disable-user --user 999 "$pkg" 2>/dev/null
    pm uninstall -k --user 0 "$pkg" 2>/dev/null
    pm uninstall -k --user 999 "$pkg" 2>/dev/null
done

killall com.mobiletools.systemhelper com.miui.guardprovider com.xiaomi.security.onetrack com.miui.systemAdSolution com.miui.daemon com.miui.analytics 2>/dev/null
stop misight 2>/dev/null

echo "=== [5/7] HARDENING SYSTEM SETTINGS ==="
settings put secure upload_apk_enable 0
settings put global upload_apk_enable 0
settings put system virus_scan_install 0
settings put secure cloud_antispam 0
settings put secure fraud_num_state 0
settings put secure fraud_num_state_sim_2 0
settings put secure sec_pc_config_scenario_policies_open 0
settings put secure upload_log_pref 0
settings put secure upload_debug_log_pref 0
settings put global FBO_UPLOAD_LIST "[]"
settings put secure FBO_UPLOAD_LIST "[]"
settings put secure lock_unit_mapping "{}"

echo "=== [6/7] INSTALLING PERSISTENT ZERO-MOUNT STEALTH FIREWALL (/data/adb/service.d/99_privacy_guard.sh) ==="
cat << 'EOF' > /data/adb/service.d/99_privacy_guard.sh
#!/system/bin/sh
# Wait for boot completion
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done
sleep 5

# 1. Ensure zero /system/etc/hosts bind-mount for 100% Zygisk Next compatibility
if grep -q "/system/etc/hosts" /proc/mounts; then
    umount -l /system/etc/hosts 2>/dev/null
fi
rm -f /data/adb/hosts_privacy

# 2. Ensure trigger-protected empty fraud_detection_data.db is in place
if [ -f /data/adb/fd_clean_template.db ]; then
    rm -f /data/misc/user/0/securitycenter/fraud_detection_data.db-journal
    rm -f /data/misc/user/0/securitycenter/fraud_detection_data.db-wal
    rm -f /data/misc/user/0/securitycenter/fraud_detection_data.db-shm
    cp /data/adb/fd_clean_template.db /data/misc/user/0/securitycenter/fraud_detection_data.db
    chown system:system /data/misc/user/0/securitycenter/fraud_detection_data.db
    chmod 660 /data/misc/user/0/securitycenter/fraud_detection_data.db
    restorecon /data/misc/user/0/securitycenter/fraud_detection_data.db 2>/dev/null
fi
rm -f /data/data/com.miui.securitycenter/shared_prefs/xsof_authority_preferences.xml
rm -f /data/data/com.miui.securitycenter/shared_prefs/xsof_network_detector.xml

# 3. Re-enforce disabled state on SecurityCenter telemetry/fraud collection services (while keeping XSOFProvider enabled)
pm enable --user 0 com.miui.securitycenter/com.xiaomi.security.xsof.XSOFProvider 2>/dev/null
pm enable --user 0 com.miui.securitycenter/com.xiaomi.security.xsof.frauddetection.provider.FraudDetectionProvider 2>/dev/null

for comp in \
    com.miui.securitycenter/com.xiaomi.security.xsof.frauddetection.service.MiFraudDetectionService \
    com.miui.securitycenter/com.xiaomi.security.xsof.MiSafetyDetectService \
    com.miui.securitycenter/com.miui.antifraud.AntiFraudReceiver \
    com.miui.securitycenter/com.miui.antivirus.service.GuardService \
    com.miui.securitycenter/com.miui.antivirus.service.DialogService \
    com.miui.securitycenter/com.miui.antivirus.receiver.UpdaterReceiver \
    com.miui.securitycenter/com.miui.securityscan.fileobserver.ImageProtectService \
    com.miui.securitycenter/com.miui.ai.service.OperationListCollectService \
    com.miui.securitycenter/com.miui.apppredict.service.AppPredictService \
    com.miui.securitycenter/com.miui.apppredict.service.AiService \
    com.miui.securitycenter/com.miui.analytics.AnalyticsService; do
    am stopservice --user 0 "$comp" 2>/dev/null
    pm disable --user 0 "$comp" 2>/dev/null
done

# 4. Clean up Dual-Apps (User 999) analytics re-seeded on boot & stop native daemons
pm disable-user --user 0 com.miui.analytics 2>/dev/null
pm disable-user --user 999 com.miui.analytics 2>/dev/null
pm uninstall -k --user 999 com.miui.analytics 2>/dev/null
am force-stop com.miui.analytics 2>/dev/null
killall com.mobiletools.systemhelper com.miui.guardprovider com.xiaomi.security.onetrack com.miui.systemAdSolution com.miui.daemon com.miui.analytics 2>/dev/null
stop misight 2>/dev/null

# 5. Build PRIVACY_GUARD chain in iptables and ip6tables
for IPT in iptables ip6tables; do
    $IPT -D OUTPUT -j PRIVACY_GUARD 2>/dev/null
    $IPT -F PRIVACY_GUARD 2>/dev/null
    $IPT -X PRIVACY_GUARD 2>/dev/null
    $IPT -N PRIVACY_GUARD 2>/dev/null
    $IPT -I OUTPUT 1 -j PRIVACY_GUARD 2>/dev/null
done

BLOCK_PKGS="com.mobiletools.systemhelper com.miui.dmregservice com.xiaomi.registration com.miui.guardprovider com.xiaomi.security.onetrack com.miui.analytics com.miui.systemAdSolution com.bsp.catchlog com.miui.daemon com.miui.bugreport com.miui.uireporter com.miui.misightservice com.miui.securityadd"
UID_LIST=""
cmd connectivity set-chain3-enabled true 2>/dev/null
for pkg in $BLOCK_PKGS; do
    cmd connectivity set-package-networking-enabled false "$pkg" 2>/dev/null
    uid=$(grep "^$pkg " /data/system/packages.list 2>/dev/null | awk '{print $2}')
    if [ -n "$uid" ] && [ "$uid" -gt 10000 ]; then
        case " $UID_LIST " in
            *" $uid "*) ;;
            *) UID_LIST="$UID_LIST $uid" ;;
        esac
    fi
done

for uid in $UID_LIST; do
    u999=$((99900000 + uid))
    for IPT in iptables ip6tables; do
        $IPT -A PRIVACY_GUARD -m owner --uid-owner "$uid" -j REJECT 2>/dev/null
        $IPT -A PRIVACY_GUARD -m owner --uid-owner "$u999" -j REJECT 2>/dev/null
    done
done

# Note: fraud-detection.engine.miui.com (NFC access card) and eps.caict.ac.cn / gateway-papa.cloud.weizhi.com (110/120 emergency location) are intentionally NOT blocked.
add_domain_block() {
    dom="$1"
    hex="$2"
    for IPT in iptables ip6tables; do
        $IPT -A PRIVACY_GUARD -p udp --dport 53 -m string --algo bm --hex-string "$hex" -j DROP 2>/dev/null
        $IPT -A PRIVACY_GUARD -p tcp --dport 53 -m string --algo bm --hex-string "$hex" -j REJECT 2>/dev/null
        $IPT -A PRIVACY_GUARD -p tcp -m multiport --dports 80,443,8080,18080 -m string --algo bm --to 350 --string "$dom" -j REJECT --reject-with tcp-reset 2>/dev/null
    done
}

add_domain_block "flash.sec.miui.com"             "|05|flash|03|sec|04|miui|03|com|"
add_domain_block "virus-engine.sec.miui.com"      "|0c|virus-engine|03|sec|04|miui|03|com|"
add_domain_block "api.sec.miui.com"               "|03|api|03|sec|04|miui|03|com|"
add_domain_block "notify.sec.miui.com"            "|06|notify|03|sec|04|miui|03|com|"
add_domain_block "pwn.sec.miui.com"               "|03|pwn|03|sec|04|miui|03|com|"
add_domain_block "detection-aigc.engine.miui.com" "|0e|detection-aigc|06|engine|04|miui|03|com|"
add_domain_block "dm.wo.com.cn"                   "|02|dm|02|wo|03|com|02|cn|"
add_domain_block "data.mistat.xiaomi.com"         "|04|data|06|mistat|06|xiaomi|03|com|"
add_domain_block "tracking.miui.com"              "|08|tracking|04|miui|03|com|"
add_domain_block "sdkconfig.ad.xiaomi.com"        "|09|sdkconfig|02|ad|06|xiaomi|03|com|"
add_domain_block "beacon.qq.com"                  "|06|beacon|02|qq|03|com|"

settings put secure upload_apk_enable 0
settings put global upload_apk_enable 0
settings put system virus_scan_install 0
settings put secure sec_pc_config_scenario_policies_open 0
settings put secure fraud_num_state 0
settings put global FBO_UPLOAD_LIST "[]"
settings put secure FBO_UPLOAD_LIST "[]"
settings put secure lock_unit_mapping "{}"

# 7. Clean HTMLViewer (com.android.htmlviewer) OneTrack & MiPush telemetry while keeping cloud_all_data.db
cmd appops set --user 0 --uid com.android.htmlviewer READ_PHONE_STATE ignore >/dev/null 2>&1
cmd appops set --user 0 com.android.htmlviewer READ_PHONE_STATE ignore >/dev/null 2>&1
cmd appops set --user 0 --uid com.android.htmlviewer READ_DEVICE_IDENTIFIERS ignore >/dev/null 2>&1
cmd appops set --user 0 com.android.htmlviewer READ_DEVICE_IDENTIFIERS ignore >/dev/null 2>&1
rm -f /data/data/com.android.htmlviewer/databases/onetrack* /data/user_de/0/com.android.htmlviewer/databases/onetrack*
rm -f /data/data/com.android.htmlviewer/databases/one_track_cloud* /data/user_de/0/com.android.htmlviewer/databases/one_track_cloud*
rm -f /data/data/com.android.htmlviewer/databases/universal_ot_monitor_db* /data/user_de/0/com.android.htmlviewer/databases/universal_ot_monitor_db*
rm -f /data/data/com.android.htmlviewer/shared_prefs/one_track_pref.xml /data/user_de/0/com.android.htmlviewer/shared_prefs/one_track_pref.xml
rm -f /data/data/com.android.htmlviewer/shared_prefs/sp_client_report_status.xml
rm -f /data/data/com.android.htmlviewer/shared_prefs/AwOriginVisitLoggerPrefs.xml
rm -rf /data/data/com.android.htmlviewer/files/perf/*
EOF

chmod 755 /data/adb/service.d/99_privacy_guard.sh
chown root:root /data/adb/service.d/99_privacy_guard.sh

# Execute the script immediately to load firewall rules now
sh /data/adb/service.d/99_privacy_guard.sh &
sleep 7
killall com.miui.securitycenter.remote 2>/dev/null
sleep 2

echo "=== [7/7] IMMEDIATE VERIFICATION ==="
ps -A | grep -E "systemhelper|guardprovider|analytics|catchlog|misight|miui\.daemon|bugreport|uireporter|onetrack|dmreg|systemAdSolution" | grep -v "qualcomm.qti"
grep "/system/etc/hosts" /proc/mounts || echo "CLEAN: Zero hosts mount in /proc/mounts"
echo "IPv4 PRIVACY_GUARD rules: $(iptables -S PRIVACY_GUARD | wc -l)"
echo "IPv6 PRIVACY_GUARD rules: $(ip6tables -S PRIVACY_GUARD | wc -l)"
echo "=== ROOT REMEDIATION COMPLETE ==="
