import 'package:flutter/material.dart';

import '../services/api_config.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';

/// 设置页：后端服务地址。
/// 提醒文案 / 时间 / 开关由后台（Django Admin → /api/config/）统一配置，
/// App 内不开放手动修改。
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

  @override
  void initState() {
    super.initState();
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
                '每日关怀提醒由后台统一配置，无需在手机端设置',
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

              // ---- 每日关怀提醒（后台配置说明） ----
              _sectionHeader('⏰', '每日关怀提醒', '由后台统一配置'),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '喝水、晚安、美食推荐提醒的文案 / 时间 / 开关',
                        style: TextStyle(fontSize: 14, height: 1.6),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '请在后台管理（Django Admin）的「APP配置」中修改，'
                        'App 启动时会自动拉取最新配置并生效，无需重新安装',
                        style:
                            TextStyle(fontSize: 12, color: AppTheme.textLight, height: 1.6),
                      ),
                    ],
                  ),
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
}
