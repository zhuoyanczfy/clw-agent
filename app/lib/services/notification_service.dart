import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../config/app_config.dart';
import 'dish_service.dart';

/// 提醒设置（与 shared_preferences 持久化对应）
class ReminderSettings {
  final bool waterEnabled;
  final List<TimeOfDayLike> waterTimes; // 喝水提醒时间点（最多 3 个）
  final bool nightEnabled;
  final TimeOfDayLike nightTime; // 晚安提醒
  final bool dishEnabled;
  final TimeOfDayLike dishTime; // 每日美食推荐提醒

  const ReminderSettings({
    this.waterEnabled = true,
    this.waterTimes = const [],
    this.nightEnabled = true,
    this.nightTime = const TimeOfDayLike(hour: 22, minute: 30),
    this.dishEnabled = true,
    this.dishTime = const TimeOfDayLike(hour: 12, minute: 0),
  });

  ReminderSettings copyWith({
    bool? waterEnabled,
    List<TimeOfDayLike>? waterTimes,
    bool? nightEnabled,
    TimeOfDayLike? nightTime,
    bool? dishEnabled,
    TimeOfDayLike? dishTime,
  }) {
    return ReminderSettings(
      waterEnabled: waterEnabled ?? this.waterEnabled,
      waterTimes: waterTimes ?? this.waterTimes,
      nightEnabled: nightEnabled ?? this.nightEnabled,
      nightTime: nightTime ?? this.nightTime,
      dishEnabled: dishEnabled ?? this.dishEnabled,
      dishTime: dishTime ?? this.dishTime,
    );
  }
}

/// 简单的时间描述（避免依赖 intl 的 TimeOfDay 序列化）
class TimeOfDayLike {
  final int hour;
  final int minute;
  const TimeOfDayLike({required this.hour, required this.minute});

  String get label => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String encode() => '$hour:$minute';

  static TimeOfDayLike decode(String s) {
    final parts = s.split(':');
    return TimeOfDayLike(
      hour: int.tryParse(parts[0]) ?? 12,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }
}

/// 定时通知服务：每天定时推送喝水、晚安、美食推荐提醒。
/// 使用 flutter_local_notifications 的原生定时调度，
/// 关闭 APP 也能收到通知（Android 系统级调度）。
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _waterBaseId = 100;
  static const int _nightId = 200;
  static const int _dishId = 300;

  static const _channelId = 'daily_reminders';
  static const _channelName = '每日关怀提醒';

  /// 初始化插件、时区并请求权限
  static Future<void> init() async {
    tzdata.initializeTimeZones();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    // Android 13+ 需要运行时通知权限
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    // Android 12+ 精确闹钟权限（保证准时提醒）
    await android?.requestExactAlarmsPermission();
  }

  /// 按当前设置调度所有提醒（先取消旧的，再重新排）
  static Future<void> scheduleAll() async {
    final settings = await loadSettings();
    await _plugin.cancelAll();

    if (settings.waterEnabled) {
      for (var i = 0; i < settings.waterTimes.length; i++) {
        final t = settings.waterTimes[i];
        await _scheduleDaily(
          id: _waterBaseId + i,
          title: '亲爱的，该喝水啦～',
          body: '喝一口温水，今天也要水润润的 ${AppConfig.herName}',
          hour: t.hour,
          minute: t.minute,
        );
      }
    }

    if (settings.nightEnabled) {
      await _scheduleDaily(
        id: _nightId,
        title: '夜深了，早点休息',
        body: '晚安，好梦。明天见，${AppConfig.herName}',
        hour: settings.nightTime.hour,
        minute: settings.nightTime.minute,
      );
    }

    if (settings.dishEnabled) {
      String body = '点开看看今天想带你吃什么';
      try {
        final dish = await DishService.getTodayDish();
        body = '今天想带你吃「${dish.name}」，点开看看';
      } catch (_) {
        // 文案用默认即可
      }
      await _scheduleDaily(
        id: _dishId,
        title: '今日美食推荐',
        body: body,
        hour: settings.dishTime.hour,
        minute: settings.dishTime.minute,
      );
    }
  }

  /// 每天固定时间重复调度
  static Future<void> _scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: '每日定时关怀提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // 每天重复
    );
  }

  // ---------- 设置持久化 ----------

  static const _kWaterEnabled = 'water_enabled';
  static const _kWaterTimes = 'water_times';
  static const _kNightEnabled = 'night_enabled';
  static const _kNightTime = 'night_time';
  static const _kDishEnabled = 'dish_enabled';
  static const _kDishTime = 'dish_time';

  static const defaultWaterTimes = [
    TimeOfDayLike(hour: 10, minute: 0),
    TimeOfDayLike(hour: 14, minute: 0),
    TimeOfDayLike(hour: 17, minute: 0),
  ];

  /// 读取设置（首次使用返回默认值：喝水 10/14/17 点，晚安 22:30，美食 12:00）
  static Future<ReminderSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final waterTimesStr = prefs.getString(_kWaterTimes);
    return ReminderSettings(
      waterEnabled: prefs.getBool(_kWaterEnabled) ?? true,
      waterTimes: waterTimesStr == null
          ? defaultWaterTimes
          : waterTimesStr
              .split(',')
              .where((s) => s.isNotEmpty)
              .map(TimeOfDayLike.decode)
              .toList(),
      nightEnabled: prefs.getBool(_kNightEnabled) ?? true,
      nightTime: TimeOfDayLike.decode(prefs.getString(_kNightTime) ?? '22:30'),
      dishEnabled: prefs.getBool(_kDishEnabled) ?? true,
      dishTime: TimeOfDayLike.decode(prefs.getString(_kDishTime) ?? '12:00'),
    );
  }

  static Future<void> saveSettings(ReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWaterEnabled, settings.waterEnabled);
    await prefs.setString(
        _kWaterTimes, settings.waterTimes.map((t) => t.encode()).join(','));
    await prefs.setBool(_kNightEnabled, settings.nightEnabled);
    await prefs.setString(_kNightTime, settings.nightTime.encode());
    await prefs.setBool(_kDishEnabled, settings.dishEnabled);
    await prefs.setString(_kDishTime, settings.dishTime.encode());
  }
}
