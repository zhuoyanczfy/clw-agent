/// 故事书条目：列表接口默认不带正文，详情/随机接口带正文。
class Story {
  final int id;
  final String title;
  final String category;

  /// 封面相对路径（可能为空），展示前需拼接服务地址
  final String cover;
  final String source;
  final String updatedAt;

  /// 正文（仅详情/随机接口返回，列表接口为空）
  final String content;

  const Story({
    required this.id,
    required this.title,
    required this.category,
    this.cover = '',
    this.source = '',
    this.updatedAt = '',
    this.content = '',
  });

  factory Story.fromJson(Map<String, dynamic> json) => Story(
        id: json['id'] as int,
        title: json['title']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        cover: json['cover']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        updatedAt: json['updated_at']?.toString() ?? '',
        content: json['content']?.toString() ?? '',
      );
}
