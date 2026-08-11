# Compass of Love & Wanderlust 🎁

送给她的礼物 APP（Flutter 客户端）：专属问候、认识天数、每日美食推荐、足迹地图、AI 推荐官、随机加载页、故事书。

后端（Django API）见 [backend/](../backend/README.md)，接口与数据由后端提供。

## 环境要求

- Flutter SDK 3.x（含 Dart）
- JDK 17（Android 工具链需要）
- Android SDK（`flutter doctor` 全部通过即可）

## 一、专属信息配置（送人前必改）

所有专属信息集中在 [lib/config/app_config.dart](lib/config/app_config.dart)：

| 配置项 | 说明 |
| --- | --- |
| `herName` | 她的昵称（显示在首页顶部和欢迎语） |
| `meetDate` | 你们认识的日期（格式 YYYY-MM-DD），首页自动计算「认识天数」 |
| `greeting` | 首页专属欢迎语 |
| `serverUrl` | 后端 API 地址（默认空 = 纯本地模式；填了才启用加载页/故事书/云端数据） |
| `dailyDishTitle` | 今日美食卡片的文案前缀 |

> 后端地址也可以在 APP「设置」页随时修改并保存，无需重新打包。

## 二、构建 APK

```powershell
cd app
flutter pub get          # 安装依赖
flutter build apk --release
```

产物位置：`build\app\outputs\flutter-apk\app-release.apk`（约 55MB）。

## 三、安装到手机

**方式一：USB 调试安装**

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

**方式二：直接拷贝** APK 文件到手机（微信/QQ/数据线均可），点击安装（需允许「安装未知来源应用」）。

## 四、连接后端（加载页 / 故事书 / 云端数据）

1. 电脑上启动后端：`cd backend; .\.venv\Scripts\python.exe manage.py runserver 0.0.0.0:8000`
2. 手机连**同一 WiFi**，查看电脑局域网 IP：`ipconfig`（IPv4 地址）
3. APP「设置」页 → 后端服务 → 填 `http://<电脑局域网IP>:8000` → 测试连接 → 保存
4. 重启 APP，即可看到每日随机加载页；首页「故事书」卡片进入故事列表

> 不在同一网络：用内网穿透（cpolar / frp 等）或部署到公网服务器（见 backend/deploy/），把公网地址填进设置页即可，APP 无需重新打包。

## 五、内容运营

加载页图片、历史故事通过后端命令行工具上传（详见 [backend/README.md](../backend/README.md)）：

```powershell
cd backend
python upload.py splash 图片.png "标题"                          # 加载页图片
python upload.py story "标题" 正文.txt --category 历史故事        # 故事
```

也可直接登录 Django Admin（http://127.0.0.1:8000/admin）管理。

## 六、常见问题

- **APP 停在加载页很久**：后端未启动或地址不对，加载页 5 秒超时会自动进入主界面
- **安装失败（签名冲突）**：先卸载旧版本再安装
- **打包报错**：`flutter doctor` 检查环境；JDK 版本需 17
- **想回退纯本地模式**：设置页清空后端地址即可（今日美食等内置功能不依赖后端）
