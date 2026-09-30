import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// 当前设备角色：双人小游戏按角色落答案（每日一问/二选一的答案、画猜的画者）。
///
/// - her：她（Android APP 默认，即收礼人）
/// - him：送礼人（Web 版默认——他用自己的 iPhone Safari 打开 Web 版参与）
///
/// 角色存本机 SharedPreferences（每台设备各自记一次），设置页可切换；
/// 所有 API 请求自动带 X-Api-Role 头，后端据此区分（不带时后端默认 her）。
class PlayerRole {
  PlayerRole._();

  static const _prefsKey = 'player_role';
  static const her = 'her';
  static const him = 'him';

  static String _role = her;

  /// 当前角色（main 启动时 load 后即同步可读，兜底 her）
  static String get current => _role;

  static bool get isHer => _role == her;

  /// 启动时调用：读本机记录的角色；首次使用按平台给默认值（APP=her / Web=him）。
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null && (saved == her || saved == him)) {
        _role = saved;
        return;
      }
      _role = kIsWeb ? him : her;
    } catch (_) {
      _role = kIsWeb ? him : her;
    }
  }

  /// 切换角色（设置页「这台设备是谁的」），立即生效并持久化。
  static Future<void> set(String role) async {
    _role = (role == him) ? him : her;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _role);
    } catch (_) {}
  }
}
