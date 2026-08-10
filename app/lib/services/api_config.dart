import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// 后端 API 地址管理：默认取 [AppConfig.serverUrl]，运行后可在设置页
/// 修改并持久化到本机（覆盖默认值），无需重新打包。
class ApiConfig {
  static const _key = 'api_server_url';

  /// 当前生效的后端地址（去掉末尾斜杠），空串表示未配置
  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_key) ?? AppConfig.serverUrl).replaceAll(RegExp(r'/$'), '');
  }

  /// 保存后端地址（设置页调用）
  static Future<void> saveBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, url.trim());
  }
}
