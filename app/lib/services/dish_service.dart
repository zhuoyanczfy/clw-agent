import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../data/dishes.dart';
import '../models/dish.dart';
import 'api_config.dart';

/// 美食服务：优先从后端拉取今日推荐，失败或未配置时使用内置美食库。
/// 内置库的取模算法与后端保持一致（md5(date) 前 8 位十六进制取整再取模），
/// 保证无论是否部署后端，同一天的推荐都是同一道菜。
class DishService {
  /// 图片相对路径（/media/...）转完整 URL，已是 http 开头则原样返回
  static Future<Dish> _withFullImageUrl(Dish dish) async {
    final url = dish.imageUrl;
    if (url.isEmpty || url.startsWith('http')) return dish;
    final base = await ApiConfig.getBaseUrl();
    if (base.isEmpty) return dish;
    return Dish(
      id: dish.id,
      name: dish.name,
      category: dish.category,
      description: dish.description,
      recipe: dish.recipe,
      ingredients: dish.ingredients,
      steps: dish.steps,
      imageUrl: '$base$url',
    );
  }

  /// 获取今日推荐（优先每日菜单接口：菜谱池随机+DB按日期缓存，
  /// 失败回退旧菜库接口，再不行用内置库）
  static Future<Dish> getTodayDish() async {
    final dateStr = _dateString(DateTime.now());
    final base = await ApiConfig.getBaseUrl();
    if (base.isNotEmpty) {
      // 新接口：每日菜单（每日随机拉取一道，DB 缓存当天）
      try {
        final resp = await http
            .get(
              Uri.parse('$base/api/meal/today/'),
              headers: {'X-Api-Token': AppConfig.apiToken},
            )
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final json = jsonDecode(utf8.decode(resp.bodyBytes));
          final mealJson = json['meal'] as Map<String, dynamic>?;
          if (mealJson != null &&
              (mealJson['name'] ?? '').toString().isNotEmpty) {
            return _withFullImageUrl(Dish.fromJson(mealJson));
          }
        }
      } catch (_) {
        // 网络失败，回退旧接口
      }
      // 旧接口：菜库按日期取模
      try {
        final resp = await http
            .get(
              Uri.parse('$base/api/dish/today/'),
              headers: {'X-Api-Token': AppConfig.apiToken},
            )
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final json = jsonDecode(utf8.decode(resp.bodyBytes));
          final dishJson = json['dish'] as Map<String, dynamic>;
          if (dishJson['name'] != null && (dishJson['name'] as String).isNotEmpty) {
            return _withFullImageUrl(Dish.fromJson(dishJson));
          }
        }
      } catch (_) {
        // 网络失败，走内置库兜底
      }
    }
    return _withFullImageUrl(_fromBuiltin(dateStr));
  }

  /// 历史每日菜单（云端接口，无网络返回空列表）
  static Future<List<MealRecord>> fetchMealHistory() async {
    final base = await ApiConfig.getBaseUrl();
    if (base.isEmpty) return [];
    try {
      final resp = await http
          .get(
            Uri.parse('$base/api/meal/history/'),
            headers: {'X-Api-Token': AppConfig.apiToken},
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final json = jsonDecode(utf8.decode(resp.bodyBytes));
        final list = json['meals'] as List<dynamic>? ?? [];
        return Future.wait(list.map((e) async {
          final m = e as Map<String, dynamic>;
          return MealRecord(
            date: (m['date'] ?? '').toString(),
            dish: await _withFullImageUrl(Dish.fromJson(m)),
          );
        }));
      }
    } catch (_) {
      // 网络失败返回空
    }
    return [];
  }

  /// 随机菜单（不落库、不影响今日菜单；失败返回 null）
  static Future<Dish?> fetchRandomMeal() async {
    final base = await ApiConfig.getBaseUrl();
    if (base.isEmpty) return null;
    try {
      final resp = await http
          .get(
            Uri.parse('$base/api/meal/random/'),
            headers: {'X-Api-Token': AppConfig.apiToken},
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final json = jsonDecode(utf8.decode(resp.bodyBytes));
        final mealJson = json['meal'] as Map<String, dynamic>?;
        if (mealJson != null &&
            (mealJson['name'] ?? '').toString().isNotEmpty) {
          return _withFullImageUrl(Dish.fromJson(mealJson));
        }
      }
    } catch (_) {
      // 失败返回 null
    }
    return null;
  }

  /// 获取全部菜库（云端优先，失败或未配置时回退内置库）
  static Future<List<Dish>> fetchDishes() async {
    final base = await ApiConfig.getBaseUrl();
    if (base.isNotEmpty) {
      try {
        final resp = await http
            .get(
              Uri.parse('$base/api/dishes/'),
              headers: {'X-Api-Token': AppConfig.apiToken},
            )
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final json = jsonDecode(utf8.decode(resp.bodyBytes));
          final list = json['dishes'] as List<dynamic>;
          final dishes = await Future.wait(list
              .map((e) => Dish.fromJson(e as Map<String, dynamic>))
              .map(_withFullImageUrl));
          if (dishes.isNotEmpty) return dishes;
        }
      } catch (_) {
        // 网络失败，走内置库兜底
      }
    }
    return Future.wait(builtinDishes.map(_withFullImageUrl));
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
            .get(
              Uri.parse('$base/api/favorites/'),
              headers: {'X-Api-Token': AppConfig.apiToken},
            )
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
        final headers = {
          'Content-Type': 'application/json',
          'X-Api-Token': AppConfig.apiToken,
        };
        final resp = adding
            ? await http
                .post(
                  Uri.parse('$base/api/favorites/'),
                  headers: headers,
                  body: jsonEncode({'slug': slug}),
                )
                .timeout(const Duration(seconds: 5))
            : await http
                .delete(Uri.parse('$base/api/favorites/$slug/'), headers: headers)
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
            headers: {
              'Content-Type': 'application/json',
              'X-Api-Token': AppConfig.apiToken,
            },
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

/// 每日菜单历史记录（日期 + 当日菜品）
class MealRecord {
  final String date;
  final Dish dish;

  const MealRecord({required this.date, required this.dish});
}
