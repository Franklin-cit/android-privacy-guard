# Android Privacy Guard (`android-privacy-guard`)

[![Platform](https://img.shields.io/badge/Platform-Xiaomi%20HyperOS%20%7C%20MIUI-FF6900?logo=xiaomi&logoColor=white)](#)
[![Mode](https://img.shields.io/badge/Privileges-Root%20%7C%20Temp%20Root%20%7C%20Standard%20ADB-blue)](#)
[![Safety](https://img.shields.io/badge/Guarantee-Zero%20Crash%20%7C%20VPN%20Safe%20%7C%20Zygisk%20Safe-success)](#)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](#)

**`android-privacy-guard`** 是一个面向 AI Agent（Claude Code / Antigravity / Cursor 等）的**系统级隐私泄露检测、加固与重启持久性验证 Skill**。

它专门针对 **Xiaomi HyperOS / MIUI**（其余定制系统如 ColorOS、OriginOS、HarmonyOS 等仅供参考）内置的 **72 小时用户行为记录数据库、跨应用风控查询接口（ContentProvider）、运营商设备管理（DM）注册上报组件、云端应用扫描引擎、系统云控宿主组件（HTML查看器）内置遥测以及系统级统计服务**，提供一套**停止本地数据采集与外联上报，同时保证系统云控与更新正常、第三方应用（微信、支付宝、银行 App 等）不闪退、不影响 VPN 代理路由、不产生额外挂载点（兼容 Zygisk Next）且支持随时还原**的技术方案。

---

## 检测与治理范围

本 Skill 内置了一份 **[《Android/OEM 隐私与遥测泄露全量备忘录》](references/leakage_reference_memo.md)**，针对直接删除或冻结系统组件容易引发的应用闪退、系统云控失效、异常耗电、暴露 Root 挂载点及 VPN 断网等问题，采用以下处理方式：

| 类别 | 典型包名 / 接口 / 路径 | 采集或上报的具体内容 | 处理方式与兼容性设计 |
| :--- | :--- | :--- | :--- |
| **1. 72 小时行为记录数据库** | `/data/misc/user/0/securitycenter/fraud_detection_data.db`<br>（含 `install_app`、`fraud_phone`、`voip_record`、`screen_share`、`screenshot` 等 8 张表） | 过去 72 小时内安装的应用包名与 MD5、通话起止时间与对方号码 MD5、微信/QQ 音视频通话时长、录屏与截屏毫秒级时间戳 | **SQLite 触发器拦截写入 + 原位文件替换**：<br>• 清空 8 张数据表并执行 `VACUUM` 清理残留数据页，创建 16 个 `BEFORE INSERT / UPDATE` 触发器（执行 `SELECT RAISE(IGNORE);`）忽略后续写入请求（避免使用 `chmod 000` 导致系统服务因权限报错而反复重试耗电）。<br>• 直接替换原路径文件并配合开机脚本校验恢复，**不使用 `mount --bind`**，不在 `/proc/mounts` 产生挂载记录，兼容 Zygisk Next。<br>• *免 Root ADB*：关闭系统配置开关并清理外置存储残留副本。 |
| **2. 跨应用风控查询接口** | `com.miui.securitycenter.provider.XSOFProvider`<br>`FraudDetectionProvider` | 向第三方应用（京东、支付宝、抖音、闲鱼、高德地图等）提供本机应用风险状态、通话叠加层状态及设备环境查询 | **保持接口启用 + 返回 0 条记录**：<br>• 不禁用 ContentProvider（防止第三方应用启动或支付时因查询接口异常而闪退），配合底层数据库的触发器拦截机制，使查询请求正常返回 `0` 条记录。 |
| **3. 安全中心内部采集服务** | `MiFraudDetectionService`<br>`MiSafetyDetectService`<br>`OperationListCollectService`<br>`ImageProtectService` 等 | 实时无障碍窗口控件与包名采集、防诈云端比对、本地相册图片检测、应用启动预测日志 | **按组件禁用后台采集服务**：<br>• 保持安全中心主包（`com.miui.securitycenter`）启用（防止系统无法正常开机或权限管理界面失效），仅通过 `pm disable` 禁用负责后台数据采集的内部 Service。 |
| **4. 运营商设备管理（DM）上报组件** | `com.mobiletools.systemhelper`（中国联通）<br>`com.miui.dmregservice`（中国电信/移动）<br>`com.xiaomi.registration` | 开机及定时唤醒读取双卡 **IMEI/MEID、IMSI、ICCID、GPS 经纬度坐标、基站 LAC/CID、Wi-Fi SSID/BSSID、全机应用前台运行时长与流量统计** 并上报运营商平台 | **清理本地数据 + 禁用/卸载组件**：<br>• 删除本地明文数据库与 SharedPreferences 缓存文件，并通过 `pm disable-user` 或 `pm uninstall -k --user 0` 停用对应包名。 |
| **5. 云端应用扫描引擎** | `com.miui.guardprovider`（内置腾讯 TMS、安天、小米云查杀引擎） | 已安装及新安装 APK 的包名、签名哈希、证书信息、MD5、安装来源包名 | **清理数据库 + 禁用服务 + 独立防火墙链拦截**：<br>• 清空本地扫描记录数据库并禁用后台服务；在 `iptables`/`ip6tables` 中创建独立的 `PRIVACY_GUARD` 子链拦截该组件 UID 的联网请求（**不执行 `iptables -F`**，不影响 FlClash / Sing-box 等 VPN 工具的 `tun0` 路由规则）。 |
| **6. 系统遥测与广告统计组件** | `com.xiaomi.security.onetrack`、`com.miui.analytics`（含 User 0 主空间与 User 999 双开空间）、`com.miui.systemAdSolution`、`com.miui.daemon`、`com.bsp.catchlog`、`com.miui.misightservice` | OAID/VAID 广告标识符、系统功能使用统计事件、崩溃日志与硬件运行状态统计 | **多用户空间同步禁用**：<br>• 同步禁用主空间（User 0）与应用双开空间（User 999）中的遥测与广告组件，配置防火墙 UID 联网拦截。 |
| **7. 系统云控宿主组件（HTML查看器）** | `com.android.htmlviewer`（常驻进程 `com.android.htmlviewer:remote`）<br>路径：`/system/priv-app/HTMLViewer/HTMLViewer.apk` | 除承担全系统云控参数下发（`SettingsCloudControlService`）和设置搜索索引外，内置了 OneTrack 统计 SDK 与 MiPush 性能上报模块，会在同步云控时调用 `READ_PHONE_STATE` 和 `READ_DEVICE_IDENTIFIERS` 读取设备状态，并在本地生成 `onetrack_cache`、`universal_ot_monitor_db`、`files/perf/` 等埋点文件 | **保留云控核心 + 撤销标识符权限 + 清理遥测数据库**：<br>• **不冻结或卸载主应用，且完整保留 `cloud_all_data.db`（系统云控配置库）与 `global_search_result_database`（设置搜索索引库）**，确保系统更新、设置搜索及应用云控正常。<br>• 通过 `appops` 将其 `READ_PHONE_STATE`（UID 级与包级）和 `READ_DEVICE_IDENTIFIERS` 设为 `ignore`，并清理其内部的 OneTrack 统计数据库、MiPush 性能日志及 WebView 访问记录。 |

---

## 仓库目录结构

```text
android-privacy-guard/
├── SKILL.md                                # AI Agent 技能指令文件（3 步标准工作流）
├── README.md                               # 项目说明文档
├── references/
│   └── leakage_reference_memo.md           # 隐私泄露接口、进程与数据库备忘录
└── scripts/
    ├── audit_privacy_leaks.sh              # [第 1 步] 只读隐私泄露检测脚本（支持 Root & 普通 ADB）
    ├── build_trigger_blackhole_db.py       # [第 2 步] 生成包含 16 个 RAISE(IGNORE) 触发器的空数据库模板
    ├── apply_root_remediation.sh           # [第 2 步 - Root] 替换数据库、禁用采集服务、配置防火墙与开机恢复脚本
    ├── apply_adb_remediation.sh            # [第 2 步 - 免 Root ADB] 禁用运营商上报与遥测组件、关闭系统统计开关
    ├── verify_post_reboot.sh               # [第 3 步] 重启后验证触发器状态、防火墙规则与写入拦截效果
    └── rollback_privacy_guard.sh           # [还原脚本] 恢复至执行加固前的初始状态（支持 Root & ADB）
```

---

## 快速开始与还原指南

### 1. 安装 Skill

将本仓库克隆到 AI 编程助手（如 Antigravity / Claude Code）的全局或工作区 `skills` 目录下：

```bash
git clone https://github.com/<your-username>/android-privacy-guard.git ~/.gemini/config/skills/android-privacy-guard
```

### 2. 连接设备并对话执行（检测 ➔ 加固 ➔ 重启验证）

在手机或平板上开启 **开发者选项 ➔ USB 调试**（以及 **USB 调试（安全设置）**）后连接电脑，通过自然语言向 AI 发送指令即可按流程执行：

- **第一步（只读检测）**：*"帮我检测一下这台小米手机/平板有哪些系统隐私泄露或后台数据采集"*
- **第二步（执行加固）**：*"我有 Root 权限（或：我只有普通 ADB 权限），请向我说明加固方案并按照不影响应用正常使用的方案执行"*
  > **权限说明**：AI 会根据设备当前的权限类型——**永久 Root（Magisk / KernelSU / APatch）**、**漏洞临时 Root（Temp Root）** 或 **免 Root 普通 ADB**，选择对应的处理脚本并在修改前自动备份原始文件。
- **第三步（重启验证）**：*"重启设备，帮我验证隐私加固方案在重启后是否继续生效"*

### 3. 如何还原到初始状态（Rollback）

如果需要送修售后、参与系统测试或恢复系统默认的采集设置，连接设备后直接向 AI 发送指令：

- **还原指令**：*"帮我回退之前的隐私加固方案，恢复到执行前的初始状态"*

AI 将调用 `scripts/rollback_privacy_guard.sh` 执行以下恢复操作：
1. **Root 设备**：删除 `/data/adb/service.d/99_privacy_guard.sh` 开机脚本与数据库模板、移除 `PRIVACY_GUARD` 防火墙子链、从 `/data/adb/privacy_guard_backup/` 恢复加固前备份的原始数据库文件、重新启用所有被禁用的系统服务与组件。
2. **免 Root ADB 设备**：重新启用或恢复所有被禁用、卸载的运营商上报与遥测组件，恢复系统默认配置开关。

---

## 白名单与兼容性说明

为保证日常功能正常可用，方案默认保留以下组件与网络接口：

1. **保留安全中心主应用（`com.miui.securitycenter`）**：避免系统无法正常启动、应用权限管理界面失效或电池统计异常。
2. **保留 HTML查看器（`com.android.htmlviewer`）主应用及 `cloud_all_data.db` 云控数据库**：在 HyperOS / MIUI 中，`com.android.htmlviewer` 除了用于展示本地 HTML 文本与开源协议外，还承载了系统级云控服务（`SettingsCloudControlService` 与 `SettingsProvider`，通过 `cloud_all_data.db` 维护全系统的模块开关、温控、显示与兼容性配置）以及系统设置搜索索引（`SearchIndexablesProvider`）。方案完整保留该应用及 `cloud_all_data.db` 数据库，仅撤销其读取电话状态与硬件标识符的权限，并清理其内置的 OneTrack 遥测数据库与 MiPush 性能日志，不影响系统更新与应用云控。
3. **放行小米智能卡包 NFC 门禁校验域名（`fraud-detection.engine.miui.com`）**：屏蔽该域名会导致模拟门禁卡时提示实名校验失败；由于本地 `fraud_detection_data.db` 已通过 SQLite 触发器保持为 `0` 条记录，放行该域名仅用于完成卡包接口校验，不会上传本地使用记录。
4. **放行国家 110/120 紧急呼叫位置上报接口（`eps.caict.ac.cn` / `gateway-papa.cloud.weizhi.com`）**：仅在拨打紧急求助电话时启用，日常无数据传输。

---

## 免责声明

1. 本项目仅供个人设备安全审计、隐私保护研究与系统配置管理使用。
2. 所有脚本均不包含任何特定设备序列号或个人数据，执行修改前会自动将原始文件备份至 `/data/adb/privacy_guard_backup/`。
3. 请勿在开启 `dm-verity` / `AVB` 校验且未解锁 Bootloader 的设备上直接修改 `/system` 或 `/vendor` 等只读系统分区。

---

## License

This project is licensed under the [MIT License](LICENSE).
