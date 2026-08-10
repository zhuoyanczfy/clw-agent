/// 行政区（南京），adcode 用于与 GeoJSON 多边形匹配。
class District {
  final int id;
  final String name;
  final String adcode;
  final int restaurantCount;
  final int visitedCount;

  const District({
    required this.id,
    required this.name,
    required this.adcode,
    this.restaurantCount = 0,
    this.visitedCount = 0,
  });

  factory District.fromJson(Map<String, dynamic> json) => District(
        id: json['id'] as int,
        name: json['name'] as String,
        adcode: json['adcode']?.toString() ?? '',
        restaurantCount: (json['restaurant_count'] as num?)?.toInt() ?? 0,
        visitedCount: (json['visited_count'] as num?)?.toInt() ?? 0,
      );
}
