# Android / 国产 ROM 隐私与遥测泄露接口全景备忘录 (Cross-Agent & Cross-Brand Reference Memo)

> **用途说明**：本备忘录汇总了经过实机逆向与数据库级取证证实的系统级隐私收集组件、后台守护进程、本地明文/风控画像数据库、跨应用调取接口（Provider/Permission）、网络上报域名及各品牌手机（小米/澎湃 HyperOS、OPPO/一加/真我 ColorOS、vivo/iQOO OriginOS、荣耀 MagicOS、三星等）的对应组件映射。**本文档已彻底脱敏，不含任何特定用户或设备的私有标识信息。**

---

## 一、 运营商终端管理探针（DM 探针）与静默注册组件（全品牌通病）

国行手机（无论插入哪家运营商 SIM 卡，甚至拔卡仅连 Wi-Fi）普遍在 `/system/priv-app/` 或 `/product/priv-app/` 下预置三大运营商的终端管理（Device Management, DM）探针与自注册服务。

### 1. 核心包名、进程与跨品牌映射表

| 组件类别 | 小米 (MIUI / HyperOS) | OPPO / 一加 / 真我 (ColorOS) | vivo / iQOO (OriginOS) | 荣耀 / 华为 (MagicOS / EMUI) | 三星 / 摩托罗拉 / 通用国行 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **联通 DM 探针（最典型）** | `com.mobiletools.systemhelper` | `com.mobiletools.systemhelper` | `com.mobiletools.systemhelper` | `com.mobiletools.systemhelper` | `com.mobiletools.systemhelper` |
| **电信/移动 DM 自注册** | `com.miui.dmregservice` / `com.xiaomi.registration` | `com.oppo.ctautoregist` / `com.oplus.dm` | `com.vivo.dm` / `com.vivo.regservice` | `com.hihonor.regservice` / `com.huawei.regservice` | `com.samsung.android.dm` / `com.ct.client.dm` |
| **虚拟 SIM / 漫游探针** | `com.miui.virtualsim` / `com.miui.vsimcore` | `com.redteamobile.roaming` | `com.vivo.vsim` | `com.hihonor.skytone` | `com.redteamobile.*` |

### 2. 实锤泄露内容与工作机制（以 `com.mobiletools.systemhelper` 为代表）
- **跨网常驻唤醒**：即便设备插入的是**中国移动或中国电信 SIM 卡**，`com.mobiletools.systemhelper`（中国联通探针）依然常驻后台，并通过 `AlarmManager` 注册高优先级 `ELAPSED_WAKEUP` 唤醒锁，全天数十次唤醒设备：
  - `com.mobiletools.systemhelper/.control.GetSignalInfoReceiver`（高频基站与信号采集）
  - `com.mobiletools.systemhelper/.control.SignalInfoRegisterReceiver`（信号与定位上报）
  - `com.mobiletools.systemhelper/.control.AppInfoRegisterReceiver`（全机应用使用情况上报）
  - `com.mobiletools.systemhelper/.control.ScheduleRegisterReceiver`（定时设备信息注册）
  - `com.mobiletools.systemhelper/.control.SIMStateReceiver` / `OnBootReceiver` / `ConnectStateReceiver`
- **本地明文数据库路径**：
  - `/data/data/com.mobiletools.systemhelper/databases/systemhelper`
  - `/data/data/com.mobiletools.systemhelper/databases/signalhelper`
- **数据库明文记录并上报的具体字段（JSON 载荷）**：
  1. **硬件与身份强标识**：双卡槽 `imei1` / `imei2`、`meid`、`imsi`、`iccid`、手机型号、ROM 版本、系统指纹、MAC 地址。
  2. **高精度地理位置与网络拓扑**：精确到小数点后 6 位的 **GPS 经纬度坐标（`longitude`, `latitude`）**、中文省市区县地理名称、蜂窝基站 `tac` / `lac` / `cid`、信号强度 `rsrp`/`sinr`、当前连接的 **Wi-Fi SSID 名称与路由器 BSSID（MAC 地址）**、本机公网/内网 IPv4 与 IPv6 地址。
  3. **全机应用行为统计（`AppInfo` 数组）**：依赖 `PACKAGE_USAGE_STATS` 特权，记录手机上**所有第三方应用**的包名、应用名、版本号、前台运行时长（`runTime`）、启动次数（`launchCount`）以及消耗的移动/Wi-Fi 流量字节数。
- **穿透 VPN 隧道**：系统 `dumpsys netstats detail` 证实，该进程流量会直接进入 `type=17 (TYPE_VPN)` 虚拟网卡，将上述本机真实 IMEI、ICCID 与 GPS 坐标通过用户的 VPN 代理节点明文/弱加密发往 `dm.wo.com.cn:18080`，造成代理节点与真实机主身份的直接关联暴露。

---

## 二、 本地 72 小时涉诈行为画像库与跨应用风控框架 (`XSOF`)

### 1. 本地行为画像数据库：`/data/misc/user/0/securitycenter/fraud_detection_data.db`
- **基本特征**：
  - 归属：`system:system`，权限 `0660`，SELinux 上下文 `u:object_r:misc_user_data_file:s0`，SQLite `PRAGMA user_version = 1`。
  - **无关闭开关**：即便用户在系统设置及手机管家中**关闭所有“电诈防护 / 安全守护”开关**，该本地行为记录器依然在后台默默记录用户操作（且在无 SIM 卡的纯 Wi-Fi 平板上同样存在并工作）。
  - **留存周期异常**：官方宣称记录滚动保留 72 小时，但实机数据库取证发现 **`screen_share`（屏幕共享/录屏表）存在跨月留存未自动清除的情况**，且 `sqlite_sequence` 自增主键会永久暴露历史累计触发总次数（例如累计截屏次数）。
- **数据库内含的 8 张核心监控表及字段明细**：

| 表名 | 监控行为类别 | 详细字段 (`CREATE TABLE` Schema) | 隐私泄露风险说明 |
| :--- | :--- | :--- | :--- |
| **`install_app`** | 应用安装监控 | `_id`, `pkg_name`, `app_name`, `source` (安装器包名), `version_code`, `md5` (安装包哈希), `install_finish_time`, `app_tag_id`, `security_tag_id` | 记录用户安装的每一个非商店/Root/侧载应用包名、来源及 APK 文件的 MD5 哈希 |
| **`fraud_phone`** | 传统电话特征 | `_id`, `call_start_time`, `call_end_time`, `is_fraud_call`, `tel_location` (归属地), `tel_number_md5` (对方号码 MD5), `operator`, `is_chinese_number`, `is_virtual_operator`, `is_active` (主被叫), `duration` | 记录通话起止时间、时长及对方电话号码的 32 位 MD5（手机号空间极小，MD5 可被轻易彩虹表反查还原明文号码） |
| **`voip_record`** | 网络音视频通话 | `_id`, `voip_record_package_name` (如微信/QQ/会议软件), `voip_record_start_time`, `voip_record_end_time`, `is_active`, `is_fraud_call`, `duration` | 记录用户使用微信、QQ 等进行语音/视频通话的精确起止时间与时长 |
| **`screen_share`** | 录屏与屏幕共享 | `_id`, `screen_share_package_name` (如 `com.miui.screenrecorder`), `screen_share_start_time`, `screen_share_end_time`, `is_active`, `duration` | 记录每一次系统录屏或会议软件投屏的精确毫秒级时间戳与持续时长 |
| **`screenshot`** | 系统截屏监控 | `_id`, `screenshort_time` | 记录每一次系统截屏的精确毫秒级时间戳，`_id` 暴露历史截屏总次数 |
| **`fraud_url`** | 网页访问特征 | `_id`, `access_time`, `url_type` | 记录触发风控规则的网页访问时间戳与分类标签 |
| **`airplane_mode`** | 飞行模式切换 | `_id`, `airplane_mode_on`, `airplane_mode_change_time` | 记录每一次开启/关闭飞行模式的时间点 |
| **`call_forwarding`** | 呼叫转移监控 | `_id`, `reason`, `enabled`, `timestamp` | 记录呼叫转移状态变更 |

### 2. 第三方商业 App 跨应用调取接口（`XSOF` 框架）
- **暴露原理（普通权限漏洞级设计）**：
  - `com.miui.securitycenter` 声明了权限 `com.xiaomi.security.permission.ACCESS_XSOF`，并将其保护级别设为 **`protectionLevel="normal"`（普通权限）**！
  - 这意味着**任何第三方商业 App 只需在 `AndroidManifest.xml` 中写一行 `<uses-permission android:name="com.xiaomi.security.permission.ACCESS_XSOF"/>`，安装时系统即自动静默批准，完全不需要用户弹窗授权，也不在权限管理界面向用户展示**。
- **暴露的 ContentProvider 接口与后台服务**：
  - Provider 1：`com.miui.securitycenter/com.xiaomi.security.xsof.XSOFProvider` (Authority: `com.xiaomi.security.xsof.provider`)
  - Provider 2：`com.miui.securitycenter/com.xiaomi.security.xsof.frauddetection.provider.FraudDetectionProvider` (Authority: `com.xiaomi.security.xsof.FraudDetectionProvider`)
  - 后台服务 1：`com.miui.securitycenter/com.xiaomi.security.xsof.frauddetection.service.MiFraudDetectionService`
  - 后台服务 2：`com.miui.securitycenter/com.xiaomi.security.xsof.MiSafetyDetectService`
- **实机检出已获取 `ACCESS_XSOF` 权限并调取风控数据的典型应用**：
  - **商业 App (`ACCESS_XSOF`)**：京东 (`com.jingdong.app.mall`)、支付宝 (`com.eg.android.AlipayGphone`)、抖音 (`com.ss.android.ugc.aweme*`)、闲鱼 (`com.taobao.idlefish`)、高德地图 (`com.autonavi.minimap`)、大众点评 (`com.dianping.v1`)、阿里巴巴 (`com.alibaba.wireless`)、通义千问 (`com.aliyun.tongyi`) 等。
  - **系统级特权应用 (`ACCESS_XSOF_FRAUD_DETECTION`, `prot=signature`)**：应用包安装器 (`com.miui.packageinstaller`)、应用商店 (`com.xiaomi.market`)、系统浏览器 (`com.android.browser`)、数字车钥匙 (`com.xiaomi.digitalkey`)。
- **本地调用审计日志路径**：
  - `/data/data/com.miui.securitycenter/shared_prefs/xsof_authority_preferences.xml`（直接以 `<long name="包名" value="时间戳" />` 格式记录近期调取过 `XSOF` 接口的第三方 App 名单！）
  - `/data/data/com.miui.securitycenter/shared_prefs/xsof_network_detector.xml`

---

## 三、 安全中心云查杀、行为预测与系统遥测全家桶

### 1. 安全扫描与云查杀引擎插件 (`com.miui.guardprovider`)
- **角色与危险权限**：独立于手机管家主包之外的云查杀引擎插件（集成腾讯 TMS `qqsecure`、安天 `avlsecdata`、小米 `flamingo` 引擎），拥有 `MANAGE_EXTERNAL_STORAGE`（所有文件访问权）、`CAPTURE_AUDIO_OUTPUT`、`CAPTURE_VOICE_COMMUNICATION_OUTPUT`（通话音频捕获）、`PEERS_MAC_ADDRESS` 等高危特权。
- **常驻服务**：`com.miui.guardprovider/.server.VirusScanService`（被 `com.miui.securitycenter` 跨进程常驻绑定，且其流量同样会穿透 VPN 隧道）。
- **本地敏感数据库 (`/data/data/com.miui.guardprovider/databases/`)**：
  - `flamingo.db` (数 MB)、`miui_antivirus.db` (数 MB)、`qqsecure.db`、`avlsecdata`、`virus_scan_server.db`（记录本地扫描过的所有 APK 路径、签名哈希、风险评级）及 `onetrack*` 遥测库。

### 2. 手机管家 (`com.miui.securitycenter`) 内部采集子服务与本地数据库
- **注意：绝不可卸载或禁用 `com.miui.securitycenter` 主包（会导致系统无限重启“卡米”）！** 但可通过 Root 精准禁用其内部的隐私采集子组件：
  - `com.xiaomi.security.xsof.frauddetection.service.MiFraudDetectionService`（72h 涉诈行为采集核心服务）
  - `com.xiaomi.security.xsof.MiSafetyDetectService`（设备环境安全检测服务）
  - `com.miui.antifraud.AntiFraudReceiver`（反诈广播接收器）
  - `com.miui.antivirus.service.GuardService` / `DialogService` / `com.miui.antivirus.receiver.UpdaterReceiver`（实时病毒监控与云库更新）
  - `com.miui.securityscan.fileobserver.ImageProtectService`（相册/截屏文件观察服务）
  - `com.miui.ai.service.OperationListCollectService`（用户操作序列收集服务）
  - `com.miui.apppredict.service.AppPredictService` / `AiService`（应用启动行为预测采集服务）
  - `com.miui.analytics.AnalyticsService`（内置统计分析服务）
- **手机管家内部敏感数据库 (`/data/data/com.miui.securitycenter/databases/`)**：
  - `risky_app.db`（风险应用库）、`app_predict_data.db`（应用使用预测库）、`global_satisfaction_data.db`、`month_report.db`、`one_track_cloud`、`onetrack`、`onetrack_cache`、`universal_ot_monitor_db`、`preload.db`。

### 3. 系统级遥测、广告与日志抓取全家桶（及他牌对应组件）

| 功能角色 | 小米 / HyperOS 包名或进程 | OPPO / ColorOS 对应包名 | vivo / OriginOS 对应包名 | 泄露内容与特征说明 |
| :--- | :--- | :--- | :--- | :--- |
| **核心埋点统计** | `com.miui.analytics` | `com.nearme.statistics.rom` / `com.oplus.statistics.rom` | `com.vivo.abe` / `com.vivo.epm` | 会在 `/data/app` 静默自升级；**在开启应用双开（`User 999`）的设备上，`XSpaceManagerService` 会在每次开机时在 `User 999` 重新释放并启动 `u999_a*` 进程！** |
| **安全中心独立埋点** | `com.xiaomi.security.onetrack` | `com.oplus.onetrace` | `com.vivo.security.collect` | 独立后台进程，专门上报安全组件遥测日志 |
| **系统广告服务 (MSA)** | `com.miui.systemAdSolution` | `com.opos.ads` | `com.vivo.magazine` / `com.bbk.theme.ad` | 拉取系统开屏广告、摇一摇广告配置与广告归因遥测 |
| **系统性能/行为守护** | `com.miui.daemon` | `com.oplus.obrain` | `com.vivo.rms` | 以 `system (uid=1000)` 权限运行，采集全系统性能、温控与应用使用快照（需配合 `killall` 停止） |
| **基带与内核日志抓取** | `com.bsp.catchlog` | `com.oplus.logkit` | `com.vivo.logger` | 抓取基带、Wi-Fi、内核崩溃与诊断日志 |
| **用户反馈与打点上报** | `com.miui.bugreport` / `com.miui.uireporter` | `com.oplus.ocar` / `com.coloros.oshare` | `com.bbk.iqoo.logsystem` | 后台错误报告与 UI 交互埋点上报 |
| **硬件/内核遥测守护** | `com.miui.misightservice` + native `misight` | `com.oplus.nhs` | `com.vivo. PEM` | 包含 Java 层服务与底层 native `misight` 守护进程（需执行 `stop misight`） |
| **AI 通话防换脸预警** | `com.xiaomi.aiasst.service` / `.vision` | `com.oplus.aicall` | `com.vivo.ai.copilot` | 开启“AI 通话预警”后，在通话期间抓取画面与语音特征送云端 (`detection-aigc.engine.miui.com`) 研判；若用户使用自动接听功能可保留应用并仅在防火墙拦截 AIGC 上报域名 |

### 4. 关键系统设置项 (`settings`) 泄露源
- `secure` / `global` `upload_apk_enable`：`1` 表示开启“上传未知安装包至云端检测”。
- `secure` `cloud_antispam`：`1` 表示开启云端防骚扰实时查询。
- `secure` `fraud_num_state` / `fraud_num_state_sim_2`：`1` 表示开启电诈号码云端联动校验。
- `secure` `sec_pc_config_scenario_policies_open`：`1` 表示开启隐私场景策略云控。
- `secure` `upload_log_pref` / `upload_debug_log_pref`：诊断日志自动上传开关。
- `global` / `secure` `FBO_UPLOAD_LIST`：以 JSON 数组明文存储用户最常使用的 Top 10 应用包名列表（供存储碎片整理与云端统计读取）。

---

## 四、 网络域名用途考证与“精准拦截 vs 严禁误杀”矩阵

在配置内核防火墙（`iptables` / `ip6tables`）时，**必须严格区分真实遥测上报域名与关乎硬件正常功能/生命救援的域名**：

### 1. 必须拦截的真实遥测与包名上报域名（共 11 个核心域名）
1. **`flash.sec.miui.com`**：安全中心通用接口——其中 `/user/ra` 接口实锤用于**上传本机已安装应用的包名与版本号**做风险检测；`/gc/dir` 用于拉取垃圾清理路径库。
2. **`dm.wo.com.cn`**（含 `:18080` 端口）：中国联通终端管理探针 (`com.mobiletools.systemhelper`) 遥测上报服务器。
3. **`virus-engine.sec.miui.com`**：安全中心云查杀与 APK 特征上报接口。
4. **`api.sec.miui.com`**：安全中心云控与风控数据交互主接口。
5. **`notify.sec.miui.com`**：安全中心风控推送与状态回传接口。
6. **`pwn.sec.miui.com`**：安全中心漏洞与威胁情报上报接口。
7. **`detection-aigc.engine.miui.com`**：AI 通话防换脸预警的云端音视频特征研判接口。
8. **`data.mistat.xiaomi.com`**：小米 OneTrack / MiStat 核心统计上报域名。
9. **`tracking.miui.com`**：MIUI/HyperOS 系统行为追踪上报域名。
10. **`sdkconfig.ad.xiaomi.com`**：小米系统广告 SDK 配置下发与归因域名。
11. **`beacon.qq.com`**：`com.miui.guardprovider` 内置腾讯安全模块（TMS / 灯塔）遥测上报域名。

### 2. 严禁在防火墙盲目拦截的域名（避免破坏正常功能与紧急救援！）
1. **🟢 放行 `fraud-detection.engine.miui.com`（保障 NFC 门禁卡功能）**：
   - **真实用途**：经固件反编译核实，该域名在整个系统中仅被小米安全中心的 **NFC 门禁模块 (`com.miui.nfcaccess`)** 调用，用于下发 NFC 门禁卡防冒用白名单配置，并不上报通话或私密数据。
   - **正确做法**：由于我们已在本地通过 SQLite 触发器黑洞废除了 `fraud_detection_data.db` 并停用了 `MiFraudDetectionService`，本地反诈画像已彻底断源；防火墙放行 `fraud-detection.engine.miui.com` 可 **100% 保障小米钱包刷 NFC 门禁卡正常工作**。
2. **🟢 放行 `eps.caict.ac.cn` (`/eps/collect`) 与 `gateway-papa.cloud.weizhi.com` (`/papa/upload`)（保障 110/120 紧急救援定位）**：
   - **真实用途**：这两个域名属于国家统一紧急报警辅助通道，仅在用户拨打 **110、120** 紧急电话时上传本机号码与定位以辅助生命救援，平时完全静默。**严禁在防火墙中封锁紧急救援通道！**
