import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

/// APP 内更新服务：版本检查（下载安装拆在 update_installer，仅移动端可用）。
///
/// 版本号约定：按 versionName（如 1.0.1）逐段比较大小。
/// 注意不能比较 versionCode：分架构包（--split-per-abi）的 versionCode 会带
/// ABI 前缀（如 x86_64=4002、arm64=2002），各架构不一致，无法统一比较。
/// 云端最新版由 RemoteConfig.appVersionName 提供（后台配置/默认值）。
class AppUpdater {
  AppUpdater._();

  static const _channel = MethodChannel('com.gift.dailycare/updater');

  /// 检查是否有新版本；无新版本或未配置时返回 null。
  /// Web 版无需 APP 内更新：浏览器刷新即拿到最新代码，直接返回 null。
  static Future<UpdateInfo?> checkForUpdate() async {
    if (kIsWeb) return null;
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
}
