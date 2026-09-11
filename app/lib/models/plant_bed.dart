/// 花坛：把多株种草组合成一天的游园计划（可定一个赏花日）。
///
/// 完成态由成员推导——坛里的植物全部拔草即"已收获 🧺"。
class PlantBed {
  final int id;
  final String title;

  /// 赏花日（YYYY-MM-DD，空串表示还没定）。
  final String visitDate;
  final List<PlantBedMember> items;
  final int doneCount;
  final int total;
  final bool isHarvested;
  final String createdAt;
  final String updatedAt;

  const PlantBed({
    required this.id,
    required this.title,
    this.visitDate = '',
    this.items = const [],
    this.doneCount = 0,
    this.total = 0,
    this.isHarvested = false,
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory PlantBed.fromJson(Map<String, dynamic> json) => PlantBed(
        id: json['id'] as int,
        title: json['title']?.toString() ?? '',
        visitDate: json['visit_date']?.toString() ?? '',
        items: (json['items'] as List?)
                ?.map((e) => PlantBedMember.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        doneCount: (json['done_count'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
        isHarvested: json['is_harvested'] == true,
        createdAt: json['created_at']?.toString() ?? '',
        updatedAt: json['updated_at']?.toString() ?? '',
      );

  /// 距赏花日还有几天：null = 没定日期；0 = 今天游园；负数 = 已过花季。
  int? get daysUntilVisit {
    if (visitDate.isEmpty) return null;
    final d = DateTime.tryParse(visitDate);
    if (d == null) return null;
    final now = DateTime.now();
    return DateTime(d.year, d.month, d.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }
}

/// 花坛里的一株植物：引用植物园条目（拔草状态两边同步），可带时段备注。
class PlantBedMember {
  final int id;

  /// 对应植物园条目 id。
  final int itemId;
  final String title;

  /// 想实现程度：1~3（1 种草 🌱 / 2 种花 🌻 / 3 种树 🌳）。
  final int intensity;
  final bool isCompleted;
  final String completedAt;

  /// 拔草手记（游园清单里已拔站点可预览）。
  final String memoryText;

  /// 时段备注，如：早上/中午/下午。
  final String timeNote;

  const PlantBedMember({
    required this.id,
    required this.itemId,
    required this.title,
    this.intensity = 1,
    this.isCompleted = false,
    this.completedAt = '',
    this.memoryText = '',
    this.timeNote = '',
  });

  factory PlantBedMember.fromJson(Map<String, dynamic> json) => PlantBedMember(
        id: json['id'] as int,
        itemId: json['item_id'] as int,
        title: json['title']?.toString() ?? '',
        intensity: (json['intensity'] as num?)?.toInt() ?? 1,
        isCompleted: json['is_completed'] == true,
        completedAt: json['completed_at']?.toString() ?? '',
        memoryText: json['memory_text']?.toString() ?? '',
        timeNote: json['time_note']?.toString() ?? '',
      );
}
