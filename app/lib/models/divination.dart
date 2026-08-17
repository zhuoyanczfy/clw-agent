/// 每日占卜结果：三张牌阵（时间之流：过去-现在-未来）+ 解读，后端按日期缓存（当天恒定，零点刷新）。
class Divination {
  final String date; // YYYY-MM-DD
  final List<TarotCard> cards;
  final String reading;
  final String lucky;
  final bool cached; // 是否命中当日缓存（首次生成为 false）

  const Divination({
    required this.date,
    required this.cards,
    required this.reading,
    required this.lucky,
    required this.cached,
  });

  factory Divination.fromJson(Map<String, dynamic> json) {
    final d = (json['divination'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rawCards = (d['cards'] as List?) ?? const [];
    return Divination(
      date: json['date']?.toString() ?? '',
      cards: rawCards
          .whereType<Map>()
          .map((e) => TarotCard.fromJson(e.cast<String, dynamic>()))
          .toList(),
      reading: d['reading']?.toString() ?? '',
      lucky: d['lucky']?.toString() ?? '',
      cached: json['cached'] == true,
    );
  }

  /// 序列化（本地缓存当天结果，与 fromJson 互逆）
  Map<String, dynamic> toJson() => {
        'date': date,
        'divination': {
          'cards': cards.map((c) => c.toJson()).toList(),
          'reading': reading,
          'lucky': lucky,
        },
        'cached': cached,
      };
}

/// 牌阵中的一张牌：位置（过去/现在/未来）+ 牌面 + 正逆位。
class TarotCard {
  final String position;
  final String name;
  final String orientation; // 正位 / 逆位
  final String keyword;
  final String image; // 塔罗牌图片路径（/media/tarot/xx.jpg）

  const TarotCard({
    required this.position,
    required this.name,
    required this.orientation,
    required this.keyword,
    required this.image,
  });

  factory TarotCard.fromJson(Map<String, dynamic> json) => TarotCard(
        position: json['position']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        orientation: json['orientation']?.toString() ?? '正位',
        keyword: json['keyword']?.toString() ?? '',
        image: json['image']?.toString() ?? '',
      );

  /// 逆位时牌卡整体倒转展示
  bool get isReversed => orientation == '逆位';

  Map<String, dynamic> toJson() => {
        'position': position,
        'name': name,
        'orientation': orientation,
        'keyword': keyword,
        'image': image,
      };
}
