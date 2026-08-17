# 光旅之盘 · Compass of Light & Wanderlust（clw-agent）

为她定制的一套美食系礼物：

- **📱 安卓 APP**（`app/`）：每天推送一道美食推荐 + 定时提醒喝水、吃美食、早点睡，首页显示她的昵称、认识天数与专属欢迎语；内置「美食足迹」（南京分区地图、用餐记录、待尝清单、AI 美食推荐官）+ 三个陪伴模块：宠物名片、每日塔罗占卜（韦特塔罗套图 + 三张牌阵 + DeepSeek 解读）、好句好段
- **🍜 Django API 后端**（`backend/`）：美食足迹的数据中枢——南京真实餐厅库、用餐记录、待尝清单、AI 推荐官（DeepSeek 多轮对话）、宠物名片、每日占卜（三张牌时间之流牌阵 + DeepSeek 解读）、好句好段（hitokoto + Unsplash 配图）全部由后端提供，APP 通过 HTTP 接口调用获取数据

APP 内置 40 道美食库，不连后端也能独立使用；配置后端地址后，每日推荐、足迹地图、记录、待尝、推荐官全部走后端数据。

## 目录结构

```
clw_agent/
├── app/                     # Flutter APP（打包成安卓 APK）
│   ├── lib/
│   │   ├── config/app_config.dart   # ★ 专属信息配置（送人前改这里）
│   │   ├── data/dishes.dart         # 内置 40 道美食（断网可用，与后端算法一致）
│   │   ├── models/                  # 区 / 餐厅 / 记录 / 待尝 / 宠物 / 占卜 / 好句 / 天气 数据模型
│   │   ├── services/                # Django API 客户端 + 通知/好句推送服务 + 后端地址配置
│   │   └── pages/                   # 首页 / 美食 / 足迹 / 推荐官 / 宠物 / 占卜 / 好句 / 设置
│   └── android/             # 安卓工程（应用名「光旅之盘」）
└── backend/                 # Django 4.2 纯 API 后端（南京美食足迹数据中枢）
    ├── config/              # Django 配置 + config.ini（DeepSeek/高德/Unsplash Key，勿提交）
    ├── foodmap/             # 业务应用：区 / 餐厅 / 记录 / 待尝 / 宠物 / 占卜 / 好句 / AI 推荐官（纯 REST API）
    ├── deploy/              # 生产部署脚本（Nginx + Gunicorn）
    └── requirements.txt
```

---

## 📱 一、安卓 APP（光旅之盘）

### 送给她之前：修改专属信息（只需 1 个文件）

打开 `app/lib/config/app_config.dart`，改三个地方：

```dart
static const String herName = '小仙女';     // ← 改成她的昵称
static const String meetDate = '2026-01-01'; // ← 改成你们认识的日期
static const String serverUrl = '';          // ← 部署后端后填地址，留空用内置美食库
```

改完后重新打包（见下）。

### 打包 APK（在她安卓手机上安装）

```powershell
$env:JAVA_HOME = "D:\jdk17\jdk-17.0.20+8"
cd D:\code\clw_agent\app
flutter build apk --release
```

打包产物：`app\build\app\outputs\flutter-apk\app-release.apk`

### 安装到她手机

1. 把 `app-release.apk` 发给她（微信/QQ/数据线均可）
2. 她在手机上打开 APK，按提示允许安装（设置 → 允许安装未知来源应用）
3. 首次打开会请求「通知权限」和「闹钟与提醒权限」，**全部允许**，提醒才能准时送达
4. 打开后默认提醒已开启，可在「设置」页调整时间

### 温馨提示

- 通知权限若被拒绝，可去手机设置 → 应用 → 光旅之盘 → 通知 中重新开启
- 部分手机（小米/华为等）有「自启动管理」，若收不到提醒，将 APP 加入允许自启动名单即可

---

## 🍜 二、Django API 后端（美食足迹数据中枢）

完整 API 文档与开发说明见 [`backend/README.md`](backend/README.md)，快速启动：

```powershell
cd D:\code\clw_agent\backend
py -3.10 -m venv .venv          # 首次
.\.venv\Scripts\activate
pip install -r requirements.txt  # 首次
python manage.py migrate         # 首次（本机已有 db.sqlite3 含历史回忆数据，可直接用）
python manage.py runserver 0.0.0.0:8000
```

- API Key 配置在 `backend/config/config.ini`（DeepSeek / 高德 / Unsplash），**该文件不入库**，模板见 `config.ini.example`
- 健康检查：`http://127.0.0.1:8000/api/health/`

### 主要 API

| 接口 | 说明 |
| --- | --- |
| `GET /api/dish/today/` | 今日美食推荐（按日期轮换，与 APP 内置算法一致） |
| `GET /api/districts/` | 南京 11 区（含餐厅数/足迹数） |
| `GET /api/districts.geojson` | 区划 GeoJSON（APP 地图分区高亮） |
| `GET /api/restaurants/` | 餐厅列表（支持 `?district=` 过滤、`?visited=1` 只看去过） |
| `GET/POST /api/records/` | 用餐记录列表 / 新建（支持直接新建餐厅） |
| `GET/PUT/DELETE /api/records/<id>/` | 记录详情 / 修改 / 删除 |
| `POST /api/records/<id>/photos/` | 上传用餐照片（multipart） |
| `GET/POST /api/wishlist/` | 待尝清单 |
| `POST /api/wishlist/<id>/eaten/` | 标记已尝 |
| `POST /api/recommend/chat/` | AI 推荐官（SSE 流式多轮对话） |
| `POST /api/recommend/verify/` | 推荐卡片真实性校验（高德兜底） |
| `GET /api/splash/` | 当日加载页图片（同一天固定一张、相邻两天不重复） |
| `POST /api/splash/upload/` | 上传加载页图片（需 `X-Upload-Token`，multipart） |
| `GET /api/config/` | APP 云端配置（首页文案/昵称/认识日期 + 提醒文案/时间/开关，Admin 改后无需重打包） |
| `GET /api/weather/` | 天气预报（高德代理，首页天气条与天气关怀提醒） |
| `GET/POST /api/pets/` | 宠物名片（信息/照片/成长事件） |
| `GET /api/divination/today/` | 每日塔罗占卜（三张牌阵「时间之流」+ 韦特塔罗套图 + DeepSeek 解读，按日期缓存） |
| `GET /api/quotes/today/` | 今日好句（hitokoto 文学/哲学 + Pixabay 配图，按日期缓存） |
| `GET /api/quotes/history/` | 历史好句列表（倒序 30 条） |
| `GET /api/quotes/random/` | 再来一条（实时拉取，不缓存） |

### 让 APP 走后端（局域网）

1. 电脑跑起 Django（`runserver 0.0.0.0:8000`），手机连同一 WiFi
2. APP「设置」页 → 后端服务 → 填 `http://<电脑局域网IP>:8000` → 测试连接 → 保存地址
3. 返回足迹页刷新，即可加载地图 / 餐厅 / 记录；推荐官、待尝清单同源

> 部署到公网（Railway / Render / 内网穿透）后，把公网地址填到「设置」页即可，APP 无需重新打包。

---

## 最近更新

### v1.2 — 塔罗占卜升级 & 美食页优化

- **每日塔罗占卜**：升级为经典「时间之流」三张牌阵（过去-现在-未来），使用韦特塔罗 22 张大阿卡纳真实套图（公有领域），逆位牌自动旋转 180° 倒置展示
- **美食页**：今日推荐图片宽高各缩为原来的一半，居中展示
- **AI 推荐官**：新增餐厅详情页、聊天历史回看、推荐餐厅一站式收藏
- **用餐记录**：新增 rating 评分校验（1-5 分，超范围自动拒绝）、编辑记录时自动回填已选餐厅
- **时区修复**：所有 `date.today()` 统一为 `timezone.localdate()`，避免跨时区日期偏差
- **塔罗牌图片**：22 张韦特塔罗大阿卡纳套图部署于 `/media/tarot/`，双环境同步

---

## 日常更新美食内容

- 改后端菜库：编辑 `backend/foodmap/dishes_full.py` 后执行 `python manage.py seed_dishes`，重启服务即可，APP 无需重装
- 改 APP 内置库：编辑 `backend/foodmap/dishes_full.py` 后执行 `py -3.10 tmp/gen_dishes_dart.py` 重新生成 `app/lib/data/dishes.dart`，再重新打包
