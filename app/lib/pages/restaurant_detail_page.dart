import 'package:flutter/material.dart';

import '../models/restaurant.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';
import 'record_form_page.dart';

/// 餐厅详情：基本信息 + 全部用餐记录。
class RestaurantDetailPage extends StatefulWidget {
  final int restaurantId;
  const RestaurantDetailPage({super.key, required this.restaurantId});

  @override
  State<RestaurantDetailPage> createState() => _RestaurantDetailPageState();
}

class _RestaurantDetailPageState extends State<RestaurantDetailPage> {
  Restaurant? _restaurant;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await FoodmapApi.fetchRestaurantDetail(widget.restaurantId);
      if (!mounted) return;
      setState(() => _restaurant = r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_restaurant?.name ?? '餐厅详情')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppTheme.textLight)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final r = _restaurant;
    if (r == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(r.name,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                      ),
                      if (r.rating != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('★ ${r.rating}',
                              style: const TextStyle(
                                  color: Colors.orange, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 14, color: AppTheme.textLight),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          r.address.isNotEmpty ? r.address : r.district,
                          style: const TextStyle(color: AppTheme.textLight, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('在「${r.district}」吃过 ${r.recordCount} 次',
                      style: const TextStyle(fontSize: 13, color: AppTheme.textLight)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('用餐记录',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RecordFormPage(restaurant: r),
                    ),
                  );
                  _load();
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('记一笔'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (r.records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('还没有记录，来留下第一次的回忆吧',
                    style: TextStyle(color: AppTheme.textLight)),
              ),
            )
          else
            ...r.records.map(
              (rec) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFFFF3D6),
                    child: Text('${rec.rating}★',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.primaryDark)),
                  ),
                  title: Text(rec.date,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                    rec.comment.isNotEmpty
                        ? rec.comment
                        : (rec.mood.isNotEmpty
                            ? rec.mood
                            : (rec.perCapita != null
                                ? '人均 ¥${rec.perCapita}'
                                : '没有留下点评')),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
