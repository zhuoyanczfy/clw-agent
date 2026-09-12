# AGENTS.md — 光旅之盘（Compass of Light & Wanderlust）

> 本文件面向所有 AI 编码代理（Claude Code / Cursor / Codex / Qoder 等），提供项目上下文与硬性约定。
> 修改本项目代码前请先通读本文；与本文冲突的旧文档（如 deploy_ops.md 部署路径）以本文为准。

## 1. 项目概述

「光旅之盘」（英文 Compass of Light & Wanderlust，2026-08-14 定名；旧名「珍惜·爱·温暖 / CLW」已作废，对外一律使用新名）是一款作为**礼物赠送**的美食系陪伴应用，交付形态为 **Android APK + Web 版**（`http://<服务器>/web/`，iPhone Safari 添加到主屏幕全屏运行）。

- Android 应用名「光旅之盘」，包名 `com.gift.dailycare`（两者勿改不一致）
- 设计原则：**不部署后端也能完整使用**（APP 内置 40 道美食库离线可用），部署后端后可获动态数据与 AI 服务
- 核心模块：
  1. **美食足迹**：南京分区地图（flutter_map + 腾讯瓦片）、用餐记录（含照片）、待尝清单、AI 推荐官（DeepSeek，多轮对话 + SSE 流式）
  2. **陪伴系统**：宠物名片（照片/疫苗/驱虫）、每日塔罗占卜（韦特牌阵 + DeepSeek 解读）、好句好段（Hitokoto + Pixabay 配图）、每日菜单
  3. **心愿清单**：情侣 bucket list，标记已体验 + 照片回忆 + 回忆日记（Web 版底部第 5 个 tab「心愿」）
  4. **智能提醒**：喝水/吃美食/早睡定时推送、宠物疫苗/驱虫提前 7 天 10:00 单次提醒（APP 端；Web 端无通知）

## 2. 技术栈与关键依赖

| 层 | 技术 |
|---|---|
| 前端 | Flutter 3.44.9（Dart 3.12.2），Android SDK 36（AGP 9.0.1 / Kotlin 2.3.20 / Gradle 9.1.0），JDK 17 |
| 后端 | Django 4.2 + Python 3.10 + SQLite，Gunicorn + Nginx |
| 第三方服务 | DeepSeek（AI 对话/塔罗解读）、高德（定位/天气）、Unsplash/Pixabay（配图）、Hitokoto（好句） |

关键 Flutter 依赖及注意点：

- `flutter_local_notifications` 19：需在 `app/android/app/build.gradle.kts` 启用 **core library desugaring** 并添加 `desugar_jdk_libs 2.1.4`
- `timezone`：通知排程前必须 `initializeTimeZones()` + `tz.setLocalLocation(tz.getLocation('Asia/Shanghai'))`，否则默认 UTC 晚 8 小时
- `flutter_map` 8.x + `latlong2`（足迹地图，腾讯瓦片 rt0.map.gtimg.com 带 CORS 头可直接用）
- `cached_network_image`、`http`、`shared_preferences`、`crypto`（内置库 md5 日期轮换算法）、`image_picker`、`package_info_plus`、`path_provider`
- Gradle 属性需 `kotlin.incremental=false`（避免增量缓存损坏导致构建失败）

后端依赖由 `backend/requirements.txt` 管理；密钥（DeepSeek/高德/Unsplash 等）存 `backend/config/config.ini`，**不入库**。

## 3. 目录结构（关键路径）

```
app/                    # Flutter 客户端（Android APK + Web）
  lib/config/app_config.dart      # 离线回退配置（昵称/认识日期/后端地址）
  lib/services/remote_config.dart # 远程配置拉取（/api/config/）
  lib/services/notification_service.dart / app_updater.dart / foodmap_api.dart
  lib/data/dishes.dart            # 内置美食库（生成产物，勿手改）
  lib/pages/                      # 各页面
backend/                # Django 后端
  foodmap/views.py               # API 视图 + APP_CONFIG_DEFAULTS 配置字典
  foodmap/services/meal_pool.py  # 每日菜单服务（读 meal_pool.json）
  foodmap/services/cover_image.py / data/quotes.py
  config/config.ini              # 密钥（不入库）
  manage.py
server/                 # 数据源与生成脚本
  dishes.py (dishes_full.py)     # 美食数据唯一来源
  gen_dishes_dart.py             # 生成 app/lib/data/dishes.dart
tmp/                    # 临时文件（不入库）
deploy_ops.md           # 部署手册（⚠️ 部署路径已过时，见第 5 节）
```

## 4. 本地构建与运行（Windows）

**构建环境**（已配好）：Flutter SDK `D:\flutter`；JDK17 `D:\jdk17\jdk-17.0.20+8`（**每次新终端需** `$env:JAVA_HOME="D:\jdk17\jdk-17.0.20+8"`）；Android SDK `D:\android-sdk`。国内镜像：`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`、`PUB_HOSTED_URL=https://pub.flutter-io.cn`（用户级已设）；Gradle 走腾讯镜像、Maven 走阿里云镜像。

**APK 打包**（默认用）：

```powershell
cd app
flutter build apk --release --split-per-abi --tree-shake-icons
# 真机安装 app-arm64-v8a-release.apk（约 19MB）；fat 包约 55MB
```

**Web 构建**：

```powershell
cd app
flutter build web --release --base-href /web/   # 产物 build/web 约 42MB，CanvasKit 各变体勿删
```

**后端本地运行**：

```powershell
py -3.10 -m venv .venv
.venv\Scripts\activate
pip install -r backend/requirements.txt
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```

**美食数据同步**：改 `server/dishes.py` 后运行 `py -3.10 tmp/gen_dishes_dart.py` 重新生成 `app/lib/data/dishes.dart`；后端菜库用 `python manage.py seed_dishes` 更新。两端 md5 轮换算法必须保持一致。

## 5. 部署拓扑（服务器 139.196.27.224，HTTP 明文 80，无 HTTPS）

| 环境 | 目录 | systemd 服务 | gunicorn | nginx 路径 |
|---|---|---|---|---|
| PROD 生产 | `/opt/foodmap-prod` | `foodmap-prod` | 127.0.0.1:8001 | `/` |
| TEST 测试 | `/opt/foodmap/app` | `foodmap` | :8000 | `/test/` |
| Web 前端 | `/opt/foodmap/web/`（纯静态） | — | — | `/web/` |

- 两环境**共用 venv**：`/opt/foodmap/venv/bin/python`（python3.11；`/opt/foodmap{,-prod}/venv` 是失效残留路径，勿据其判断依赖）
- **deploy_ops.md 中的部署路径已过时**，部署前以 `systemctl cat <服务名>` 输出为准
- **后端发版顺序**：备份(.bak) → SFTP 上传 → `manage.py migrate` → `systemctl restart foodmap-prod` → `systemctl is-active` 确认
- **Web 发版流程**：本地 `flutter build web --release --base-href /web/` → SFTP 覆盖 `/opt/foodmap/web/` → 纯静态**无需 reload nginx** → 用户刷新即更新（入口 index.html no-cache 保发版即生效）
- 服务器本机 curl 验证必须带 `-H "Host: 139.196.27.224"`（Django ALLOWED_HOSTS）；API 另需 `X-Api-Token` 头（token 值见仓库配置，勿写入文档）
- 验证走**公网 IPv4**（`curl -4 http://139.196.27.224/...`）：localhost 测 80 会解析 IPv6 命中 nginx 默认站点，得到误导性 404；直接 curl 127.0.0.1:8001 会因 Host 校验返回 400
- media 目录属主必须是 `foodmap:foodmap`（gunicorn 以 foodmap 运行，属主 root 会导致上传 500）

## 6. 开发与验证规范（硬性约定）

1. **日常验证只跑 `flutter analyze` + `flutter test`，不打包 APK**（打包耗时长，仅在用户明确说「打包」时执行 `flutter build apk --release`）
2. **测试只在测试环境执行**（`/opt/foodmap/app`，nginx `/test/`）；正式环境仅允许部署/重启/只读验证。例外：用户明确授权后可在正式环境测试，但**测完必须彻底清理测试数据**（记录/照片删除，DB 与磁盘零残留）
3. **专属信息与通知文案统一后台配置**：后端 `backend/foodmap/views.py` 的 `APP_CONFIG_DEFAULTS` + Admin「APP配置」覆盖；APP 经 `RemoteConfig`（`services/remote_config.dart`）启动拉 `/api/config/` 并缓存，`app_config.dart` 仅作离线回退。**新增配置键需同时改后端默认字典与 RemoteConfig 键常量**
4. **美食数据唯一来源是 `server/dishes.py`**，改后必须运行生成脚本同步 `app/lib/data/dishes.dart`
5. 通知文案统一暖心第二人称称呼（`{herName}` 占位符，来自 RemoteConfig）
6. **UI 主题（2026-08-14 改版）**：暖黄色调（`theme.dart` 中 primary=`0xFFFFB300`、primaryDark=`0xFFE69600`、bg=`0xFFFFFBF0`）；装饰符号一律**星星**（⭐/`Icons.star`），**禁用爱心与粉色**；红色仅用于警示（疫苗逾期/删除）
7. 前端选图压缩：`pickMultiImage` 带 `maxWidth: 1600` + `imageQuality: 82`（Web 端无效，靠 nginx 60m 上传限制兜底）；上传 timeout 120s

## 7. 架构不变量（改动前必读）

1. **每日菜单完全解耦于 Dish 模型**：仅由 `meal_pool.json` + `meal_pool.py`（`random_meal()`）提供，`api_meal_today` 视图只从其读取。改菜单内容必须改 `meal_pool.json`，改 Dish 表不影响每日菜单
2. **split-per-abi 的 versionCode 带 ABI 前缀**（arm64-v8a=2000+N、armeabi-v7a=1000+N、x86_64=4000+N），**版本比较必须用 versionName**（APP 内更新 app_updater 即如此实现）
3. **历史会话 = 左侧 Drawer + 触底分页**：后端 `/api/chat/sessions/` 支持 `offset/limit` 并返回 `total`；前端 `chat_history_sheet.dart` 管分页状态，`ai_recommend_page.dart` 集成 Drawer
4. **跨日期通知**（宠物疫苗/驱虫提前 7 天 10:00）依赖 Android **AlarmManager**（单次精确触发，系统级存活）+ **ScheduledNotificationBootReceiver**（`BOOT_COMPLETED` 重注册）；相关权限：RECEIVE_BOOT_COMPLETED、SCHEDULE_EXACT_ALARM、POST_NOTIFICATIONS
5. **Web 兼容铁律**：`dart:io` 不得进入 Web 编译路径——用条件导入 `if (dart.library.io)` 拆 `_io/_stub`（例：`local_image{,_io,_stub}.dart`、`update_installer{,_io,_stub}.dart`）；`MultipartFile.fromPath` 全改 `fromBytes` + `XFile.readAsBytes`（Web 端 XFile.path 是 blob: URL）；Web 端 API 地址取 `Uri.base` origin（同源无 CORS），移动端用 `AppConfig.serverUrl`；Web 端 `kIsWeb` 静默跳过通知/APP 内更新；桌面端 `_WebFrame`（main.dart）居中限宽 480px

## 8. 踩坑经验（高频陷阱）

| 陷阱 | 正确做法 |
|---|---|
| Django `FileField`：`instance.image.delete(save=False)` 会**连物理文件删除**；`FieldFile.delete()` 会置空实例内存字段 | 换文件顺序：**先 `old.delete(save=False)` 再赋新值并 `save()`**；删记录前确认无同名新文件 |
| Django test Client 默认不校验 CSRF，纯 API 新增 POST 视图漏加 `@csrf_exempt` 后测试通过、真实请求 403 | 新增可 POST 的视图必须加 `@csrf_exempt`，并用真实 HTTP（requests 打 runserver）双验证 |
| 「点按钮无反应」类 bug 头号嫌疑：必填空输入**静默 return**（无报错无请求无 UI 变化） | 必填为空时绝不静默 return，用 `errorText` 标红输入框；hint 加「例如：」前缀 |
| Flutter Web release 中文串编译为 `\uXXXX` 转义，grep 原生中文查不到 | 验证部署用 MD5 对比 `main.dart.js` |
| flutter timezone 默认 UTC，通知晚 8 小时 | `initializeTimeZones()` 后 `tz.setLocalLocation(tz.getLocation('Asia/Shanghai'))` |
| `CachedNetworkImage` 用 `errorBuilder` 编译错误 | 参数名是 **`errorWidget`** |
| 上传 500：media 目录属主 root:root，gunicorn（foodmap 用户）无写权限 | `chown -R foodmap:foodmap` 两环境 media 目录 |
| 好句配图重复 | `quotes.py` 每类关键词扩到 4-7 个；`cover_image.py` per_page 3→30 + exclude 集合重试（近 14 天图不重复）；fallback 随机历史图而非最新 |
| 微信 WKWebView 中 AlertDialog + 键盘布局风险 | 长文案输入改独立页面路由（MaterialPageRoute） |
| Flutter Web FloatingActionButton 在部分浏览器点击事件不可靠 | 关键新增操作放 AppBar actions（IconButton），如心愿清单页 |
| Web 发版后用户看不到新功能：① nginx 只给 index.html 配了 no-cache，`main.dart.js`/`flutter_service_worker.js` 无缓存头被启发式缓存 + Service Worker 缓存旧 JS；② **部分上传**（只传了 main.dart.js 没传 flutter_service_worker.js），SW 版本清单不变，客户端永远拿不到新资源 | `/etc/nginx/conf.d/foodmap.conf` 已加 `location ~* ^/web/.+\.(js\|json)$` no-cache（2026-09-12，备份 .bak-20260912175107）；**Web 发版必须全量上传 build/web**，并校验 index.html / flutter_service_worker.js / flutter_bootstrap.js / main.dart.js 四文件 MD5 与本地一致；排查先对比 MD5，再查 Cache-Control |

## 9. 重要决策记录

- **iOS 原生暂缓**（2026-09）：Mac+Xcode 门槛、TestFlight 需 688 元/年 Apple 开发者账号、ATS 禁明文 HTTP。**Web 版已作为零成本替代上线**（iPhone Safari 添加到主屏幕，`apple-mobile-web-app-capable` 已配）。若重启 iOS，需适配三处：通知 iOS 分支（DarwinInitializationSettings）、APP 内更新降级、ATS 例外
- **中餐菜谱数据源 = 美食天下 meishichina.com**（弃用 HowToCook：图片存 Git LFS 且图文匹配差）：服务端渲染可直接爬，`/mofang/` 聚合页 396 个，详情页含成品大图（`i3r.meishitx.com` OSS p800）、结构化食材与步骤。结论在其页面结构改版前有效
- **APP 内更新**：后端配置键下发版本信息（`app_version_name`/`app_apk_arm64` 等），`MainActivity.kt` MethodChannel 实现 installApk（FileProvider）+ getAbi，比较 versionName 触发下载安装
- **服务器全站 HTTP 明文**：无 certbot、无 SSL 证书，nginx 仅监听 80

---

*本文件由项目维护者从 Qoder 项目记忆整理导出（2026-09-12），不含任何密码、token 与个人敏感信息。*
