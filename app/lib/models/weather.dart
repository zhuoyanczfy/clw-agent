/// 天气数据模型：实况 + 4 天预报（由后端 /api/weather/ 代理高德返回）。
class WeatherLive {
  final String city; // 城市名（如 南京市）
  final String weather; // 天气现象（晴 / 多云 / 小雨...）
  final String temperature; // 实时气温（摄氏度）
  final String humidity; // 空气湿度
  final String windDirection; // 风向
  final String windPower; // 风力级别
  final String reportTime; // 数据发布时刻

  const WeatherLive({
    required this.city,
    required this.weather,
    required this.temperature,
    required this.humidity,
    required this.windDirection,
    required this.windPower,
    required this.reportTime,
  });

  factory WeatherLive.fromJson(Map<String, dynamic> json) => WeatherLive(
        city: (json['city'] ?? '').toString(),
        weather: (json['weather'] ?? '').toString(),
        temperature: (json['temperature'] ?? '').toString(),
        humidity: (json['humidity'] ?? '').toString(),
        windDirection: (json['winddirection'] ?? '').toString(),
        windPower: (json['windpower'] ?? '').toString(),
        reportTime: (json['reporttime'] ?? '').toString(),
      );

  /// 天气现象 → emoji 图标（先匹配具体现象，再匹配大类）
  static String emoji(String weather) {
    if (weather.contains('雷')) return '⛈️';
    if (weather.contains('暴雨') || weather.contains('大雨')) return '🌧️';
    if (weather.contains('中雨')) return '🌧️';
    if (weather.contains('雨夹雪')) return '🌨️';
    if (weather.contains('雪')) return '❄️';
    if (weather.contains('雨')) return '🌦️';
    if (weather.contains('雾') || weather.contains('霾')) return '🌫️';
    if (weather.contains('阴')) return '☁️';
    if (weather.contains('多云')) return '⛅';
    if (weather.contains('晴')) return '☀️';
    if (weather.contains('风')) return '💨';
    return '🌤️';
  }

  /// 是否下雨（含雨夹雪，天气关怀提醒判断用）
  static bool isRainy(String weather) => weather.contains('雨');
}

/// 单天预报（高德返回当天 + 未来 3 天，共 4 条）
class WeatherForecast {
  final String date; // 2026-08-14
  final String week; // 5
  final String dayWeather; // 白天天气现象
  final String nightWeather; // 夜间天气现象
  final String dayTemp; // 白天温度
  final String nightTemp; // 夜间温度

  const WeatherForecast({
    required this.date,
    required this.week,
    required this.dayWeather,
    required this.nightWeather,
    required this.dayTemp,
    required this.nightTemp,
  });

  factory WeatherForecast.fromJson(Map<String, dynamic> json) =>
      WeatherForecast(
        date: (json['date'] ?? '').toString(),
        week: (json['week'] ?? '').toString(),
        dayWeather: (json['dayweather'] ?? '').toString(),
        nightWeather: (json['nightweather'] ?? '').toString(),
        dayTemp: (json['daytemp'] ?? '').toString(),
        nightTemp: (json['nighttemp'] ?? '').toString(),
      );
}

/// 天气整体数据
class WeatherInfo {
  final WeatherLive live;
  final List<WeatherForecast> forecasts;

  const WeatherInfo({required this.live, required this.forecasts});

  factory WeatherInfo.fromJson(Map<String, dynamic> json) => WeatherInfo(
        live: WeatherLive.fromJson(
            (json['live'] as Map<String, dynamic>?) ?? const {}),
        forecasts: ((json['forecasts'] as List<dynamic>?) ?? const [])
            .map((e) => WeatherForecast.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// 明日预报（forecasts[0] 为今天，[1] 为明天）
  WeatherForecast? get tomorrow =>
      forecasts.length > 1 ? forecasts[1] : null;
}
