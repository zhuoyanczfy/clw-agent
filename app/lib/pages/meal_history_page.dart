import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/dish_service.dart';
import '../theme.dart';
import '../widgets/cute_widgets.dart';
import 'dish_page.dart';

/// 历史每日菜单：后端按日期缓存的每日推荐，按日期倒序展示。
class MealHistoryPage extends StatefulWidget {
  const MealHistoryPage({super.key});

  @override
  State<MealHistoryPage> createState() => _MealHistoryPageState();
}

class _MealHistoryPageState extends State<MealHistoryPage> {
  List<MealRecord> _records = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await DishService.fetchMealHistory();
      if (!mounted) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('每日菜单历史'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(child: Text('加载失败：$_error', style: const TextStyle(color: AppTheme.textLight))),
        ],
      );
    }
    if (_records.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                Text('🍳', style: TextStyle(fontSize: 48)),
                SizedBox(height: 12),
                Text('还没有历史菜单', style: TextStyle(color: AppTheme.textLight)),
                SizedBox(height: 4),
                Text(
                  '打开首页「今日美食」后，每天会自动记录一道',
                  style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _records.length,
      itemBuilder: (context, i) {
        final record = _records[i];
        final dish = record.dish;
        return BouncyIn(
          offsetY: 12,
          child: Card(
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.only(bottom: 14),
            child: SquishyTap(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => DishPage(dish: dish)),
                );
              },
              borderRadius: BorderRadius.circular(18),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    height: 92,
                    child: CachedNetworkImage(
                      imageUrl: dish.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        color: const Color(0xFFFFF3D6),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      errorWidget: (_, _, _) => Container(
                        color: const Color(0xFFFFF3D6),
                        child: const Center(
                          child: Text('🫕', style: TextStyle(fontSize: 28)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.date,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dish.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dish.category,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(Icons.chevron_right, color: AppTheme.textLight),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
