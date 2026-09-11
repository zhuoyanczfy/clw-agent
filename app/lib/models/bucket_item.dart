/// 植物园条目：想一起做的事（种草/种花/种树）。
class BucketItem {
  final int id;
  final String title;
  final String description;
  final String category;

  /// 想实现程度：1~3，越大越想要（1 种草 🌱 / 2 种花 🌻 / 3 种树 🌳）。
  final int intensity;
  final int sortOrder;
  final bool isCompleted;
  final String completedAt;
  final String memoryText;
  final List<BucketPhoto> photos;
  final String createdAt;
  final String updatedAt;

  const BucketItem({
    required this.id,
    required this.title,
    this.description = '',
    this.category = '',
    this.intensity = 1,
    this.sortOrder = 0,
    this.isCompleted = false,
    this.completedAt = '',
    this.memoryText = '',
    this.photos = const [],
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory BucketItem.fromJson(Map<String, dynamic> json) => BucketItem(
        id: json['id'] as int,
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        intensity: (json['intensity'] as num?)?.toInt() ?? 1,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        isCompleted: json['is_completed'] == true,
        completedAt: json['completed_at']?.toString() ?? '',
        memoryText: json['memory_text']?.toString() ?? '',
        photos: (json['photos'] as List?)
                ?.map((e) => BucketPhoto.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: json['created_at']?.toString() ?? '',
        updatedAt: json['updated_at']?.toString() ?? '',
      );
}

/// 植物园照片
class BucketPhoto {
  final int id;
  final String url;

  const BucketPhoto({required this.id, required this.url});

  factory BucketPhoto.fromJson(Map<String, dynamic> json) => BucketPhoto(
        id: json['id'] as int,
        url: json['url']?.toString() ?? '',
      );
}