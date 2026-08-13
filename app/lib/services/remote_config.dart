import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'foodmap_api.dart';

/// 简单的时间描述（避免依赖 intl 的 TimeOfDay 序列化）
class TimeOfDayLike {
  final int hour;
  final int minute;
  const TimeOfDayLike({required this.hour, required this.minute});

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  static TimeOfDayLike parse(String s) {
    final parts = s.split(':');
    return TimeOfDayLike(
      hour: int.tryParse(parts[0]) ?? 12,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }
}

/// 云端配置服务：启动时从后端拉取配置（键值对），未配置后端或拉取失败时
/// 回退 [AppConfig] 本地默认值。
///
/// 提醒类的开关/时间/文案支持 APP 内自定义（见 [setOverride]）：
/// 优先级为 本地用户覆盖 > 云端配置 > 内置默认值；
/// 未改过的项仍跟随云端（后台可统一改默认），改过可一键恢复。
class RemoteConfig {
  RemoteConfig._();

  static const _cacheKey = 'remote_config_cache';
  static const _overridesKey = 'reminder_overrides';

  /// 本地用户覆盖值（APP 设置页改过的键），优先级最高
  static Map<String, String> _overrides = const {};

  // 配置键（与 backend/foodmap/views.py 的 APP_CONFIG_DEFAULTS 对齐）
  static const kHerName = 'her_name';
  static const kMeetDate = 'meet_date';
  static const kGreeting = 'greeting';
  static const kDailyDishTitle = 'daily_dish_title';
  static const kWaterTitle = 'water_title';
  static const kWaterBody = 'water_body';
  static const kNightTitle = 'night_title';
  static const kNightBody = 'night_body';
  static const kDishTitle = 'dish_title';
  static const kDishBody = 'dish_body';
  static const kWaterTimes = 'water_times';
  static const kNightTime = 'night_time';
  static const kDishTime = 'dish_time';
  static const kWaterEnabled = 'water_enabled';
  static const kNightEnabled = 'night_enabled';
  static const kDishEnabled = 'dish_enabled';

  static Map<String, String> _values = const {};
  static bool _loaded = false;

  /// 是否成功拉取过云端配置（拉取失败但命中本机缓存也算）
  static bool get isLoaded => _loaded;

  /// 启动时调用：拉取云端配置（5 秒超时容错），成功后缓存到本机；
  /// 失败时尝试读上次缓存，都没有则使用本地默认值。
  /// 本地用户覆盖（设置页改过的提醒配置）一并加载。
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_overridesKey);
      if (raw != null && raw.isNotEmpty) {
        _overrides = (jsonDecode(raw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v?.toString() ?? ''));
      }
    } catch (_) {}
    try {
      final values = await FoodmapApi.fetchConfig()
          .timeout(const Duration(seconds: 5));
      _values = values;
      _loaded = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, jsonEncode(values));
      } catch (_) {}
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString(_cacheKey);
        if (cached != null && cached.isNotEmpty) {
          _values =
              (jsonDecode(cached) as Map<String, dynamic>).map(
                  (k, v) => MapEntry(k, v?.toString() ?? ''));
          _loaded = true;
        }
      } catch (_) {}
    }
  }

  // ---------- 本地用户覆盖（APP 设置页） ----------

  /// 某配置键是否被用户在 APP 内改过（改过则不再跟随云端）
  static bool hasOverride(String key) => _overrides.containsKey(key);

  /// 保存一项用户覆盖并立即生效（内存），持久化到本机
  static Future<void> setOverride(String key, String value) async {
    _overrides = {..._overrides, key: value};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_overridesKey, jsonEncode(_overrides));
    } catch (_) {}
  }

  /// 清除全部用户覆盖，恢复跟随云端/默认值
  static Future<void> resetOverrides() async {
    _overrides = const {};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_overridesKey);
    } catch (_) {}
  }

  // ---------- 通用读取 ----------

  /// 取字符串配置；本地覆盖 > 云端 > [fallback] / 本地默认
  static String get(String key, {String? fallback}) {
    final o = _overrides[key];
    if (o != null) return o;
    final v = _values[key];
    if (v != null && v.isNotEmpty) return v;
    return fallback ?? _localDefault(key);
  }

  static String _localDefault(String key) {
    switch (key) {
      case kHerName:
        return AppConfig.herName;
      case kMeetDate:
        return AppConfig.meetDate;
      case kGreeting:
        return AppConfig.greeting;
      case kDailyDishTitle:
        return AppConfig.dailyDishTitle;
      default:
        return '';
    }
  }

  /// 布尔配置（"1"/"true" 视为开）
  static bool getBool(String key, {bool fallback = false}) {
    final v = get(key, fallback: fallback ? '1' : '0').toLowerCase();
    return v == '1' || v == 'true';
  }

  /// 时间配置（如 "22:30"）
  static TimeOfDayLike getTime(String key, {TimeOfDayLike? fallback}) {
    final s = get(key);
    if (s.isEmpty) return fallback ?? const TimeOfDayLike(hour: 12, minute: 0);
    return TimeOfDayLike.parse(s);
  }

  /// 时间点列表配置（如 "10:00,14:00,17:00"）
  static List<TimeOfDayLike> getTimes(String key,
      {List<TimeOfDayLike>? fallback}) {
    final s = get(key);
    final parts = s.split(',').where((p) => p.trim().isNotEmpty).toList();
    if (parts.isEmpty) return fallback ?? const [];
    return parts.map(TimeOfDayLike.parse).toList();
  }

  /// 模板替换：{herName} / {dishName} 占位符
  static String format(String template, {String dishName = ''}) => template
      .replaceAll('{herName}', herName)
      .replaceAll('{dishName}', dishName);

  // ---------- 常用配置便捷属性 ----------

  static String get herName => get(kHerName, fallback: AppConfig.herName);
  static String get meetDate => get(kMeetDate, fallback: AppConfig.meetDate);
  static String get greeting => get(kGreeting, fallback: AppConfig.greeting);
  static String get dailyDishTitle =>
      get(kDailyDishTitle, fallback: AppConfig.dailyDishTitle);

  // 通知文案
  static String get waterTitle => get(kWaterTitle, fallback: '亲爱的，该喝水啦～');
  static String get waterBody =>
      get(kWaterBody, fallback: '喝一口温水，今天也要水润润的 $herName');
  static String get nightTitle => get(kNightTitle, fallback: '夜深了，早点休息');
  static String get nightBody =>
      get(kNightBody, fallback: '晚安，好梦。明天见，$herName');
  static String get dishTitle => get(kDishTitle, fallback: '今日美食推荐');
  static String get dishBody =>
      get(kDishBody, fallback: '今天想带你吃「$dailyDishTitle」，点开看看');

  // 通知时间与开关（本地默认与后端默认一致）
  static const defaultWaterTimes = [
    TimeOfDayLike(hour: 10, minute: 0),
    TimeOfDayLike(hour: 14, minute: 0),
    TimeOfDayLike(hour: 17, minute: 0),
  ];

  static List<TimeOfDayLike> get waterTimes =>
      getTimes(kWaterTimes, fallback: defaultWaterTimes);
  static TimeOfDayLike get nightTime =>
      getTime(kNightTime, fallback: const TimeOfDayLike(hour: 22, minute: 30));
  static TimeOfDayLike get dishTime =>
      getTime(kDishTime, fallback: const TimeOfDayLike(hour: 12, minute: 0));
  static bool get waterEnabled => getBool(kWaterEnabled, fallback: true);
  static bool get nightEnabled => getBool(kNightEnabled, fallback: true);
  static bool get dishEnabled => getBool(kDishEnabled, fallback: true);
}
