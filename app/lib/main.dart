import 'package:flutter/material.dart';

import 'pages/food_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'services/notification_service.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化通知插件与权限，并调度每日提醒
  await NotificationService.init();
  await NotificationService.scheduleAll();
  runApp(const GiftingApp());
}

class GiftingApp extends StatelessWidget {
  const GiftingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '专属美食关怀',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const MainShell(),
    );
  }
}

/// 主框架：底部导航（首页 / 美食 / 设置）
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
          HomePage(
            onOpenSettings: () => setState(() => _index = 2),
          ),
          const FoodPage(),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFFFE9E9),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: AppTheme.primaryDark),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu, color: AppTheme.primaryDark),
            label: '美食',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: AppTheme.primaryDark),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
