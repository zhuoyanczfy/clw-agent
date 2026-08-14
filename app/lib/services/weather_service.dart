import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/weather.dart';
import 'api_config.dart';

/// 天气服务：从后端代理接口拉取（高德数据，实况 30min / 预报 3h 服务端缓存），
/// 本机缓存兜底：网络失败时返回上次成功拉取的天气。
class WeatherService {
  static const _cacheKey = 'weather_cache';

  /// 拉取天气；失败时读本机缓存，都没有则抛异常（调用方静默降级）。
  static Future<WeatherInfo> fetchWeather() async {
    final base = await ApiConfig.getBaseUrl();
    if (base.isNotEmpty) {
      try {
        final resp = await http
            .get(
              Uri.parse('$base/api/weather/'),
              headers: {'X-Api-Token': AppConfig.apiToken},
            )
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final json = jsonDecode(utf8.decode(resp.bodyBytes));
          final info =
              WeatherInfo.fromJson(json as Map<String, dynamic>);
          if (info.live.city.isNotEmpty) {
            await _saveCache(json);
            return info;
          }
        }
      } catch (_) {
        // 网络失败，走本机缓存兜底
      }
    }
    final cached = await _readCache();
    if (cached != null) return cached;
    throw Exception('天气数据不可用');
  }

  static Future<void> _saveCache(Map<String, dynamic> json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(json));
    } catch (_) {}
  }

  static Future<WeatherInfo?> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      return WeatherInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
