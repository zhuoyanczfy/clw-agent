/// 美食数据模型
class Dish {
  final String id;
  final String name;
  final String category;
  final String description;
  final String recipe;
  final String imageUrl;

  const Dish({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.recipe,
    required this.imageUrl,
  });

  factory Dish.fromJson(Map<String, dynamic> json) {
    return Dish(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      description: json['description'] as String? ?? '',
      recipe: json['recipe'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
    );
  }
}
