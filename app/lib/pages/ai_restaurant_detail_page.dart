import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/foodmap_api.dart';
import '../theme.dart';

/// 推荐官餐馆详情页：高德门店照片轮播 + 特色菜 + 餐馆信息 + 收藏。
/// 数据来自推荐官卡片（photos 为高德返回的门店照片组，展示图/顾客实拍混合，
/// 高德接口没有专门的特色菜图片字段）。
class AiRestaurantDetailPage extends StatefulWidget {
  final Map<String, dynamic> item;

  const AiRestaurantDetailPage({super.key, required this.item});

  @override
  State<AiRestaurantDetailPage> createState() => _AiRestaurantDetailPageState();
}

class _AiRestaurantDetailPageState extends State<AiRestaurantDetailPage> {
  int _photoIndex = 0;
  bool _collecting = false;

  Map<String, dynamic> get _item => widget.item;

  /// 照片列表：优先 photos 全部；无照片时退回 image 主图
  List<String> get _photos {
    final photos = (_item['photos'] as List?) ?? const [];
    final urls = <String>[
      for (final p in photos)
        if (p is Map && (p['url'] ?? '').toString().isNotEmpty)
          (p['url'] ?? '').toString(),
    ];
    if (urls.isEmpty) {
      final image = (_item['image'] ?? '').toString();
      if (image.isNotEmpty) return [image];
    }
    return urls;
  }

  Future<void> _collect() async {
    if (_collecting) return;
    setState(() => _collecting = true);
    try {
      await FoodmapApi.addWishlist(
        name: _item['name'] as String,
        district: (_item['district'] as String?) ?? '',
        amapId: (_item['amap_id'] as String?)?.isNotEmpty == true
            ? _item['amap_id'] as String
            : null,
        perCapita: (_item['per_capita'] as double?)?.round(),
        reason: (_item['reason'] as String?) ?? '',
        source: 'ai',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('「${_item['name']}」已加入待尝清单')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _collecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rating = _item['rating'] as double?;
    final perCapita = _item['per_capita'] as double?;
    final tags = (_item['tags'] as List?)?.cast<String>() ?? const <String>[];
    final address = (_item['address'] ?? '').toString();
    final reason = (_item['reason'] ?? '').toString();
    final district = (_item['district'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: Text('${_item['name']}')),
      body: ListView(
        children: [
          // 照片轮播（高德门店照片组，含展示图与顾客实拍）
          if (_photos.isNotEmpty) _photoCarousel(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 店名 + 评分/人均/区
                Text(
                  '${_item['name']}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (rating != null) ...[
                      const Icon(
                        Icons.star,
                        size: 18,
                        color: Color(0xFFFF9F45),
                      ),
                      Text(
                        ' $rating',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE8823A),
                        ),
                      ),
                    ],
                    if (rating != null && perCapita != null)
                      const SizedBox(width: 10),
                    if (perCapita != null)
                      Text(
                        '人均 ¥${perCapita.round()}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textLight,
                        ),
                      ),
                    if (district.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          district,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFE8823A),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                // 推荐理由
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8F0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFE0B2)),
                    ),
                    child: Text(
                      reason,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppTheme.textDark,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
                // 特色菜
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    '特色菜',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final t in tags) _tagChip(t)],
                  ),
                ],
                // 地址
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: Color(0xFFB08FB8),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          address,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: AppTheme.textLight,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // 收藏
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _collecting ? null : _collect,
                    icon: _collecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.star_outline, size: 18),
                    label: const Text('收藏到待尝'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 照片轮播：左右滑动 + 圆点指示器
  Widget _photoCarousel() {
    return Column(
      children: [
        SizedBox(
          height: 240,
          child: PageView.builder(
            itemCount: _photos.length,
            onPageChanged: (i) => setState(() => _photoIndex = i),
            itemBuilder: (context, index) {
              return CachedNetworkImage(
                imageUrl: _photos[index],
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  color: const Color(0xFFFCE4EC),
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFE0A3B8),
                    ),
                  ),
                ),
                errorWidget: (_, _, _) => Container(
                  color: const Color(0xFFFCE4EC),
                  child: const Center(
                    child: Icon(
                      Icons.storefront,
                      size: 48,
                      color: Color(0xFFE0A3B8),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_photos.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _photos.length; i++)
                Container(
                  width: i == _photoIndex ? 8 : 6,
                  height: i == _photoIndex ? 8 : 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _photoIndex
                        ? AppTheme.primary
                        : const Color(0xFFE0C4D0),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  /// 特色菜标签小徽章
  Widget _tagChip(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: Text(
        tag,
        style: const TextStyle(fontSize: 12, color: Color(0xFFE8823A)),
      ),
    );
  }
}
