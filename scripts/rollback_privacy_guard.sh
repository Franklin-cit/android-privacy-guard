#!/system/bin/sh
# 1-Click Full Rollback Script for Android Privacy Guard
# Restores packages, SecurityCenter sub-components, firewall rules, and backed-up databases/settings.

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

echo "=== [1/5] REMOVING BOOT SCRIPT & KERNEL FIREWALL RULES ==="
if [ "$HAS_ROOT" != "0" ]; then
    run_priv "
        rm -f /data/adb/service.d/99_privacy_guard.sh
        rm -f /data/adb/fd_clean_template.db
        if grep -q '/system/etc/hosts' /proc/mounts; then
            umount -l /system/etc/hosts 2>/dev/null
        fi
        for IPT in iptables ip6tables; do
            \$IPT -D OUTPUT -j PRIVACY_GUARD 2>/dev/null
            \$IPT -F PRIVACY_GUARD 2>/dev/null
            \$IPT -X PRIVACY_GUARD 2>/dev/null
        done
    "
fi

echo "=== [2/5] RESTORING ORIGINAL 72H DATABASE (IF BACKED UP) ==="
if [ "$HAS_ROOT" != "0" ]; then
    run_priv "
        if [ -f /data/adb/privacy_guard_backup/fraud_detection_data.db.bak ]; then
            cp -p /data/adb/privacy_guard_backup/fraud_detection_data.db.bak /data/misc/user/0/securitycenter/fraud_detection_data.db
            chown system:system /data/misc/user/0/securitycenter/fraud_detection_data.db
            chmod 660 /data/misc/user/0/securitycenter/fraud_detection_data.db
            restorecon /data/misc/user/0/securitycenter/fraud_detection_data.db 2>/dev/null
            echo 'Restored original fraud_detection_data.db'
        fi
    "
fi

echo "=== [3/5] RE-ENABLING SECURITYCENTER SUB-COMPONENTS ==="
if [ "$HAS_ROOT" != "0" ]; then
    run_priv "
        for comp in \
            com.miui.securitycenter/com.xiaomi.security.xsof.XSOFProvider \
            com.miui.securitycenter/com.xiaomi.security.xsof.frauddetection.provider.FraudDetectionProvider \
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
            pm enable --user 0 \"\$comp\" 2>/dev/null
        done
    "
fi

echo "=== [4/5] RE-INSTALLING & RE-ENABLING SYSTEM PACKAGES ==="
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
com.miui.securityadd
"
for pkg in $TARGET_PKGS; do
    cmd package install-existing --user 0 "$pkg" 2>/dev/null
    pm enable --user 0 "$pkg" 2>/dev/null
    cmd appops set "$pkg" RUN_IN_BACKGROUND allow 2>/dev/null
    cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND allow 2>/dev/null
    cmd appops set "$pkg" WAKE_LOCK allow 2>/dev/null
    if [ "$HAS_ROOT" != "0" ]; then
        run_priv "cmd connectivity set-package-networking-enabled true $pkg 2>/dev/null"
    fi
done

cmd appops set --user 0 --uid com.android.htmlviewer READ_PHONE_STATE allow 2>/dev/null
cmd appops set --user 0 com.android.htmlviewer READ_PHONE_STATE allow 2>/dev/null

echo "=== [5/5] RESTORING SYSTEM SETTINGS FROM BACKUP ==="
for bdir in /data/adb/privacy_guard_backup /data/local/tmp/privacy_guard_adb_backup; do
    if [ -f "$bdir/settings_secure.txt" ]; then
        while IFS='=' read -r k v; do
            if [ -n "$k" ] && [ "$v" != "null" ]; then
                settings put secure "$k" "$v" 2>/dev/null
            fi
        done < "$bdir/settings_secure.txt"
        echo "Restored settings from $bdir/settings_secure.txt"
        break
    fi
done

echo "=== ROLLBACK COMPLETE (REBOOT RECOMMENDED FOR CLEAN STATE) ==="
