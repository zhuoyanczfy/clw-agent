/// 餐厅（来自后端美食足迹库）。
class Restaurant {
  final int id;
  final String name;
  final int districtId;
  final String district;
  final String address;
  final double? lat;
  final double? lng;
  final String? amapId;
  final double? rating;
  final int recordCount;
  final List<RestaurantRecord> records;

  const Restaurant({
    required this.id,
    required this.name,
    required this.districtId,
    required this.district,
    this.address = '',
    this.lat,
    this.lng,
    this.amapId,
    this.rating,
    this.recordCount = 0,
    this.records = const [],
  });

  bool get visited => recordCount > 0;

  factory Restaurant.fromJson(Map<String, dynamic> json) => Restaurant(
        id: json['id'] as int,
        name: json['name'] as String,
        districtId: (json['district_id'] as num?)?.toInt() ?? 0,
        district: json['district']?.toString() ?? '',
        address: json['address']?.toString() ?? '',
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        amapId: json['amap_id']?.toString(),
        rating: (json['rating'] as num?)?.toDouble(),
        recordCount: (json['record_count'] as num?)?.toInt() ?? 0,
        records: (json['records'] as List?)
                ?.map((e) => RestaurantRecord.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

/// 餐厅下的用餐记录摘要（列表展示用）。
class RestaurantRecord {
  final int id;
  final String date;
  final int rating;
  final String comment;
  final int? perCapita;
  final String mood;

  const RestaurantRecord({
    required this.id,
    required this.date,
    required this.rating,
    this.comment = '',
    this.perCapita,
    this.mood = '',
  });

  factory RestaurantRecord.fromJson(Map<String, dynamic> json) => RestaurantRecord(
        id: json['id'] as int,
        date: json['date'] as String,
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        comment: json['comment']?.toString() ?? '',
        perCapita: (json['per_capita'] as num?)?.toInt(),
        mood: json['mood']?.toString() ?? '',
      );
}
