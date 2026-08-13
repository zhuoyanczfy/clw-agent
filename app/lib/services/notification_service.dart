import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/pet.dart';
import 'dish_service.dart';
import 'remote_config.dart';

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

  /// 已调度提醒的宠物事项 id（重新调度时用于取消被删除/改期的事项）
  static final Set<int> _scheduledPetEventIds = <int>{};

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
