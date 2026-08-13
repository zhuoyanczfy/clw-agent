import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dish.dart';
import '../services/dish_service.dart';
import '../services/remote_config.dart';
import '../theme.dart';
import 'dish_page.dart';

/// 美食页：今日推荐 + 我收藏的美食
class FoodPage extends StatefulWidget {
  const FoodPage({super.key});

  @override
  State<FoodPage> createState() => _FoodPageState();
}

class _FoodPageState extends State<FoodPage> {
  Dish? _todayDish;
  final List<Dish> _favorites = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dish = await DishService.getTodayDish();
    final all = await DishService.fetchDishes();
    final ids = await _loadFavoriteIds();
    // 收藏列表从完整菜库匹配（云端优先，离线时用内置库）
    final favDishes = <Dish>[];
    for (final id in ids) {
      final match = all.where((d) => d.id == id);
      if (match.isNotEmpty) favDishes.add(match.first);
    }
    if (!mounted) return;
    setState(() {
      _todayDish = dish;
      _favorites
        ..clear()
        ..addAll(favDishes);
    });
  }

  Future<List<String>> _loadFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('favorite_dish_ids') ?? []);
  }

  Future<void> _toggleFavorite(Dish dish) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList('favorite_dish_ids') ?? []).toList();
    if (ids.contains(dish.id)) {
      ids.remove(dish.id);
    } else {
      ids.add(dish.id);
    }
    await prefs.setStringList('favorite_dish_ids', ids);
    await _load();
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
                '今日美食',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${RemoteConfig.dailyDishTitle}一道好菜，每天都有小惊喜',
                style: const TextStyle(fontSize: 13, color: AppTheme.textLight),
              ),
              const SizedBox(height: 16),
              if (_todayDish == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else
                _buildTodayCard(_todayDish!),
              const SizedBox(height: 28),
              const Text(
                '我收藏的美食',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 12),
              if (_favorites.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        '还没有收藏～在美食详情页点 ♥ 收藏\n以后想吃的都记在这里',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textLight, height: 1.6),
                      ),
                    ),
                  ),
                )
              else
                ..._favorites.map(_buildFavoriteItem),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTodayCard(Dish dish) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDish(dish),
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
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (_, _, _) => Container(
                      color: const Color(0xFFFFE9E9),
                      child: const Center(
                          child: Text('🫕', style: TextStyle(fontSize: 48))),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      dish.category,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
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
                        fontSize: 13, color: AppTheme.primaryDark),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          dish.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _toggleFavorite(dish),
                        icon: Icon(
                          _favorites.any((d) => d.id == dish.id)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteItem(Dish dish) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openDish(dish),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: CachedNetworkImage(
                    imageUrl: dish.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      color: const Color(0xFFFFE9E9),
                      child: const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (_, _, _) => Container(
                      color: const Color(0xFFFFE9E9),
                      child: const Center(
                          child: Text('🍽️', style: TextStyle(fontSize: 24))),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dish.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dish.description.length > 30
                          ? '${dish.description.substring(0, 30)}…'
                          : dish.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textLight),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _toggleFavorite(dish),
                icon: const Icon(Icons.favorite, color: AppTheme.primaryDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDish(Dish dish) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DishPage(dish: dish)),
    );
  }
}
