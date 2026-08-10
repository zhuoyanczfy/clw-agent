/// 专属信息集中配置 —— 送给她之前，把这里改成她的信息即可！
///
/// 修改指引（三步）：
/// 1. [herName] 改成她的昵称（或你想称呼她的名字）
/// 2. [meetDate] 改成你们认识的日期，首页会自动计算「认识天数」
/// 3. [serverUrl] 如果你部署了后端服务，填上公网地址（如 https://xxx.com）；
///    不填或留空，APP 会自动使用内置美食库，按日期轮换推荐
class AppConfig {
  /// 她的昵称（显示在首页顶部和欢迎语里）
  static const String herName = '小仙女';

  /// 你们认识的日期（格式 YYYY-MM-DD），用于计算认识天数
  static const String meetDate = '2026-01-01';

  /// 首页专属欢迎语
  static const String greeting = '今天也要好好吃饭呀';

  /// 后端 API 地址（可选）。
  /// 留空则使用内置美食库；部署后填：https://你的域名
  static const String serverUrl = '';

  /// 今日美食卡片的标题前缀（专属感文案）
  static const String dailyDishTitle = '今天想带你吃';
}
