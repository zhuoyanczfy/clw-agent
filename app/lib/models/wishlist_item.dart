/// 待尝清单项（AI 推荐收藏或手动添加）。
class WishlistItem {
  final int id;
  final String name;
  final String? amapId;
  final int? districtId;
  final String district;
  final String reason;
  final int? perCapita;
  final String status; // pending | eaten
  final String source; // ai | manual
  final String createdAt;

  const WishlistItem({
    required this.id,
    required this.name,
    this.amapId,
    this.districtId,
    this.district = '',
    this.reason = '',
    this.perCapita,
    this.status = 'pending',
    this.source = 'ai',
    this.createdAt = '',
  });

  bool get isPending => status == 'pending';

  factory WishlistItem.fromJson(Map<String, dynamic> json) => WishlistItem(
        id: json['id'] as int,
        name: json['name'] as String,
        amapId: json['amap_id']?.toString(),
        districtId: (json['district_id'] as num?)?.toInt(),
        district: json['district']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
        perCapita: (json['per_capita'] as num?)?.toInt(),
        status: json['status']?.toString() ?? 'pending',
        source: json['source']?.toString() ?? 'ai',
        createdAt: json['created_at']?.toString() ?? '',
      );
}
