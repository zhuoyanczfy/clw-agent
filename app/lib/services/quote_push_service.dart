import 'dart:math';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/quote.dart';
import 'foodmap_api.dart';

/// 好句推送服务：每日随机时间点推送（6:00~22:00），每天1~3次。
/// 使用本地通知定时调度，到点自动弹出，无需打开 APP。
class QuotePushService {
  QuotePushService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'quote_push';
  static const _channelName = '好句推送';
  static const _scheduledKey = 'quote_scheduled_times';

  /// 调度今日随机推送：在 6:00~22:00 之间随机选 1~3 个时间点。
  /// 每天启动时调用一次，已排过期的自动清理。
  /// 注意：通知为单次推送（不带每日重复），内容每天由启动时的重新调度更新；
  /// 若某天未打开 APP 则不推送，避免弹出旧句子。
  static Future<void> scheduleToday() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // 清理昨天的调度记录
    final lastScheduled = prefs.getString(_scheduledKey) ?? '';
    if (lastScheduled.isNotEmpty && lastScheduled != today) {
      // 取消所有旧通知（通过 ID 范围）
      for (var id = 600; id < 610; id++) {
        await _plugin.cancel(id);
      }
    }

    // 今天已调度过则跳过
    if (lastScheduled == today) return;

    // 今日好句只拉一次（当天内容恒定），失败则本次不排
    Quote quote;
    try {
      quote = await FoodmapApi.fetchTodayQuote();
    } catch (_) {
      return;
    }

    // 随机决定今天推几次：1~3 次
    final pushCount = 1 + Random().nextInt(3);
    final now = DateTime.now();
    var scheduledCount = 0;

    for (var i = 0; i < pushCount; i++) {
      // 随机时间：7:30 ~ 22:00
      final hour = 7 + Random().nextInt(15);
      final minute = Random().nextInt(60);
      var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
      // 7 点档只保留 30 分及以后（即 >= 7:30）
      if (hour == 7 && minute < 30) {
        scheduled = scheduled.add(const Duration(minutes: 30));
      }

      // 如果今天的时间已过，推到明天
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      // 拉取今日好句（到点弹的内容固定为当日缓存）
      try {
        await _scheduleNotification(
          id: 600 + i,
          title: '📖 今日好句 · ${quote.author}',
          body: quote.text,
          scheduled: scheduled,
        );
        scheduledCount++;
      } catch (_) {
        // 调度失败则跳过本次
      }
    }

    if (scheduledCount > 0) {
      await prefs.setString(_scheduledKey, today);
    }
  }

  static Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduled,
  }) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduled, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: '每日好句好段推送',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
}
