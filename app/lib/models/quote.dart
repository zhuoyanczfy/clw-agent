/// 好句好段：数据源为 hitokoto.cn（一言），按日期缓存。
class Quote {
  final int id;
  final String date; // YYYY-MM-DD
  final String text;
  final String author;
  final String source;
  final String category;
  final String imageUrl;

  const Quote({
    required this.id,
    required this.date,
    required this.text,
    required this.author,
    required this.source,
    required this.category,
    required this.imageUrl,
  });

  factory Quote.fromJson(Map<String, dynamic> json) {
    final q = (json['quote'] as Map?)?.cast<String, dynamic>() ?? json;
    return Quote(
      id: q['id'] as int? ?? 0,
      date: q['date']?.toString() ?? '',
      text: q['text']?.toString() ?? '',
      author: q['author']?.toString() ?? '',
      source: q['source']?.toString() ?? '',
      category: q['category']?.toString() ?? '',
      imageUrl: q['image_url']?.toString() ?? '',
    );
  }
}
