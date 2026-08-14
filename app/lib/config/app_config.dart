/// 专属信息集中配置 —— 送给她之前，把这里改成她的信息即可！
///
/// 修改指引（三步）：
/// 1. [herName] 改成她的昵称（或你想称呼她的名字）
/// 2. [meetDate] 改成你们认识的日期，首页会自动计算「认识天数」
/// 3. [serverUrl] 已默认指向云端服务器（139.196.27.224），装机即连、无需配置；
///    如更换服务器，可在 APP「设置」页修改后端地址（高级功能，一般不用动）
class AppConfig {
  /// 她的昵称（显示在首页顶部和欢迎语里）
  static const String herName = '小仙女';

  /// 你们认识的日期（格式 YYYY-MM-DD），用于计算认识天数
  static const String meetDate = '2026-01-01';

  /// 首页专属欢迎语
  static const String greeting = '今天也要好好吃饭呀';

  /// 后端 API 地址（默认已指向云端服务器，装机即连）。
  /// 运行后可在设置页修改并保存到本机（覆盖默认值），无需重新打包。
  static const String serverUrl = 'http://139.196.27.224';

  /// API 鉴权令牌（与后端 backend/config/config.ini 的 API_TOKEN 保持一致）
  static const String apiToken = 'clw-api-8f3k2j9h4g5d6s7a';

  /// 今日美食卡片的标题前缀（专属感文案）
  static const String dailyDishTitle = '今天想带你吃';
}
