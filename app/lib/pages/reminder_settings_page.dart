import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../services/remote_config.dart';
import '../theme.dart';
import '../widgets/cute_widgets.dart';

/// 每日关怀提醒配置页：喝水 / 晚安 / 美食推荐的开关、时间与文案。
/// 改动立即生效并重排通知；「恢复后台默认」清空所有本地自定义。
class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({super.key});

  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage> {
  late bool _waterEnabled;
  late bool _nightEnabled;
  late bool _dishEnabled;
  late List<TimeOfDayLike> _waterTimes;
  late TimeOfDayLike _nightTime;
  late TimeOfDayLike _dishTime;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _waterEnabled = RemoteConfig.waterEnabled;
    _nightEnabled = RemoteConfig.nightEnabled;
    _dishEnabled = RemoteConfig.dishEnabled;
    _waterTimes = List.of(RemoteConfig.waterTimes);
    _nightTime = RemoteConfig.nightTime;
    _dishTime = RemoteConfig.dishTime;
  }

  /// 保存一项配置并重排通知（容错，失败只提示不阻断）
  Future<void> _apply(String key, String value) async {
    await RemoteConfig.setOverride(key, value);
    try {
      await NotificationService.rescheduleAll();
    } catch (_) {
      // 通知重排失败不影响配置保存
    }
  }

  Future<void> _toggleWater(bool on) async {
    setState(() {
      _waterEnabled = on;
      _busy = true;
    });
    await _apply(RemoteConfig.kWaterEnabled, on ? '1' : '0');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggleNight(bool on) async {
    setState(() {
      _nightEnabled = on;
      _busy = true;
    });
    await _apply(RemoteConfig.kNightEnabled, on ? '1' : '0');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggleDish(bool on) async {
    setState(() {
      _dishEnabled = on;
      _busy = true;
    });
    await _apply(RemoteConfig.kDishEnabled, on ? '1' : '0');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickTime(TimeOfDayLike current, ValueChanged<TimeOfDayLike> onPicked) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;
    onPicked(
      TimeOfDayLike(hour: picked.hour, minute: picked.minute),
    );
  }

  Future<void> _editWaterTime(int index) async {
    await _pickTime(_waterTimes[index], (t) async {
      setState(() => _waterTimes[index] = t);
      await _apply(
        RemoteConfig.kWaterTimes,
        _waterTimes.map((e) => e.label).join(','),
      );
    });
  }

  Future<void> _addWaterTime() async {
    if (_waterTimes.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多设置 4 个喝水时间～')),
      );
      return;
    }
    await _pickTime(
      const TimeOfDayLike(hour: 10, minute: 0),
      (t) async {
        setState(() => _waterTimes.add(t));
        await _apply(
          RemoteConfig.kWaterTimes,
          _waterTimes.map((e) => e.label).join(','),
        );
      },
    );
  }

  Future<void> _removeWaterTime(int index) async {
    setState(() => _waterTimes.removeAt(index));
    await _apply(
      RemoteConfig.kWaterTimes,
      _waterTimes.map((e) => e.label).join(','),
    );
  }

  Future<void> _editNightTime() async {
    await _pickTime(_nightTime, (t) async {
      setState(() => _nightTime = t);
      await _apply(RemoteConfig.kNightTime, t.label);
    });
  }

  Future<void> _editDishTime() async {
    await _pickTime(_dishTime, (t) async {
      setState(() => _dishTime = t);
      await _apply(RemoteConfig.kDishTime, t.label);
    });
  }

  Future<void> _editCopy({
    required String emoji,
    required String title,
    required String titleKey,
    required String bodyKey,
  }) async {
    final titleCtrl = TextEditingController(
      text: RemoteConfig.get(titleKey, fallback: ''),
    );
    final bodyCtrl = TextEditingController(
      text: RemoteConfig.get(bodyKey, fallback: ''),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$emoji 编辑$title文案'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              maxLength: 20,
              decoration: const InputDecoration(
                labelText: '通知标题',
                hintText: '比如：亲爱的，该喝水啦～',
                isDense: true,
              ),
            ),
            TextField(
              controller: bodyCtrl,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: '通知内容',
                hintText: '支持 {herName} 占位符（她的昵称）',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存', style: TextStyle(color: AppTheme.primaryDark)),
          ),
        ],
      ),
    );
    if (saved != true) return;
    await _apply(titleKey, titleCtrl.text.trim());
    await _apply(bodyKey, bodyCtrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('文案已更新'), duration: Duration(seconds: 2)));
  }

  Future<void> _resetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复后台默认设置？'),
        content: const Text('你在 APP 里改过的开关、时间和文案都会还原为后台配置的默认值。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复默认', style: TextStyle(color: AppTheme.primaryDark)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await RemoteConfig.resetOverrides();
    if (!mounted) return;
    setState(_reload);
    try {
      await NotificationService.rescheduleAll();
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已恢复后台默认设置'), duration: Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final hasOverride = RemoteConfig.hasOverride(RemoteConfig.kWaterEnabled) ||
        RemoteConfig.hasOverride(RemoteConfig.kNightEnabled) ||
        RemoteConfig.hasOverride(RemoteConfig.kDishEnabled) ||
        RemoteConfig.hasOverride(RemoteConfig.kWaterTimes) ||
        RemoteConfig.hasOverride(RemoteConfig.kNightTime) ||
        RemoteConfig.hasOverride(RemoteConfig.kDishTime) ||
        RemoteConfig.hasOverride(RemoteConfig.kWaterTitle) ||
        RemoteConfig.hasOverride(RemoteConfig.kWaterBody) ||
        RemoteConfig.hasOverride(RemoteConfig.kNightTitle) ||
        RemoteConfig.hasOverride(RemoteConfig.kNightBody) ||
        RemoteConfig.hasOverride(RemoteConfig.kDishTitle) ||
        RemoteConfig.hasOverride(RemoteConfig.kDishBody);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '每日关怀提醒',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                '随时调整提醒的时间、开关和文案，改完立即生效；\n即使关掉 APP，提醒也会准时送达～',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textLight,
                  height: 1.6,
                ),
              ),
            ),
            _buildWaterCard(),
            const SizedBox(height: 14),
            _buildNightCard(),
            const SizedBox(height: 14),
            _buildDishCard(),
            const SizedBox(height: 20),
            if (hasOverride)
              SquishyTap(
                borderRadius: BorderRadius.circular(16),
                onTap: _busy ? null : _resetAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFD9DF)),
                  ),
                  child: const Center(
                    child: Text(
                      '恢复后台默认设置',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.primaryDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaterCard() {
    return _card(
      emoji: '💧',
      title: '喝水提醒',
      enabled: _waterEnabled,
      onToggle: _toggleWater,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '提醒时间（点击改时间，最多 4 个）',
            style: TextStyle(fontSize: 12, color: AppTheme.textLight),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _waterTimes.length; i++)
                InputChip(
                  label: Text(_waterTimes[i].label),
                  onPressed: _waterEnabled ? () => _editWaterTime(i) : null,
                  onDeleted: _waterEnabled && _waterTimes.length > 1
                      ? () => _removeWaterTime(i)
                      : null,
                  deleteIconColor: AppTheme.textLight,
                ),
              if (_waterTimes.length < 4)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('加一个'),
                  onPressed: _waterEnabled ? _addWaterTime : null,
                ),
            ],
          ),
        ],
      ),
      onEditCopy: () => _editCopy(
        emoji: '💧',
        title: '喝水',
        titleKey: RemoteConfig.kWaterTitle,
        bodyKey: RemoteConfig.kWaterBody,
      ),
    );
  }

  Widget _buildNightCard() {
    return _card(
      emoji: '🌙',
      title: '晚安提醒',
      enabled: _nightEnabled,
      onToggle: _toggleNight,
      trailing: Row(
        children: [
          const Text(
            '提醒时间',
            style: TextStyle(fontSize: 12, color: AppTheme.textLight),
          ),
          const Spacer(),
          ActionChip(
            avatar: const Icon(Icons.schedule, size: 16),
            label: Text(_nightTime.label),
            onPressed: _nightEnabled ? _editNightTime : null,
          ),
        ],
      ),
      onEditCopy: () => _editCopy(
        emoji: '🌙',
        title: '晚安',
        titleKey: RemoteConfig.kNightTitle,
        bodyKey: RemoteConfig.kNightBody,
      ),
    );
  }

  Widget _buildDishCard() {
    return _card(
      emoji: '🍽️',
      title: '美食推荐提醒',
      enabled: _dishEnabled,
      onToggle: _toggleDish,
      trailing: Row(
        children: [
          const Text(
            '提醒时间',
            style: TextStyle(fontSize: 12, color: AppTheme.textLight),
          ),
          const Spacer(),
          ActionChip(
            avatar: const Icon(Icons.schedule, size: 16),
            label: Text(_dishTime.label),
            onPressed: _dishEnabled ? _editDishTime : null,
          ),
        ],
      ),
      onEditCopy: () => _editCopy(
        emoji: '🍽️',
        title: '美食推荐',
        titleKey: RemoteConfig.kDishTitle,
        bodyKey: RemoteConfig.kDishBody,
      ),
    );
  }

  Widget _card({
    required String emoji,
    required String title,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required Widget trailing,
    required VoidCallback onEditCopy,
  }) {
    return BouncyIn(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Text(emoji, style: const TextStyle(fontSize: 24)),
                title: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                subtitle: Text(
                  enabled ? '已开启' : '已关闭',
                  style: TextStyle(
                    fontSize: 12,
                    color: enabled ? const Color(0xFF43A047) : AppTheme.textLight,
                  ),
                ),
                value: enabled,
                onChanged: _busy ? null : onToggle,
                activeThumbColor: AppTheme.primary,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Opacity(opacity: enabled ? 1 : 0.4, child: trailing),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: enabled ? onEditCopy : null,
                child: const Text('编辑通知文案'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

