/// 星语彩蛋：后台配置 secret_notes 里的一条碎碎念。
class SecretNote {
  final String id;
  final String text;
  final String date; // YYYY-MM-DD

  const SecretNote({required this.id, required this.text, required this.date});

  factory SecretNote.fromJson(Map<String, dynamic> json) => SecretNote(
        id: json['id']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        date: json['date']?.toString() ?? '',
      );

  /// 展示用日期：同年只显示「9月16日」，跨年带年份
  String get displayDate {
    final d = DateTime.tryParse(date);
    if (d == null) return date;
    return d.year == DateTime.now().year
        ? '${d.month}月${d.day}日'
        : '${d.year}年${d.month}月${d.day}日';
  }
}
