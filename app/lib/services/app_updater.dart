import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'remote_config.dart';

/// 一次可用的新版本信息
class UpdateInfo {
  final String versionName;
  final String note;
  final String apkUrl;
  const UpdateInfo({
    required this.versionName,
    required this.note,
    required this.apkUrl,
  });
}

/// APP 内更新服务：版本检查 → 下载 APK（带进度）→ 触发系统安装器。
///
/// 版本号约定：按 versionName（如 1.0.1）逐段比较大小。
/// 注意不能比较 versionCode：分架构包（--split-per-abi）的 versionCode 会带
/// ABI 前缀（如 x86_64=4002、arm64=2002），各架构不一致，无法统一比较。
/// 云端最新版由 RemoteConfig.appVersionName 提供（后台配置/默认值）。
class AppUpdater {
  AppUpdater._();

  static const _channel = MethodChannel('com.gift.dailycare/updater');

  /// 检查是否有新版本；无新版本或未配置时返回 null。
  static Future<UpdateInfo?> checkForUpdate() async {
    final cloudName = RemoteConfig.appVersionName;
    if (cloudName.isEmpty) return null; // 未配置版本信息
    final info = await PackageInfo.fromPlatform();
    if (!_isNewer(cloudName, info.version)) return null;
    return UpdateInfo(
      versionName: cloudName,
      note: RemoteConfig.appUpdateNote,
      apkUrl: RemoteConfig.appApkUrl(await getAbi()),
    );
  }

  /// cloud > local 时为 true（逐段比较 x.y.z，允许 z 缺失）
  static bool _isNewer(String cloud, String local) {
    final a = cloud.split('.').map(int.tryParse).toList();
    final b = local.split('.').map(int.tryParse).toList();
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final x = i < a.length ? (a[i] ?? 0) : 0;
      final y = i < b.length ? (b[i] ?? 0) : 0;
      if (x != y) return x > y;
    }
    return false; // 完全相等
  }

  /// 设备 CPU 架构（原生通道获取，失败回退 arm64-v8a）
  static Future<String> getAbi() async {
    try {
      return await _channel.invokeMethod<String>('getAbi') ?? 'arm64-v8a';
    } catch (_) {
      return 'arm64-v8a';
    }
  }

  /// 下载 APK 到应用缓存目录 updates/（与 FileProvider 的 cache-path 对应），
  /// 返回本地文件路径；[onProgress] 回调 0.0~1.0。
  static Future<String> download(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final updatesDir = Directory('${tempDir.path}/updates');
    if (!updatesDir.existsSync()) updatesDir.createSync(recursive: true);
    final file = File('${updatesDir.path}/app-update.apk');
    if (file.existsSync()) file.deleteSync(); // 覆盖旧包，避免版本降级

    final request = http.Request('GET', Uri.parse(url));
    final response = await request.send().timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('下载失败（HTTP ${response.statusCode}）');
    }
    final total = response.contentLength ?? 0;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (file.lengthSync() == 0) {
      file.deleteSync();
      throw Exception('下载失败：文件为空');
    }
    return file.path;
  }

  /// 触发系统安装器安装 APK（用户需在系统弹窗确认）
  static Future<void> install(String path) async {
    await _channel.invokeMethod('installApk', {'path': path});
  }
}
