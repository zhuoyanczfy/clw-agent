import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/dining_record.dart';
import '../models/district.dart';
import '../models/divination.dart';
import '../models/pet.dart';
import '../models/quote.dart';
import '../models/restaurant.dart';
import '../models/splash_image.dart';
import '../models/wishlist_item.dart';
import 'api_config.dart';

/// 后端 API 异常（网络失败 / 非 2xx）。
class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}

/// 美食足迹 API 客户端：与 Django 后端（backend/foodmap/views.py）对接。
class FoodmapApi {
  FoodmapApi._();

  static Future<String> _base() async => ApiConfig.getBaseUrl();

  static Uri _uri(String base, String path) => Uri.parse('$base$path');

  static Never _throw(http.Response resp) {
    String msg = '请求失败(${resp.statusCode})';
    try {
      final json = jsonDecode(utf8.decode(resp.bodyBytes));
      if (json is Map && json['error'] != null) msg = json['error'].toString();
    } catch (_) {}
    throw ApiException(msg);
  }

  /// 统一请求入口：自动附带鉴权头、处理超时与错误。
  static Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final base = await _base();
    if (base.isEmpty) throw const ApiException('还未配置后端地址，请到设置页填写');
    final headers = <String, String>{'X-Api-Token': AppConfig.apiToken};
    http.Response resp;
    switch (method) {
      case 'GET':
        resp = await http.get(_uri(base, path), headers: headers).timeout(timeout);
      case 'DELETE':
        resp = await http.delete(_uri(base, path), headers: headers).timeout(timeout);
      case 'POST':
      case 'PUT':
        headers['Content-Type'] = 'application/json';
        final req = method == 'POST'
            ? http.post(_uri(base, path), headers: headers, body: jsonEncode(body ?? {}))
            : http.put(_uri(base, path), headers: headers, body: jsonEncode(body ?? {}));
        resp = await req.timeout(timeout);
      default:
        throw ApiException('不支持的请求方法: $method');
    }
    if (resp.statusCode >= 300) _throw(resp);
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  static Future<dynamic> _getJson(String path) =>
      _request('GET', path, timeout: const Duration(seconds: 15));

  static Future<dynamic> _postJson(String path, [Map<String, dynamic>? body]) =>
      _request('POST', path, body: body);

  static Future<dynamic> _putJson(String path, Map<String, dynamic> body) =>
      _request('PUT', path, body: body);

  static Future<void> _deleteJson(String path) async {
    await _request('DELETE', path);
  }

  // ---------- 健康检查 ----------

  static Future<bool> health() async {
    try {
      final base = await _base();
      if (base.isEmpty) return false;
      final resp = await http
          .get(
            _uri(base, '/api/health/'),
            headers: {'X-Api-Token': AppConfig.apiToken},
          )
          .timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---------- 每日占卜 ----------

  /// 今日占卜结果：当天首次请求由后端抽牌并调 DeepSeek 生成，之后命中缓存。
  /// 生成解读耗时较长，超时放宽到 75 秒。
  static Future<Divination> fetchTodayDivination() async {
    final json = await _request(
      'GET',
      '/api/divination/today/',
      timeout: const Duration(seconds: 75),
    ) as Map<String, dynamic>;
    return Divination.fromJson(json);
  }

  // ---------- 好句好段 ----------

  /// 今日好句：按日期缓存，当天恒定。
  static Future<Quote> fetchTodayQuote() async {
    final json = await _getJson('/api/quotes/today/') as Map<String, dynamic>;
    return Quote.fromJson(json);
  }

  /// 历史好句列表。
  static Future<List<Quote>> fetchQuoteHistory() async {
    final json = await _getJson('/api/quotes/history/') as Map<String, dynamic>;
    return (json['quotes'] as List)
        .map((e) => Quote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 再来一条：实时拉取，不缓存、不计数。
  static Future<Quote> fetchRandomQuote() async {
    final json = await _getJson('/api/quotes/random/') as Map<String, dynamic>;
    return Quote.fromJson(json);
  }

  // ---------- 区与餐厅 ----------

  /// 全部行政区（含餐厅数/足迹数）
  static Future<List<District>> fetchDistricts() async {
    final json = await _getJson('/api/districts/') as Map<String, dynamic>;
    return (json['districts'] as List)
        .map((e) => District.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 南京区划 GeoJSON（flutter_map 分区高亮）
  static Future<Map<String, dynamic>> fetchDistrictsGeoJson() async {
    final base = await _base();
    final resp = await http
        .get(
          _uri(base, '/api/districts.geojson'),
          headers: {'X-Api-Token': AppConfig.apiToken},
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) throw ApiException('区划数据加载失败(${resp.statusCode})');
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  /// 餐厅列表；[district] 按区名过滤，[visitedOnly] 只看去过（地图标记），
  /// [query] 关键词搜索（后端最多返回 50 条，供记录页选餐厅用）
  static Future<List<Restaurant>> fetchRestaurants({
    String? district,
    bool visitedOnly = false,
    String? query,
  }) async {
    final params = <String, String>{
      if (district != null && district.isNotEmpty) 'district': district,
      if (visitedOnly) 'visited': '1',
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    };
    final queryStr = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    final json = await _getJson('/api/restaurants/$queryStr') as Map<String, dynamic>;
    return (json['restaurants'] as List)
        .map((e) => Restaurant.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 餐厅详情（含全部用餐记录）
  static Future<Restaurant> fetchRestaurantDetail(int id) async {
    final json = await _getJson('/api/restaurants/$id/') as Map<String, dynamic>;
    return Restaurant.fromJson(json['restaurant'] as Map<String, dynamic>);
  }

  // ---------- 用餐记录 ----------

  static Future<List<DiningRecord>> fetchRecords() async {
    final json = await _getJson('/api/records/') as Map<String, dynamic>;
    return (json['records'] as List)
        .map((e) => DiningRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 新建记录：传 [restaurantId] 选已有餐厅，或 [restaurantName]+[districtId] 新建餐厅
  static Future<DiningRecord> createRecord({
    int? restaurantId,
    String? restaurantName,
    int? districtId,
    required String date,
    int rating = 4,
    String comment = '',
    int? perCapita,
    String mood = '',
  }) async {
    final json = await _postJson('/api/records/', {
      'restaurant_id': ?restaurantId,
      if (restaurantName != null && restaurantName.isNotEmpty) 'restaurant_name': restaurantName,
      'district_id': ?districtId,
      'date': date,
      'rating': rating,
      'comment': comment,
      'per_capita': perCapita,
      'mood': mood,
    }) as Map<String, dynamic>;
    return DiningRecord.fromJson(json['record'] as Map<String, dynamic>);
  }

  static Future<DiningRecord> updateRecord(
    int id, {
    int? restaurantId,
    String? restaurantName,
    int? districtId,
    required String date,
    int rating = 4,
    String comment = '',
    int? perCapita,
    String mood = '',
  }) async {
    final json = await _putJson('/api/records/$id/', {
      'restaurant_id': ?restaurantId,
      if (restaurantName != null && restaurantName.isNotEmpty) 'restaurant_name': restaurantName,
      'district_id': ?districtId,
      'date': date,
      'rating': rating,
      'comment': comment,
      'per_capita': perCapita,
      'mood': mood,
    }) as Map<String, dynamic>;
    return DiningRecord.fromJson(json['record'] as Map<String, dynamic>);
  }

  static Future<void> deleteRecord(int id) => _deleteJson('/api/records/$id/');

  /// 上传照片（multipart），返回新增照片列表
  static Future<List<RecordPhoto>> uploadPhotos(int recordId, List<String> filePaths) async {
    final base = await _base();
    if (base.isEmpty) throw const ApiException('还未配置后端地址，请到设置页填写');
    final request = http.MultipartRequest('POST', _uri(base, '/api/records/$recordId/photos/'))
      ..headers['X-Api-Token'] = AppConfig.apiToken;
    for (final path in filePaths) {
      request.files.add(await http.MultipartFile.fromPath('photos', path));
    }
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode >= 300) _throw(resp);
    final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return (json['photos'] as List)
        .map((e) => RecordPhoto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> deletePhoto(int photoId) => _deleteJson('/api/records/photos/$photoId/');

  /// 照片完整地址（后端返回相对路径，需拼接服务地址）。
  ///
  /// 带内存缓存：同一相对路径只拼一次，避免列表页每张照片都触发
  /// SharedPreferences 读取。
  static final Map<String, String> _mediaUrlCache = {};

  static Future<String> photoUrl(String path) => mediaUrl(path);

  static Future<String> mediaUrl(String path) async {
    final cached = _mediaUrlCache[path];
    if (cached != null) return cached;
    final base = await _base();
    final url = '$base$path';
    _mediaUrlCache[path] = url;
    return url;
  }

  // ---------- APP 云端配置 ----------

  /// 拉取云端配置（键值对），失败时抛异常由调用方容错
  static Future<Map<String, String>> fetchConfig() async {
    final json = await _getJson('/api/config/') as Map<String, dynamic>;
    final raw = json['config'] as Map<String, dynamic>;
    return raw.map((k, v) => MapEntry(k, v?.toString() ?? ''));
  }

  // ---------- 加载页 ----------

  /// 当日加载页图片（后端保证同一天固定一张、相邻两天不重复）
  static Future<SplashImage> fetchSplash() async {
    final json = await _getJson('/api/splash/') as Map<String, dynamic>;
    return SplashImage.fromJson(json['splash'] as Map<String, dynamic>);
  }

  // ---------- 待尝清单 ----------

  static Future<List<WishlistItem>> fetchWishlist({String? status}) async {
    final query = status == null ? '' : '?status=$status';
    final json = await _getJson('/api/wishlist/$query') as Map<String, dynamic>;
    return (json['items'] as List)
        .map((e) => WishlistItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<WishlistItem> addWishlist({
    required String name,
    String? amapId,
    int? districtId,
    String district = '',
    String reason = '',
    int? perCapita,
    String source = 'ai',
  }) async {
    final json = await _postJson('/api/wishlist/', {
      'name': name,
      'amap_id': ?amapId,
      'district_id': ?districtId,
      if (district.isNotEmpty) 'district': district,
      'reason': reason,
      'per_capita': perCapita,
      'source': source,
    }) as Map<String, dynamic>;
    return WishlistItem.fromJson(json['item'] as Map<String, dynamic>);
  }

  static Future<WishlistItem> markWishlistEaten(int id) async {
    final json = await _postJson('/api/wishlist/$id/eaten/') as Map<String, dynamic>;
    return WishlistItem.fromJson(json['item'] as Map<String, dynamic>);
  }

  static Future<void> deleteWishlist(int id) => _deleteJson('/api/wishlist/$id/');

  /// 校验推荐卡片真实性（高德），返回 {ok, amapId, name, address, district, rating}
  static Future<List<Map<String, dynamic>>> verifyRecommendItems(List<Map<String, dynamic>> items) async {
    final json = await _postJson('/api/recommend/verify/', {'items': items}) as Map<String, dynamic>;
    return (json['items'] as List).cast<Map<String, dynamic>>();
  }

  // ---------- 宠物名片 ----------

  /// 宠物列表（单用户场景通常 0 或 1 条）
  static Future<List<Pet>> fetchPets() async {
    final json = await _getJson('/api/pets/') as Map<String, dynamic>;
    return (json['pets'] as List)
        .map((e) => Pet.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 创建宠物档案（multipart，avatar 可选）
  static Future<Pet> createPet({
    required String name,
    String breed = '',
    String gender = '',
    String birthday = '',
    String adoptDate = '',
    String notes = '',
    String? avatarPath,
  }) async {
    final base = await _base();
    if (base.isEmpty) throw const ApiException('还未配置后端地址，请到设置页填写');
    final request = http.MultipartRequest('POST', _uri(base, '/api/pets/'))
      ..headers['X-Api-Token'] = AppConfig.apiToken
      ..fields['name'] = name
      ..fields['breed'] = breed
      ..fields['gender'] = gender
      ..fields['birthday'] = birthday
      ..fields['adopt_date'] = adoptDate
      ..fields['notes'] = notes;
    if (avatarPath != null) {
      request.files.add(await http.MultipartFile.fromPath('avatar', avatarPath));
    }
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode >= 300) _throw(resp);
    final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return Pet.fromJson(json['pet'] as Map<String, dynamic>);
  }

  /// 更新宠物档案（multipart 全字段；avatarPath 传 null 表示不换头像）
  static Future<Pet> updatePet(
    int id, {
    required String name,
    String breed = '',
    String gender = '',
    String birthday = '',
    String adoptDate = '',
    String notes = '',
    String? avatarPath,
  }) async {
    final base = await _base();
    if (base.isEmpty) throw const ApiException('还未配置后端地址，请到设置页填写');
    final request = http.MultipartRequest('POST', _uri(base, '/api/pets/$id/'))
      ..headers['X-Api-Token'] = AppConfig.apiToken
      ..fields['name'] = name
      ..fields['breed'] = breed
      ..fields['gender'] = gender
      ..fields['birthday'] = birthday
      ..fields['adopt_date'] = adoptDate
      ..fields['notes'] = notes;
    if (avatarPath != null) {
      request.files.add(await http.MultipartFile.fromPath('avatar', avatarPath));
    }
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode >= 300) _throw(resp);
    final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return Pet.fromJson(json['pet'] as Map<String, dynamic>);
  }

  static Future<void> deletePet(int id) => _deleteJson('/api/pets/$id/');

  /// 宠物照片列表
  static Future<List<PetPhoto>> fetchPetPhotos(int petId) async {
    final json = await _getJson('/api/pets/$petId/photos/') as Map<String, dynamic>;
    return (json['photos'] as List)
        .map((e) => PetPhoto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 上传宠物照片（multipart，可多张，caption 可选）
  static Future<List<PetPhoto>> uploadPetPhotos(
    int petId,
    List<String> filePaths, {
    String caption = '',
  }) async {
    final base = await _base();
    if (base.isEmpty) throw const ApiException('还未配置后端地址，请到设置页填写');
    final request = http.MultipartRequest('POST', _uri(base, '/api/pets/$petId/photos/'))
      ..headers['X-Api-Token'] = AppConfig.apiToken
      ..fields['caption'] = caption;
    for (final path in filePaths) {
      request.files.add(await http.MultipartFile.fromPath('images', path));
    }
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode >= 300) _throw(resp);
    final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return (json['photos'] as List)
        .map((e) => PetPhoto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> deletePetPhoto(int photoId) =>
      _deleteJson('/api/pets/photos/$photoId/');

  /// 宠物事项列表（按日期倒序）
  static Future<List<PetEvent>> fetchPetEvents(int petId) async {
    final json = await _getJson('/api/pets/$petId/events/') as Map<String, dynamic>;
    return (json['events'] as List)
        .map((e) => PetEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 添加宠物事项
  static Future<PetEvent> addPetEvent(
    int petId, {
    required String kind,
    required String title,
    required String date,
    String dueDate = '',
    double? weight,
    String note = '',
  }) async {
    final json = await _postJson('/api/pets/$petId/events/', {
      'kind': kind,
      'title': title,
      'date': date,
      if (dueDate.isNotEmpty) 'due_date': dueDate,
      'weight': ?weight,
      'note': note,
    }) as Map<String, dynamic>;
    return PetEvent.fromJson(json['event'] as Map<String, dynamic>);
  }

  static Future<void> deletePetEvent(int eventId) =>
      _deleteJson('/api/pets/events/$eventId/');

  // ---------- AI 推荐官（SSE 流式聊天） ----------

  /// 历史会话分页列表（按更新时间倒序）。返回 (本页会话, 总数)，
  /// 触底翻页时用 [offset] = 已加载条数继续拉。
  static Future<(List<Map<String, dynamic>>, int)> chatSessions({
    int offset = 0,
    int limit = 20,
  }) async {
    final json = await _getJson(
      '/api/chat/sessions/?offset=$offset&limit=$limit',
    ) as Map<String, dynamic>;
    final sessions = [
      for (final s in (json['sessions'] as List? ?? const []))
        Map<String, dynamic>.from(s as Map),
    ];
    return (sessions, json['total'] as int? ?? 0);
  }

  /// 单会话详情（含 messages：[{role, content}]）。
  static Future<Map<String, dynamic>> chatSessionDetail(int id) async {
    final json = await _getJson('/api/chat/sessions/$id/') as Map<String, dynamic>;
    return Map<String, dynamic>.from(json['session'] as Map);
  }

  /// 保存会话：带 [sessionId] 则更新，否则新建。返回会话摘要（含新 id）。
  static Future<Map<String, dynamic>> saveChatSession({
    int? sessionId,
    String title = '',
    required List<Map<String, String>> messages,
  }) async {
    final json = await _postJson('/api/chat/sessions/', {
      'session_id': ?sessionId,
      'title': title,
      'messages': messages,
    }) as Map<String, dynamic>;
    return Map<String, dynamic>.from(json['session'] as Map);
  }

  /// 删除会话。
  static Future<void> deleteChatSession(int id) =>
      _deleteJson('/api/chat/sessions/$id/');

  /// 发送消息并流式接收回复。返回 `Stream<String>`（增量文本），onDone 表示流结束。
  /// [history] 为之前 user/assistant 消息列表（不含本轮）。
  static Stream<String> chatStream(String message, List<Map<String, String>> history) async* {
    final base = await _base();
    if (base.isEmpty) throw const ApiException('还未配置后端地址，请到设置页填写');
    final client = http.Client();
    try {
      final request = http.Request('POST', _uri(base, '/api/recommend/chat/'))
        ..headers['X-Api-Token'] = AppConfig.apiToken
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'text/event-stream'
        ..body = jsonEncode({'message': message, 'history': history});
      final response = await client.send(request).timeout(const Duration(seconds: 30));

      final lines = utf8.decoder
          .bind(response.stream)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (!line.startsWith('data: ')) continue;
        final payload = line.substring(6);
        if (payload == '[DONE]') break;
        Map<String, dynamic> json;
        try {
          json = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue; // 忽略非 JSON 行，继续读下一行
        }
        if (json['error'] != null) throw ApiException(json['error'].toString());
        final delta = json['delta']?.toString() ?? '';
        if (delta.isNotEmpty) yield delta;
      }
    } finally {
      client.close();
    }
  }
}
