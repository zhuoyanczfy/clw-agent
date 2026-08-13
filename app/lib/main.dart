import 'package:flutter/material.dart';

import 'pages/ai_recommend_page.dart';
import 'pages/food_page.dart';
import 'pages/footprint_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/splash_page.dart';
import 'services/foodmap_api.dart';
import 'services/notification_service.dart';
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
      title: 'Compass of Love & Wanderlust',
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

  /// 启动时拉取云端配置并按配置调度每日提醒（容错，失败用本地默认值）
  Future<void> _bootstrap() async {
    try {
      await RemoteConfig.load();
    } catch (_) {
      // 配置拉取失败用本地默认值
    }
    try {
      await NotificationService.scheduleAll();
    } catch (_) {
      // 通知调度失败不影响使用
    }
    try {
      // 宠物疫苗/驱虫到期提醒（云端无数据时跳过）
      final pets = await FoodmapApi.fetchPets();
      for (final pet in pets) {
        final events = await FoodmapApi.fetchPetEvents(pet.id);
        await NotificationService.schedulePetReminders(events);
      }
    } catch (_) {
      // 宠物提醒调度失败不影响使用
    }
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
        indicatorColor: const Color(0xFFFFE9E9),
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
