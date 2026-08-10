/// 用餐记录（含照片）。
class DiningRecord {
  final int id;
  final int restaurantId;
  final String restaurant;
  final String district;
  final String date;
  final int rating;
  final String comment;
  final int? perCapita;
  final String mood;
  final List<RecordPhoto> photos;
  final String createdAt;

  const DiningRecord({
    required this.id,
    required this.restaurantId,
    required this.restaurant,
    required this.district,
    required this.date,
    required this.rating,
    this.comment = '',
    this.perCapita,
    this.mood = '',
    this.photos = const [],
    this.createdAt = '',
  });

  factory DiningRecord.fromJson(Map<String, dynamic> json) => DiningRecord(
        id: json['id'] as int,
        restaurantId: (json['restaurant_id'] as num?)?.toInt() ?? 0,
        restaurant: json['restaurant']?.toString() ?? '',
        district: json['district']?.toString() ?? '',
        date: json['date'] as String,
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        comment: json['comment']?.toString() ?? '',
        perCapita: (json['per_capita'] as num?)?.toInt(),
        mood: json['mood']?.toString() ?? '',
        photos: (json['photos'] as List?)
                ?.map((e) => RecordPhoto.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        createdAt: json['created_at']?.toString() ?? '',
      );
}

/// 用餐照片（url 为相对路径，展示时需拼接后端地址）。
class RecordPhoto {
  final int id;
  final String url;

  const RecordPhoto({required this.id, required this.url});

  factory RecordPhoto.fromJson(Map<String, dynamic> json) => RecordPhoto(
        id: json['id'] as int,
        url: json['url'] as String,
      );
}
