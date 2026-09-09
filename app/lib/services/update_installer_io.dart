import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 下载 APK 到应用缓存目录 updates/（与 FileProvider 的 cache-path 对应），
/// 返回本地文件路径；[onProgress] 回调 0.0~1.0。
Future<String> downloadUpdate(
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
Future<void> installUpdate(String path) async {
  const channel = MethodChannel('com.gift.dailycare/updater');
  await channel.invokeMethod('installApk', {'path': path});
}
