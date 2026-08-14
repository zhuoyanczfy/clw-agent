import 'package:flutter/material.dart';

import '../models/wishlist_item.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';

/// 待尝清单：AI 推荐收藏 + 手动添加，支持标记已尝。
class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  List<WishlistItem> _items = [];
  bool _loading = true;
  String? _error;
  bool _showEaten = false;

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
      final items = await FoodmapApi.fetchWishlist();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _addManual() async {
    final nameCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加到待尝清单'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '餐厅名称',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: '想吃的理由（可选）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    try {
      await FoodmapApi.addWishlist(
        name: name,
        reason: reasonCtrl.text.trim(),
        source: 'manual',
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _toggleEaten(WishlistItem item) async {
    try {
      if (item.isPending) {
        await FoodmapApi.markWishlistEaten(item.id);
      } else {
        await FoodmapApi.deleteWishlist(item.id);
      }
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _delete(WishlistItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${item.name}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FoodmapApi.deleteWishlist(item.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _items.where((i) => i.isPending).toList();
    final eaten = _items.where((i) => !i.isPending).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('待尝清单'),
        actions: [
          IconButton(
            onPressed: _addManual,
            icon: const Icon(Icons.add),
            tooltip: '手动添加',
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(pending, eaten),
    );
  }

  Widget _buildBody(List<WishlistItem> pending, List<WishlistItem> eaten) {
    if (_loading) return const Center(child: CircularProgressIndicator());
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _SegBtn(
                  label: '待尝（${pending.length}）',
                  selected: !_showEaten,
                  onTap: () => setState(() => _showEaten = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SegBtn(
                  label: '已尝（${eaten.length}）',
                  selected: _showEaten,
                  onTap: () => setState(() => _showEaten = true),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _showEaten ? _list(eaten, eatenMode: true) : _list(pending),
          ),
        ),
      ],
    );
  }

  Widget _list(List<WishlistItem> items, {bool eatenMode = false}) {
    if (items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Icon(eatenMode ? Icons.check_circle_outline : Icons.star_border,
              size: 48, color: AppTheme.textLight),
          const SizedBox(height: 12),
          Center(
            child: Text(
              eatenMode ? '还没有吃过的记录' : '让 AI 推荐官帮你种草，或点右上角手动添加',
              style: const TextStyle(color: AppTheme.textLight),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  item.source == 'ai' ? Icons.auto_awesome : Icons.add_circle_outline,
                  size: 20,
                  color: item.source == 'ai' ? AppTheme.accent : AppTheme.textLight,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      if (item.district.isNotEmpty)
                        Text(item.district,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textLight)),
                      if (item.reason.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(item.reason,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppTheme.textLight)),
                        ),
                      if (item.perCapita != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('人均 ¥${item.perCapita}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.orange)),
                        ),
                    ],
                  ),
                ),
                if (eatenMode)
                  IconButton(
                    onPressed: () => _delete(item),
                    icon: const Icon(Icons.delete_outline,
                        size: 20, color: AppTheme.textLight),
                    tooltip: '删除记录',
                  )
                else
                  FilledButton.tonal(
                    onPressed: () => _toggleEaten(item),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('吃过了', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SegBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SegBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? Colors.white : AppTheme.textDark,
            ),
          ),
        ),
      ),
    );
  }
}
