import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/pet.dart';
import '../models/weather.dart';
import 'dish_service.dart';
import 'foodmap_api.dart';
import 'remote_config.dart';
import 'weather_service.dart';

/// 定时通知服务：每天定时推送喝水、晚安、美食推荐提醒。
/// 使用 flutter_local_notifications 的原生定时调度，
/// 关闭 APP 也能收到通知（Android 系统级调度）。
/// 文案 / 时间 / 开关全部由后台配置（RemoteConfig），APP 内不可手动修改。
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _waterBaseId = 100;
  static const int _nightId = 200;
  static const int _dishId = 300;
  static const int _petBaseId = 400;
  static const int _weatherId = 500;

  /// 已调度提醒的宠物事项 id（重新调度时用于取消被删除/改期的事项）
  static final Set<int> _scheduledPetEventIds = <int>{};

  static const _channelId = 'daily_reminders';
  static const _channelName = '每日关怀提醒';

  /// 初始化插件、时区并请求权限
  static Future<void> init() async {
    tzdata.initializeTimeZones();
    // 必须显式指定本地时区：默认 UTC 会导致所有定时提醒比设定时间晚 8 小时触发
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
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

  /// 按云端配置调度所有提醒（先取消旧的，再重新排）
  static Future<void> scheduleAll() async {
    await _plugin.cancelAll();

    if (RemoteConfig.waterEnabled) {
      for (var i = 0; i < RemoteConfig.waterTimes.length; i++) {
        final t = RemoteConfig.waterTimes[i];
        await _scheduleDaily(
          id: _waterBaseId + i,
          title: RemoteConfig.waterTitle,
          body: RemoteConfig.format(RemoteConfig.waterBody),
          hour: t.hour,
          minute: t.minute,
        );
      }
    }

    if (RemoteConfig.nightEnabled) {
      await _scheduleDaily(
        id: _nightId,
        title: RemoteConfig.nightTitle,
        body: RemoteConfig.format(RemoteConfig.nightBody),
        hour: RemoteConfig.nightTime.hour,
        minute: RemoteConfig.nightTime.minute,
      );
    }

    if (RemoteConfig.dishEnabled) {
      String body = RemoteConfig.format(RemoteConfig.dishBody);
      try {
        final dish = await DishService.getTodayDish();
        body = RemoteConfig.format(RemoteConfig.dishBody, dishName: dish.name);
      } catch (_) {
        // 文案用默认即可
      }
      await _scheduleDaily(
        id: _dishId,
        title: RemoteConfig.dishTitle,
        body: body,
        hour: RemoteConfig.dishTime.hour,
        minute: RemoteConfig.dishTime.minute,
      );
    }

    if (RemoteConfig.weatherEnabled) {
      await _scheduleWeather();
    }
  }

  /// 天气关怀提醒：拉取天气，明天有雨或降温（≥5°）才排明早的通知；
  /// 条件不满足或拉取失败则不排（下次启动/改设置时重新评估）。
  static Future<void> _scheduleWeather() async {
    try {
      final weather = await WeatherService.fetchWeather();
      final t = weather.tomorrow;
      if (t == null) return;
      final rainy =
          WeatherLive.isRainy(t.dayWeather) || WeatherLive.isRainy(t.nightWeather);
      final todayTemp = double.tryParse(weather.live.temperature) ?? 0;
      final tomorrowTemp = double.tryParse(t.dayTemp) ?? todayTemp;
      final cold = todayTemp - tomorrowTemp >= 5;
      if (!rainy && !cold) return;
      String body;
      if (rainy && cold) {
        body = '${RemoteConfig.format(RemoteConfig.weatherRainBody, dayWeather: t.dayWeather)} '
            '${RemoteConfig.format(RemoteConfig.weatherColdBody, dayTemp: t.dayTemp)}';
      } else if (rainy) {
        body = RemoteConfig.format(RemoteConfig.weatherRainBody,
            dayWeather: t.dayWeather);
      } else {
        body = RemoteConfig.format(RemoteConfig.weatherColdBody,
            dayTemp: t.dayTemp);
      }
      await _scheduleDaily(
        id: _weatherId,
        title: RemoteConfig.weatherTitle,
        body: body,
        hour: RemoteConfig.weatherTime.hour,
        minute: RemoteConfig.weatherTime.minute,
      );
    } catch (_) {
      // 天气拉取失败：本次不排天气提醒
    }
  }

  /// 调度宠物疫苗/驱虫到期提醒：到期前 7 天上午 10 点单次通知。
  /// 会取消已删除事项的旧提醒；到期日已过或未设到期时间的不调度。
  static Future<void> schedulePetReminders(List<PetEvent> events) async {
    final now = tz.TZDateTime.now(tz.local);
    final active = <int>{};
    for (final e in events) {
      if (e.kind != PetEvent.kindVaccine && e.kind != PetEvent.kindDeworm) {
        continue;
      }
      final due = DateTime.tryParse(e.dueDate);
      if (due == null) continue;
      final remindAt = tz.TZDateTime(
        tz.local,
        due.year,
        due.month,
        due.day,
        10,
      ).subtract(const Duration(days: 7));
      if (!remindAt.isAfter(now)) continue;
      active.add(e.id);
      await _plugin.zonedSchedule(
        _petBaseId + e.id,
        '🐾 猫咪健康提醒',
        '${e.title} 还有 7 天到期（${e.dueDate}），记得带猫咪预约哦',
        remindAt,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: '每日定时关怀提醒',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
    // 取消已不存在（被删除或改了到期时间）的旧提醒
    for (final id in _scheduledPetEventIds.difference(active)) {
      await _plugin.cancel(_petBaseId + id);
    }
    _scheduledPetEventIds
      ..clear()
      ..addAll(active);
  }

  /// 重排全部提醒：每日提醒 + 宠物疫苗/驱虫到期提醒。
  /// 设置页改动提醒配置后调用；宠物数据拉取失败不影响每日提醒。
  static Future<void> rescheduleAll() async {
    await scheduleAll();
    try {
      final pets = await FoodmapApi.fetchPets();
      for (final pet in pets) {
        final events = await FoodmapApi.fetchPetEvents(pet.id);
        await schedulePetReminders(events);
      }
    } catch (_) {
      // 宠物提醒拉取失败不影响每日提醒
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
}
