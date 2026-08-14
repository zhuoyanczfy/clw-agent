/// 每日占卜结果：塔罗牌 + 解读，后端按日期缓存（当天恒定，零点刷新）。
class Divination {
  final String date; // YYYY-MM-DD
  final String cardName;
  final String orientation; // 正位 / 逆位
  final String keyword;
  final String reading;
  final String lucky;
  final bool cached; // 是否命中当日缓存（首次生成为 false）

  const Divination({
    required this.date,
    required this.cardName,
    required this.orientation,
    required this.keyword,
    required this.reading,
    required this.lucky,
    required this.cached,
  });

  factory Divination.fromJson(Map<String, dynamic> json) {
    final d = (json['divination'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Divination(
      date: json['date']?.toString() ?? '',
      cardName: d['card_name']?.toString() ?? '',
      orientation: d['orientation']?.toString() ?? '正位',
      keyword: d['keyword']?.toString() ?? '',
      reading: d['reading']?.toString() ?? '',
      lucky: d['lucky']?.toString() ?? '',
      cached: json['cached'] == true,
    );
  }

  /// 逆位时结果卡片整体倒转展示
  bool get isReversed => orientation == '逆位';
}
