import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/dishes.dart';
import '../models/dish.dart';
import 'api_config.dart';

/// 美食服务：优先从后端拉取今日推荐，失败或未配置时使用内置美食库。
/// 内置库的取模算法与后端保持一致（md5(date) 前 8 位十六进制取整再取模），
/// 保证无论是否部署后端，同一天的推荐都是同一道菜。
class DishService {
  /// 获取今日推荐
  static Future<Dish> getTodayDish() async {
    final dateStr = _dateString(DateTime.now());
    final base = await ApiConfig.getBaseUrl();
    if (base.isNotEmpty) {
      try {
        final resp = await http
            .get(Uri.parse('$base/api/dish/today/'))
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final json = jsonDecode(utf8.decode(resp.bodyBytes));
          final dishJson = json['dish'] as Map<String, dynamic>;
          if (dishJson['name'] != null && (dishJson['name'] as String).isNotEmpty) {
            return Dish.fromJson(dishJson);
          }
        }
      } catch (_) {
        // 网络失败，走内置库兜底
      }
    }
    return _fromBuiltin(dateStr);
  }

  /// 获取全部菜库（云端优先，失败或未配置时回退内置库）
  static Future<List<Dish>> fetchDishes() async {
    final base = await ApiConfig.getBaseUrl();
    if (base.isNotEmpty) {
      try {
        final resp = await http
            .get(Uri.parse('$base/api/dishes/'))
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final json = jsonDecode(utf8.decode(resp.bodyBytes));
          final list = json['dishes'] as List<dynamic>;
          final dishes = list
              .map((e) => Dish.fromJson(e as Map<String, dynamic>))
              .toList();
          if (dishes.isNotEmpty) return dishes;
        }
      } catch (_) {
        // 网络失败，走内置库兜底
      }
    }
    return builtinDishes;
  }

  /// 按日期从内置库取（与后端 dish_for_date 算法一致）
  static Dish _fromBuiltin(String dateStr) {
    final digest = crypto.md5.convert(utf8.encode(dateStr)).bytes;
    final hex = digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final seed = int.parse(hex.substring(0, 8), radix: 16);
    return builtinDishes[seed % builtinDishes.length];
  }

  // ---------- 收藏（云端为准，本地缓存兜底） ----------

  /// 同步收藏列表：云端有值以云端为准并更新本地缓存；
  /// 云端为空而本地有收藏时，把旧版本地收藏迁移到云端（换机/升级不丢收藏）。
  static Future<List<String>> syncFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final localIds = (prefs.getStringList('favorite_dish_ids') ?? []).toList();
    final base = await ApiConfig.getBaseUrl();
    if (base.isNotEmpty) {
      try {
        final resp = await http
            .get(Uri.parse('$base/api/favorites/'))
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final json = jsonDecode(utf8.decode(resp.bodyBytes));
          final list = json['favorites'] as List<dynamic>? ?? [];
          final remoteIds = list
              .map((e) => ((e as Map<String, dynamic>)['id'] ?? '').toString())
              .where((s) => s.isNotEmpty)
              .toList();
          if (remoteIds.isEmpty && localIds.isNotEmpty) {
            // 云端还没有收藏：把本地收藏迁上去
            for (final id in localIds) {
              await _pushFavorite(base, id);
            }
            await prefs.setStringList('favorite_dish_ids', localIds);
            return localIds;
          }
          await prefs.setStringList('favorite_dish_ids', remoteIds);
          return remoteIds;
        }
      } catch (_) {
        // 云端不可用，用本地缓存
      }
    }
    return localIds;
  }

  /// 收藏/取消收藏：本地立即生效，云端尽力同步（失败不阻断本地操作）。
  static Future<bool> toggleFavorite(String slug) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList('favorite_dish_ids') ?? []).toList();
    final adding = !ids.contains(slug);
    if (adding) {
      ids.add(slug);
    } else {
      ids.remove(slug);
    }
    await prefs.setStringList('favorite_dish_ids', ids);
    final base = await ApiConfig.getBaseUrl();
    if (base.isNotEmpty) {
      try {
        final resp = adding
            ? await http
                .post(
                  Uri.parse('$base/api/favorites/'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'slug': slug}),
                )
                .timeout(const Duration(seconds: 5))
            : await http
                .delete(Uri.parse('$base/api/favorites/$slug/'))
                .timeout(const Duration(seconds: 5));
        return resp.statusCode == 200;
      } catch (_) {
        // 云端失败不阻断本地收藏
      }
    }
    return true;
  }

  static Future<void> _pushFavorite(String base, String slug) async {
    try {
      await http
          .post(
            Uri.parse('$base/api/favorites/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'slug': slug}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // 迁移失败静默，下次启动再试
    }
  }

  static String _dateString(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}
