/// 宠物档案模型：猫咪名片的基本信息。
class Pet {
  final int id;
  final String name;
  final String breed;
  final String gender;
  final String birthday; // YYYY-MM-DD，空串表示未知
  final String adoptDate; // YYYY-MM-DD，空串表示未知
  final String avatar; // 相对路径，如 /media/pet_avatars/x.png
  final String notes;

  const Pet({
    required this.id,
    required this.name,
    required this.breed,
    required this.gender,
    required this.birthday,
    required this.adoptDate,
    required this.avatar,
    required this.notes,
  });

  factory Pet.fromJson(Map<String, dynamic> json) {
    return Pet(
      id: json['id'] as int,
      name: json['name']?.toString() ?? '',
      breed: json['breed']?.toString() ?? '',
      gender: json['gender']?.toString() ?? '',
      birthday: json['birthday']?.toString() ?? '',
      adoptDate: json['adopt_date']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
    );
  }

  /// 年龄描述（从生日算）：如「2 岁 5 个月」；生日未知返回空串
  String get ageText {
    final b = DateTime.tryParse(birthday);
    if (b == null) return '';
    final now = DateTime.now();
    var months =
        (now.year - b.year) * 12 + now.month - b.month;
    if (now.day < b.day) months -= 1;
    if (months < 0) months = 0;
    final years = months ~/ 12;
    final rest = months % 12;
    if (years == 0) return '$rest 个月';
    if (rest == 0) return '$years 岁';
    return '$years 岁 $rest 个月';
  }

  /// 相伴天数（从来家纪念日算，含当天）；无领养日返回 null
  int? get companionDays {
    final d = DateTime.tryParse(adoptDate);
    if (d == null) return null;
    return DateTime.now().difference(d).inDays + 1;
  }
}

/// 宠物照片（成长相册）。
class PetPhoto {
  final int id;
  final String image; // 相对路径
  final String caption;
  final String createdAt;

  const PetPhoto({
    required this.id,
    required this.image,
    required this.caption,
    required this.createdAt,
  });

  factory PetPhoto.fromJson(Map<String, dynamic> json) {
    return PetPhoto(
      id: json['id'] as int,
      image: json['image']?.toString() ?? '',
      caption: json['caption']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}

/// 宠物事项：疫苗 / 驱虫 / 体重 / 其他。
class PetEvent {
  static const kindVaccine = 'vaccine';
  static const kindDeworm = 'deworm';
  static const kindWeight = 'weight';
  static const kindOther = 'other';

  final int id;
  final String kind;
  final String title;
  final String date; // YYYY-MM-DD
  final String dueDate; // YYYY-MM-DD，空串表示无下次到期
  final double? weight; // kg，仅体重事项
  final String note;

  const PetEvent({
    required this.id,
    required this.kind,
    required this.title,
    required this.date,
    required this.dueDate,
    required this.weight,
    required this.note,
  });

  factory PetEvent.fromJson(Map<String, dynamic> json) {
    return PetEvent(
      id: json['id'] as int,
      kind: json['kind']?.toString() ?? kindOther,
      title: json['title']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      dueDate: json['due_date']?.toString() ?? '',
      weight: (json['weight'] as num?)?.toDouble(),
      note: json['note']?.toString() ?? '',
    );
  }

  /// 距下次到期还剩几天；无到期日返回 null；已过期返回负数
  int? get daysUntilDue {
    final d = DateTime.tryParse(dueDate);
    if (d == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(d.year, d.month, d.day);
    return due.difference(today).inDays;
  }
}
