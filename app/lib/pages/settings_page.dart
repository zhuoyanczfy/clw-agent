import 'package:flutter/material.dart';

import '../services/api_config.dart';
import '../services/foodmap_api.dart';
import '../services/notification_service.dart';
import '../theme.dart';

/// 设置页：后端服务地址 + 每日关怀提醒（喝水 / 晚安 / 美食推荐）
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ReminderSettings? _settings;
  bool _saving = false;

  // 后端服务地址
  final _serverCtrl = TextEditingController();
  String _savedServerUrl = '';
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _load();
    _loadServerUrl();
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadServerUrl() async {
    final url = await ApiConfig.getBaseUrl();
    if (!mounted) return;
    setState(() {
      _savedServerUrl = url;
      _serverCtrl.text = url;
    });
  }

  Future<void> _saveServer() async {
    final url = _serverCtrl.text.trim();
    await ApiConfig.saveBaseUrl(url);
    if (!mounted) return;
    setState(() {
      _savedServerUrl = url.replaceAll(RegExp(r'/$'), '');
      _testResult = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('后端地址已保存'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _testServer() async {
    final url = _serverCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _testResult = '请先填写地址');
      return;
    }
    await ApiConfig.saveBaseUrl(url);
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final ok = await FoodmapApi.health();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = ok ? '✅ 连接成功，后端服务正常' : '❌ 无法连接，请检查地址与网络';
    });
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

                    // ---- 后端服务 ----
                    _sectionHeader('🌐', '后端服务', '美食足迹的数据来源'),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _serverCtrl,
                              keyboardType: TextInputType.url,
                              decoration: const InputDecoration(
                                labelText: '后端地址',
                                hintText: 'http://192.168.1.100:8000',
                                helperText: '电脑与手机需在同一网络；部署公网后填域名',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_testResult != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  _testResult!,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _testing ? null : _testServer,
                                    child: _testing
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Text('测试连接'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: _saveServer,
                                    child: const Text('保存地址'),
                                  ),
                                ),
                              ],
                            ),
                            if (_savedServerUrl.isEmpty) ...[
                              const SizedBox(height: 8),
                              const Text(
                                '未配置时，每日美食使用内置库；足迹/记录/推荐官需要后端',
                                style: TextStyle(
                                    fontSize: 11, color: AppTheme.textLight),
                              ),
                            ],
                          ],
                        ),
                      ),
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
