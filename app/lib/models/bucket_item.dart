/// 心愿清单项：想一起做的事。
class BucketItem {
  final int id;
  final String title;
  final String description;
  final String category;
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

/// 心愿清单照片
class BucketPhoto {
  final int id;
  final String url;

  const BucketPhoto({required this.id, required this.url});

  factory BucketPhoto.fromJson(Map<String, dynamic> json) => BucketPhoto(
        id: json['id'] as int,
        url: json['url']?.toString() ?? '',
      );
}