/// Web 实现：Web 版由浏览器刷新自动拿到最新代码，不存在 APK 下载安装。
/// 正常不会被调用（Web 端 AppUpdater.checkForUpdate 直接返回 null）。
Future<String> downloadUpdate(
  String url, {
  void Function(double progress)? onProgress,
}) async {
  throw UnsupportedError('Web 版无需下载安装，刷新页面即可更新');
}

Future<void> installUpdate(String path) async {}
