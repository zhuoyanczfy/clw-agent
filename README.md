# 专属美食关怀 APP

为她定制的安卓 APP：每天推送一道美食推荐 + 定时提醒喝水、吃美食、早点睡。
首页显示她的昵称、你们认识的天数、专属欢迎语——一眼就能看出是专门为她做的。

## 功能一览

- 首页：专属问候（昵称 + 认识天数 + 今日美食卡片）
- 美食：每日一道美食推荐（40 道菜全菜系，含专属文案和做法），可收藏想吃的菜
- 提醒：喝水提醒（默认 10:00 / 14:00 / 17:00）、美食推荐提醒（默认 12:00）、晚安提醒（默认 22:30），全部可自定义时间和开关
- 提醒为系统级定时通知：关闭 APP 也能收到，手机重启后自动恢复

## 目录结构

```
clw_agent/
├── app/                     # Flutter APP（打包成安卓 APK）
│   ├── lib/
│   │   ├── config/app_config.dart   # ★ 专属信息配置（送人前改这里）
│   │   ├── data/dishes.dart         # 内置 40 道美食（断网可用）
│   │   ├── services/                # 美食服务 + 定时通知服务
│   │   └── pages/                   # 首页 / 美食 / 设置
│   └── android/             # 安卓工程（应用名「专属美食关怀」）
├── server/                  # Python FastAPI 后端（可选增强）
│   ├── main.py              # API：/api/dish/today 每日推荐
│   ├── dishes.py            # 美食库数据（与 APP 内置一致）
│   └── requirements.txt
└── README.md
```

## 送给她之前：修改专属信息（只需 1 个文件）

打开 `app/lib/config/app_config.dart`，改三个地方：

```dart
static const String herName = '小仙女';     // ← 改成她的昵称
static const String meetDate = '2026-01-01'; // ← 改成你们认识的日期
static const String serverUrl = '';          // ← 部署后端后填地址，留空用内置美食库
```

改完后重新打包（见下）。

## 打包 APK（在她安卓手机上安装）

### 首次准备环境（已在本机完成，无需重复）

- Flutter 3.44.9（`D:\flutter`）、JDK 17（`D:\jdk17`）、Android SDK（`D:\android-sdk`）
- 国内镜像已配置：Flutter 存储、pub、Gradle、Maven 均走国内源

### 重新打包命令

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

- 通知权限若被拒绝，可去手机设置 → 应用 → 专属美食关怀 → 通知 中重新开启
- 部分手机（小米/华为等）有「自启动管理」，若收不到提醒，将 APP 加入允许自启动名单即可

## 后端部署（可选，部署后可在服务器端更新美食内容）

不部署后端完全不影响使用（APP 内置 40 道菜按日期轮换，与后端算法一致）。

需要部署时：

```powershell
cd D:\code\clw_agent\server
pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8000
```

本地验证：`http://127.0.0.1:8000/api/dish/today`（交互文档 `/docs`）

部署到公网（可选免费方案：Railway / Render / PythonAnywhere）后，把公网地址填入 `app_config.dart` 的 `serverUrl` 并重新打包。

## 日常更新美食内容

- 只改后端：编辑 `server/dishes.py` 添加新菜，重启服务即可，APP 无需重装
- 改 APP 内置库：编辑 `server/dishes.py` 后运行 `python server/gen_dishes_dart.py` 重新生成 `app/lib/data/dishes.dart`，再重新打包
