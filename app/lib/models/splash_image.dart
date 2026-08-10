/// 加载页图片（后端每日随机返回一张，同一天固定、相邻两天不重复）。
class SplashImage {
  final int id;
  final String title;

  /// 相对路径（如 /media/splash/xx.png），展示前需用 [FoodmapApi.mediaUrl] 拼接服务地址
  final String url;

  const SplashImage({
    required this.id,
    required this.title,
    required this.url,
  });

  factory SplashImage.fromJson(Map<String, dynamic> json) => SplashImage(
        id: json['id'] as int,
        title: json['title']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
      );
}
