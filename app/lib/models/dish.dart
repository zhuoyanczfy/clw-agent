/// 美食数据模型
class Dish {
  final String id;
  final String name;
  final String category;
  final String description;
  final String recipe;
  final List<String> ingredients;
  final List<String> steps;
  final String imageUrl;

  const Dish({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    this.recipe = '',
    this.ingredients = const [],
    this.steps = const [],
    required this.imageUrl,
  });

  factory Dish.fromJson(Map<String, dynamic> json) {
    final ingredients = _splitLines(json['ingredients']);
    final steps = _splitLines(json['steps']);
    return Dish(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      description: json['description'] as String? ?? '',
      // 旧接口兼容：无材料/步骤时退回 recipe 单段做法
      recipe: json['recipe'] as String? ?? '',
      ingredients: ingredients,
      steps: steps,
      imageUrl: json['image_url'] as String? ?? '',
    );
  }

  /// 是否有完整菜谱（材料用量 + 制作步骤）
  bool get hasDetail => ingredients.isNotEmpty && steps.isNotEmpty;

  static List<String> _splitLines(dynamic value) {
    if (value is! String || value.trim().isEmpty) return const [];
    return value
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}
