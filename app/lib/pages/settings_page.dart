import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/api_config.dart';
import '../services/foodmap_api.dart';
import '../services/player_role.dart';
import '../theme.dart';
import '../widgets/cute_widgets.dart';
import 'reminder_settings_page.dart';
import 'secret_notes_page.dart';

/// 设置页：后端服务地址 + 每日关怀提醒入口。
/// 提醒的开关/时间/文案可在 APP 内配置（本地优先生效，可恢复后台默认）。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // 后端服务地址
  final _serverCtrl = TextEditingController();
  String _savedServerUrl = '';
  bool _testing = false;
  String? _testResult;
  // 版本号（底部页脚展示）
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
    _loadVersion();
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

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = info.version);
    } catch (_) {}
  }

  void _openSecretNotes() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SecretNotesPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '设置',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '后端服务与每日关怀提醒配置',
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
                          labelText: '后端地址（高级）',
                          hintText: 'http://139.196.27.224',
                          helperText: '已默认连接云端服务器，一般无需修改；换服务器时才需要改这里',
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

              // ---- 每日关怀提醒（APP 内可配置） ----
              _sectionHeader('⏰', '每日关怀提醒', '开关 / 时间 / 文案'),
              const SizedBox(height: 12),
              Card(
                child: SquishyTap(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ReminderSettingsPage(),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Text('💧', style: TextStyle(fontSize: 22)),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '喝水 · 晚安 · 美食推荐',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textDark,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '点这里调整开关、提醒时间和通知文案',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: AppTheme.textLight),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ---- 双人游戏身份（每日一问 / 二选一 / 你画我猜按此落答案） ----
              _sectionHeader('🎮', '这台设备是谁的', '双人游戏按此区分双方'),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Android APP 默认是「她」，网页版默认是「他」；换设备玩时在这里切换',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textLight,
                            height: 1.6),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildRoleChoice(
                                role: PlayerRole.her,
                                title: '她',
                                icon: Icons.female),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildRoleChoice(
                                role: PlayerRole.him,
                                title: '他',
                                icon: Icons.male),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 44),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _appVersion.isEmpty ? '光旅之盘' : '光旅之盘 v$_appVersion',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textLight.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _EasterEggStar(onOpen: _openSecretNotes),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 身份选择按钮（♀她 / ♂他，选中态高亮） ----
  Widget _buildRoleChoice({
    required String role,
    required String title,
    required IconData icon,
  }) {
    final selected = PlayerRole.current == role;
    return SquishyTap(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _switchRole(role, title),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF3D6) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.primary : const Color(0x14000000),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? AppTheme.primary : AppTheme.textLight,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? AppTheme.primaryDark : AppTheme.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchRole(String role, String title) async {
    if (PlayerRole.current == role) return;
    await PlayerRole.set(role);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('这台设备将以「$title」的身份参与双人游戏'),
        duration: const Duration(seconds: 2),
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
}

/// 设置页彩蛋入口：伪装成版本号旁的装饰小星，点击闪一下再进入星语页。
/// 刻意保持无 tooltip、无按钮涟漪——看起来只是一枚装饰符号。
class _EasterEggStar extends StatefulWidget {
  const _EasterEggStar({required this.onOpen});

  final VoidCallback onOpen;

  @override
  State<_EasterEggStar> createState() => _EasterEggStarState();
}

class _EasterEggStarState extends State<_EasterEggStar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _tap() {
    if (_ctrl.isAnimating) return;
    _ctrl.forward(from: 0); // 星星闪一下，与页面转场并行
    widget.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _tap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final glow = math.sin(_ctrl.value * math.pi); // 0 → 1 → 0
          return Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              Icons.star_rounded,
              size: 13 + glow * 4,
              color: Color.lerp(
                AppTheme.textLight.withValues(alpha: 0.6),
                AppTheme.primary,
                glow,
              ),
              shadows: [
                Shadow(
                  color: AppTheme.primary.withValues(alpha: 0.9 * glow),
                  blurRadius: 12 * glow,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
