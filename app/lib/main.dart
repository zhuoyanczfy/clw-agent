import 'package:flutter/material.dart';

import 'pages/ai_recommend_page.dart';
import 'pages/food_page.dart';
import 'pages/footprint_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/splash_page.dart';
import 'services/app_updater.dart';
import 'services/notification_service.dart';
import 'services/quote_push_service.dart';
import 'services/remote_config.dart';
import 'theme.dart';
import 'widgets/cute_widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化通知插件与权限（每日提醒在 _Root 拉到云端配置后再调度）。
  // 通知初始化失败不能影响 APP 启动（如模拟器/低版本系统不支持时）。
  try {
    await NotificationService.init();
  } catch (e) {
    debugPrint('通知初始化失败（不影响启动）: $e');
  }
  runApp(const GiftingApp());
}

class GiftingApp extends StatelessWidget {
  const GiftingApp({super.key, this.showSplash = true});

  /// 是否先展示加载页（测试环境关闭，直接进主框架）
  final bool showSplash;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Compass of Light & Wanderlust',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: showSplash ? const _Root() : const MainShell(),
    );
  }
}

/// 启动入口：先展示加载页（后端每日随机图片），结束后进入主界面。
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// 启动时拉取云端配置并按配置调度全部提醒（容错，失败用本地默认值）
  Future<void> _bootstrap() async {
    try {
      await RemoteConfig.load();
    } catch (_) {
      // 配置拉取失败用本地默认值
    }
    try {
      // 每日关怀提醒 + 宠物疫苗/驱虫到期提醒
      await NotificationService.rescheduleAll();
    } catch (_) {
      // 通知调度失败不影响使用
    }
    // 好句定时推送：每日随机时间点（6:00~22:00）
    try {
      await QuotePushService.scheduleToday();
    } catch (_) {
      // 好句推送调度失败不影响使用
    }
    // APP 内更新检查：云端版本号更高时弹窗提示（自动下载安装）
    _checkForUpdate();
  }

  /// 启动后检查新版本，有更新时弹窗（等加载页结束、主界面出现后再弹）
  Future<void> _checkForUpdate() async {
    var waited = 0;
    while (!_splashDone && waited < 50) {
      await Future.delayed(const Duration(milliseconds: 200));
      waited++;
    }
    if (!mounted) return;
    try {
      final update = await AppUpdater.checkForUpdate();
      if (update == null || !mounted) return;
      await _showUpdateDialog(update);
    } catch (_) {
      // 更新检查失败不影响使用
    }
  }

  /// 更新弹窗：展示版本说明，用户确认后开始下载安装
  Future<void> _showUpdateDialog(UpdateInfo update) async {
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update_alt, color: AppTheme.primaryDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text('发现新版本 v${update.versionName}'),
            ),
          ],
        ),
        content: Text(
          update.note.isEmpty ? '修复问题并优化体验，建议尽快更新～' : update.note,
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadDialog(url: update.apkUrl),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_splashDone) {
      return SplashPage(onFinished: () => setState(() => _splashDone = true));
    }
    return const MainShell();
  }
}

/// 主框架：底部导航（首页 / 美食 / 足迹 / 推荐官 / 设置）
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const HomePage(),
          const FoodPage(),
          const FootprintPage(),
          const AiRecommendPage(),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFFFF3D6),
        destinations: [
          NavigationDestination(
            icon: _navIcon(0, Icons.home_outlined, Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: _navIcon(
              1,
              Icons.restaurant_menu_outlined,
              Icons.restaurant_menu,
            ),
            label: '美食',
          ),
          NavigationDestination(
            icon: _navIcon(2, Icons.map_outlined, Icons.map),
            label: '足迹',
          ),
          NavigationDestination(
            icon: _navIcon(3, Icons.smart_toy_outlined, Icons.smart_toy),
            label: '推荐官',
          ),
          NavigationDestination(
            icon: _navIcon(4, Icons.settings_outlined, Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }

  /// 底部导航图标：选中时弹跳一下（Q 版手感）
  Widget _navIcon(int index, IconData icon, IconData selectedIcon) {
    return BounceNavIcon(
      selected: _index == index,
      icon: Icon(icon),
      selectedIcon: Icon(selectedIcon, color: AppTheme.primaryDark),
    );
  }
}

/// 更新下载进度弹窗：下载完成后自动触发系统安装器
class _DownloadDialog extends StatefulWidget {
  final String url;
  const _DownloadDialog({required this.url});

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  double _progress = 0;
  String _status = '正在下载更新…';
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _progress = 0;
      _status = '正在下载更新…';
      _error = null;
    });
    try {
      final path = await AppUpdater.download(
        widget.url,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            _status = '已下载 ${(p * 100).toStringAsFixed(0)}%';
          });
        },
      );
      if (!mounted) return;
      setState(() => _status = '准备安装…');
      await AppUpdater.install(path);
      if (mounted) Navigator.of(context).pop(); // 安装器接管，关掉弹窗
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _status = '下载失败';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.downloading, color: AppTheme.primaryDark),
          const SizedBox(width: 8),
          const Expanded(child: Text('正在更新')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_status, style: const TextStyle(height: 1.5)),
          const SizedBox(height: 12),
          if (_error == null) ...[
            LinearProgressIndicator(value: _progress, minHeight: 8),
            const SizedBox(height: 8),
            Text(
              '${(_progress * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (_error != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          )
        else
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('后台下载'),
          ),
      ],
    );
  }
}
