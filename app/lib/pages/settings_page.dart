import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../theme.dart';

/// 设置页：每日关怀提醒（喝水 / 晚安 / 美食推荐）的时间与开关
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ReminderSettings? _settings;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await NotificationService.loadSettings();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  Future<void> _save() async {
    final settings = _settings;
    if (settings == null) return;
    setState(() => _saving = true);
    await NotificationService.saveSettings(settings);
    await NotificationService.scheduleAll();
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('提醒已更新，她会准时收到哒'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _pickTime({
    required TimeOfDayLike current,
    required void Function(TimeOfDayLike) onChanged,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppTheme.primary,
            primary: AppTheme.primaryDark,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    onChanged(TimeOfDayLike(hour: picked.hour, minute: picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      body: SafeArea(
        child: settings == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '每日关怀提醒',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '按时提醒她喝水、吃美食、早点睡',
                      style: TextStyle(fontSize: 13, color: AppTheme.textLight),
                    ),
                    const SizedBox(height: 20),

                    // ---- 喝水提醒 ----
                    _sectionHeader('💧', '喝水提醒', '一天 3 次，提醒她补水'),
                    const SizedBox(height: 12),
                    Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < settings.waterTimes.length; i++)
                            _timeTile(
                              label: '第 ${i + 1} 次喝水',
                              icon: '🚰',
                              time: settings.waterTimes[i],
                              enabled: settings.waterEnabled,
                              onTap: settings.waterEnabled
                                  ? () => _pickTime(
                                        current: settings.waterTimes[i],
                                        onChanged: (t) => setState(() {
                                          final times =
                                              List<TimeOfDayLike>.from(
                                                  settings.waterTimes);
                                          times[i] = t;
                                          _settings = settings
                                              .copyWith(waterTimes: times);
                                        }),
                                      )
                                  : null,
                            ),
                          SwitchListTile(
                            value: settings.waterEnabled,
                            onChanged: (v) => setState(
                                () => _settings = settings.copyWith(waterEnabled: v)),
                            title: const Text('开启喝水提醒',
                                style: TextStyle(fontSize: 14)),
                            activeThumbColor: AppTheme.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ---- 美食推荐提醒 ----
                    _sectionHeader('🍜', '美食推荐', '每天中午推送今日美食'),
                    const SizedBox(height: 12),
                    Card(
                      child: Column(
                        children: [
                          _timeTile(
                            label: '每日美食推荐',
                            icon: '🥢',
                            time: settings.dishTime,
                            enabled: settings.dishEnabled,
                            onTap: settings.dishEnabled
                                ? () => _pickTime(
                                      current: settings.dishTime,
                                      onChanged: (t) => setState(() => _settings =
                                          settings.copyWith(dishTime: t)),
                                    )
                                : null,
                          ),
                          SwitchListTile(
                            value: settings.dishEnabled,
                            onChanged: (v) => setState(
                                () => _settings = settings.copyWith(dishEnabled: v)),
                            title: const Text('开启美食推荐提醒',
                                style: TextStyle(fontSize: 14)),
                            activeThumbColor: AppTheme.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ---- 晚安提醒 ----
                    _sectionHeader('🌙', '晚安提醒', '提醒她早点休息'),
                    const SizedBox(height: 12),
                    Card(
                      child: Column(
                        children: [
                          _timeTile(
                            label: '晚安时间',
                            icon: '🌙',
                            time: settings.nightTime,
                            enabled: settings.nightEnabled,
                            onTap: settings.nightEnabled
                                ? () => _pickTime(
                                      current: settings.nightTime,
                                      onChanged: (t) => setState(() => _settings =
                                          settings.copyWith(nightTime: t)),
                                    )
                                : null,
                          ),
                          SwitchListTile(
                            value: settings.nightEnabled,
                            onChanged: (v) => setState(
                                () => _settings = settings.copyWith(nightEnabled: v)),
                            title: const Text('开启晚安提醒',
                                style: TextStyle(fontSize: 14)),
                            activeThumbColor: AppTheme.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('保存提醒设置'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Center(
                      child: Text(
                        '提醒在手机系统层面生效，关闭 App 也能收到',
                        style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _sectionHeader(String emoji, String title, String subtitle) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
        ),
      ],
    );
  }

  Widget _timeTile({
    required String label,
    required String icon,
    required TimeOfDayLike time,
    required bool enabled,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Text(icon, style: const TextStyle(fontSize: 18)),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFFFE9E9) : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          time.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: enabled ? AppTheme.primaryDark : AppTheme.textLight,
          ),
        ),
      ),
      onTap: onTap,
      enabled: enabled,
    );
  }
}
