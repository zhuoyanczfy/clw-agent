import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/dish.dart';
import '../services/dish_service.dart';
import '../services/remote_config.dart';
import '../theme.dart';
import '../widgets/cute_widgets.dart';
import 'dish_page.dart';

/// 首页：专属问候 + 认识天数 + 今日美食卡片 + 提醒状态（文案由后台配置）
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Dish? _todayDish;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dish = await DishService.getTodayDish();
    if (!mounted) return;
    setState(() => _todayDish = dish);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGreeting(),
                const SizedBox(height: 20),
                _buildDaysCard(),
                const SizedBox(height: 20),
                _buildTodayDishCard(),
                const SizedBox(height: 20),
                _buildReminderCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- 顶部专属问候 ----
  Widget _buildGreeting() {
    final hour = DateTime.now().hour;
    final greeting = hour < 6
        ? '夜深了'
        : hour < 11
        ? '早上好'
        : hour < 14
        ? '中午好'
        : hour < 18
        ? '下午好'
        : '晚上好';
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final now = DateTime.now();
    final dateStr = '${now.month}月${now.day}日 · 星期${weekdays[now.weekday - 1]}';
    return BouncyIn(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting，${RemoteConfig.herName}',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${RemoteConfig.greeting} · $dateStr',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textLight,
                  ),
                ),
              ],
            ),
          ),
          HeartBeat(
            maxScale: 1.15,
            duration: const Duration(milliseconds: 1000),
            child: const _HeartBadge(),
          ),
        ],
      ),
    );
  }

  // ---- 认识天数卡片 ----
  Widget _buildDaysCard() {
    final meet = DateTime.tryParse(RemoteConfig.meetDate) ?? DateTime.now();
    final days = DateTime.now().difference(meet).inDays + 1;
    return BouncyIn(
      offsetY: 20,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primary, AppTheme.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '我们认识的第 $days 天',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '从 ${RemoteConfig.meetDate} 认识你，每一天都值得纪念',
              style: const TextStyle(fontSize: 13, color: Color(0xFFFFF1F1)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _daysItem(days, '相识天数'),
                const SizedBox(width: 16),
                _daysItem(days ~/ 7, '相识周数'),
                const SizedBox(width: 16),
                _daysItem(days ~/ 30, '相识月数'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _daysItem(int value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            BouncyNumber(
              value: value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFFFFF1F1)),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 今日美食卡片 ----
  Widget _buildTodayDishCard() {
    final dish = _todayDish;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '今日美食',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: dish == null ? null : () => _openDish(dish),
              child: const Text(
                '查看详情 ›',
                style: TextStyle(fontSize: 13, color: AppTheme.primaryDark),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (dish == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else
          BouncyIn(
            offsetY: 28,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: SquishyTap(
                onTap: () => _openDish(dish),
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: CachedNetworkImage(
                            imageUrl: dish.imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Container(
                              color: const Color(0xFFFFE9E9),
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            errorWidget: (_, _, _) => Container(
                              color: const Color(0xFFFFE9E9),
                              child: const Center(
                                child: HeartBeat(
                                  maxScale: 1.1,
                                  child: Text(
                                    '🫕',
                                    style: TextStyle(fontSize: 48),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 12,
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              dish.category,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            RemoteConfig.dailyDishTitle,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.primaryDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dish.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openDish(Dish dish) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => DishPage(dish: dish)));
  }

  // ---- 提醒状态卡片（状态由后台配置） ----
  Widget _buildReminderCard() {
    final waterOn = RemoteConfig.waterEnabled;
    final nightOn = RemoteConfig.nightEnabled;
    final dishOn = RemoteConfig.dishEnabled;
    final onCount = [waterOn, nightOn, dishOn].where((b) => b).length;
    return BouncyIn(
      offsetY: 20,
      delay: const Duration(milliseconds: 300),
      child: Card(
        child: SquishyTap(
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('每日提醒由后台统一配置，无需在手机端设置'),
              duration: Duration(seconds: 2),
            ),
          ),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0E3),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text('⏰', style: TextStyle(fontSize: 22)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '每日关怀提醒',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '喝水 · 晚安 · 美食推荐，$onCount 项已开启',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.textLight),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 临时占位（设置页由 main.dart 底部导航承载时直接跳转 Tab）
class _HeartBadge extends StatelessWidget {
  const _HeartBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primary, AppTheme.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Center(child: Text('❤️', style: TextStyle(fontSize: 22))),
    );
  }
}
