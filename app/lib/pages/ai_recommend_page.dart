import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/foodmap_api.dart';
import '../theme.dart';
import '../widgets/cute_widgets.dart';
import 'wishlist_page.dart';

/// 聊天消息
class _ChatMsg {
  final String role; // user | assistant
  final String content;
  _ChatMsg(this.role, this.content);
}

/// AI 推荐官：与「南京美食推荐官」多轮对话（SSE 流式），推荐卡片可一键收藏。
class AiRecommendPage extends StatefulWidget {
  const AiRecommendPage({super.key});

  @override
  State<AiRecommendPage> createState() => _AiRecommendPageState();
}

class _AiRecommendPageState extends State<AiRecommendPage> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMsg> _messages = [];
  bool _busy = false;
  String _streaming = ''; // 正在流式生成中的内容

  // AI 最近推荐过的餐厅（用于「收藏」按钮）
  final List<Map<String, dynamic>> _recommended = [];

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _append(String text) {
    _streaming += text;
    setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _busy) return;
    _inputCtrl.clear();
    setState(() {
      _messages.add(_ChatMsg('user', text));
      _busy = true;
      _streaming = '';
    });
    _scrollToBottom();

    // 传给后端的对话历史（不含本轮）
    final history = [
      for (final m in _messages)
        if (m.role != 'user' || m != _messages.last)
          {'role': m.role, 'content': m.content},
    ];

    try {
      await for (final delta in FoodmapApi.chatStream(text, history)) {
        _append(delta);
      }
      // 流结束：落盘并尝试提取推荐餐厅
      final reply = _streaming;
      setState(() {
        _messages.add(_ChatMsg('assistant', reply));
        _streaming = '';
        _busy = false;
      });
      _extractRecommendations(reply);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMsg('assistant', '（出错了：$e）'));
        _streaming = '';
        _busy = false;
      });
    }
    _scrollToBottom();
  }

  /// 拆分 AI 回复：剥离 ```json 代码块 → (纯文本, 餐馆卡片列表)
  (String, List<Map<String, dynamic>>) _parseReply(String content) {
    final cards = <Map<String, dynamic>>[];
    var text = content;
    final jsonBlock = RegExp(r'```json\s*([\s\S]*?)```');
    for (final m in jsonBlock.allMatches(content)) {
      text = text.replaceAll(m.group(0)!, '');
      cards.addAll(_tryParseCards(m.group(1)!));
    }
    // 清理 markdown 符号（AI 文案常带 **粗体** 与 --- 分隔线）
    text = text.replaceAll('**', '');
    text = text.replaceAll(RegExp(r'^---+\s*$', multiLine: true), '');
    // 兜底：剥离偶发的 XML 工具调用标记（后端异常时可能混入回复）
    text = text.replaceAll(RegExp(r'<tool_calls>[\s\S]*?</tool_calls>'), '');
    return (text.trim(), cards);
  }

  /// 宽容解析 JSON 卡片数组：截断尾随文本、去尾逗号，避免 AI 格式偏差导致卡片丢失
  List<Map<String, dynamic>> _tryParseCards(String raw) {
    var s = raw.trim();
    final lastBracket = s.lastIndexOf(']');
    if (lastBracket >= 0 && lastBracket < s.length - 1) {
      s = s.substring(0, lastBracket + 1);
    }
    s = s.replaceAll(RegExp(r',\s*]'), ']');
    try {
      final decoded = jsonDecode(s);
      if (decoded is List) {
        final found = <Map<String, dynamic>>[];
        for (final item in decoded) {
          if (item is Map && item['name'] is String) {
            found.add(_normalizeCard(item));
          }
        }
        return found;
      }
    } catch (_) {
      // 非法 JSON，交给调用方回退正则提取
    }
    return const [];
  }

  /// 流式生成中的显示文本：不展示原始 ```json 代码块，避免用户看到半截 JSON
  String _streamingDisplay(String s) {
    final idx = s.indexOf('```');
    if (idx < 0) return s;
    final head = s.substring(0, idx).trimRight();
    return head.isEmpty ? '（正在生成推荐卡片…）' : '$head\n（正在生成推荐卡片…）';
  }

  /// 从 AI 回复中提取推荐餐厅：优先解析 ```json 卡片（含照片/评分/标签等），
  /// 解析失败时回退正则「店名（区）」提取，供图文卡展示与一键收藏
  void _extractRecommendations(String reply) {
    final found = _parseReply(reply).$2;
    if (found.isEmpty) {
      final regex = RegExp(
        r'[「【】"]?\s*([\u4e00-\u9fa5A-Za-z0-9·&（）()]{2,20}?)\s*[」】"]?\s*(?:（|\(|【)([\u4e00-\u9fa5]{2,4}区)(?:）|\)|】)',
      );
      for (final m in regex.allMatches(reply)) {
        final name = m.group(1)!.trim();
        final district = m.group(2)!.trim();
        if (name.isEmpty || name.length > 16) continue;
        if (found.any((f) => f['name'] == name)) continue;
        found.add({'name': name, 'district': district});
      }
    }
    if (found.isEmpty) return;
    setState(() {
      _recommended
        ..clear()
        ..addAll(found);
    });
  }

  /// 卡片字段归一化：AI 输出可能缺字段或类型不定，统一成 UI 需要的格式
  Map<String, dynamic> _normalizeCard(Map item) {
    double? toDouble(dynamic v) {
      final n = v is num ? v : double.tryParse(v?.toString() ?? '');
      return n == null || n <= 0 ? null : n.toDouble();
    }

    final tags = <String>[];
    for (final t in (item['tags'] as List?) ?? const []) {
      final s = t.toString().trim();
      if (s.isNotEmpty && !tags.contains(s)) tags.add(s);
    }
    return {
      'name': (item['name'] ?? '').toString(),
      'district': (item['district'] ?? '').toString(),
      'reason': (item['reason'] ?? '').toString(),
      'address': (item['address'] ?? '').toString(),
      'amap_id': (item['amap_id'] ?? '').toString(),
      'image': (item['image'] ?? '').toString(),
      'rating': toDouble(item['rating']),
      'per_capita': toDouble(item['per_capita']),
      'tags': tags,
    };
  }

  Future<void> _collect(Map<String, dynamic> item) async {
    try {
      await FoodmapApi.addWishlist(
        name: item['name'] as String,
        district: (item['district'] as String?) ?? '',
        amapId: (item['amap_id'] as String?)?.isNotEmpty == true
            ? item['amap_id'] as String
            : null,
        perCapita: (item['per_capita'] as double?)?.round(),
        reason: (item['reason'] as String?) ?? '',
        source: 'ai',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('「${item['name']}」已加入待尝清单')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('美食推荐官'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const WishlistPage())),
            icon: const Icon(Icons.star_outline),
            tooltip: '待尝清单',
          ),
          IconButton(
            onPressed: _busy ? null : () => setState(() => _messages.clear()),
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清空对话',
          ),
        ],
      ),
      body: Column(
        children: [
          // 推荐卡片（AI 回复 json 卡片中解析出的餐厅，带图/评分/标签）
          if (_recommended.isNotEmpty)
            BouncyIn(
              offsetY: 0,
              duration: const Duration(milliseconds: 350),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                color: const Color(0xFFFFF3E0),
                child: SizedBox(
                  height: 132,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final item in _recommended)
                        _recommendCard(item),
                    ],
                  ),
                ),
              ),
            ),
          // 消息列表
          Expanded(
            child: _messages.isEmpty && _streaming.isEmpty
                ? _emptyHint()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_busy ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        // 生成中：还没吐字时显示「正在输入」，否则显示流式气泡
                        return _streaming.isNotEmpty
                            ? _bubble(
                                'assistant',
                                _streamingDisplay(_streaming),
                                streaming: true,
                              )
                            : _typingBubble();
                      }
                      final m = _messages[index];
                      if (m.role == 'assistant') {
                        // AI 回复：纯文本气泡 + 内嵌餐馆信息卡（特色菜/评分/地址/收藏）
                        final split = _parseReply(m.content);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (split.$1.isNotEmpty)
                              _bubble('assistant', split.$1),
                            for (final c in split.$2)
                              _inlineRestaurantCard(c),
                          ],
                        );
                      }
                      return _bubble(m.role, m.content);
                    },
                  ),
          ),
          // 输入栏
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: _busy ? '推荐官正在思考…' : '告诉我想吃什么（如：想找鼓楼区好吃的川菜）',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy ? null : _send,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 气泡内嵌的餐馆信息卡：门店图 + 店名 + 评分/人均 + 推荐理由 + 特色菜标签 + 地址 + 收藏
  Widget _inlineRestaurantCard(Map<String, dynamic> item) {
    final image = (item['image'] ?? '').toString();
    final rating = item['rating'] as double?;
    final perCapita = item['per_capita'] as double?;
    final tags = (item['tags'] as List?)?.cast<String>() ?? const <String>[];
    final address = (item['address'] ?? '').toString();
    final reason = (item['reason'] ?? '').toString();
    final district = (item['district'] ?? '').toString();
    return BouncyIn(
      offsetY: 12,
      duration: const Duration(milliseconds: 350),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF2DCE6), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：门店图 + 店名 + 评分/人均/区
            Row(
              children: [
                if (image.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: CachedNetworkImage(
                        imageUrl: image,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => _imagePlaceholder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (rating != null) ...[
                            const Icon(
                              Icons.star,
                              size: 13,
                              color: Color(0xFFFF9F45),
                            ),
                            Text(
                              ' $rating',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFE8823A),
                              ),
                            ),
                          ],
                          if (rating != null && perCapita != null)
                            const SizedBox(width: 8),
                          if (perCapita != null)
                            Text(
                              '人均¥${perCapita.round()}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textLight,
                              ),
                            ),
                          if (district.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              district,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textLight,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // 推荐理由
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                reason,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textDark,
                  height: 1.6,
                ),
              ),
            ],
            // 特色菜标签
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final t in tags) _tagChip(t)],
              ),
            ],
            // 地址
            if (address.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: Color(0xFFB08FB8),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textLight,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _collect(item),
                icon: const Icon(Icons.star_outline, size: 16),
                label: const Text('收藏到待尝'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 特色菜标签小徽章
  Widget _tagChip(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: Text(
        tag,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFFE8823A),
        ),
      ),
    );
  }

  /// 推荐图文卡：门店图 + 店名 + 评分/人均 + 特色菜标签，点击收藏
  Widget _recommendCard(Map<String, dynamic> item) {
    final image = (item['image'] ?? '').toString();
    final rating = item['rating'] as double?;
    final perCapita = item['per_capita'] as double?;
    final tags = (item['tags'] as List?)?.cast<String>() ?? const <String>[];
    final tagText = tags.take(3).join(' · ');
    return GestureDetector(
      onTap: () => _collect(item),
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(right: 10),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 门店图（无图时优雅占位）
            Stack(
              children: [
                SizedBox(
                  height: 74,
                  width: double.infinity,
                  child: image.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: image,
                          fit: BoxFit.cover,
                          fadeInDuration: const Duration(milliseconds: 200),
                          errorWidget: (_, _, _) => _imagePlaceholder(),
                        )
                      : _imagePlaceholder(),
                ),
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.star,
                    size: 15,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black26, blurRadius: 4)],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (rating != null) ...[
                        const Icon(
                          Icons.star,
                          size: 11,
                          color: Color(0xFFFF9F45),
                        ),
                        Text(
                          ' $rating',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE8823A),
                          ),
                        ),
                      ],
                      if (rating != null && perCapita != null)
                        const SizedBox(width: 6),
                      if (perCapita != null)
                        Text(
                          '人均¥${perCapita.round()}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppTheme.textLight,
                          ),
                        ),
                    ],
                  ),
                  if (tagText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      tagText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFB08FB8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: const Color(0xFFFCE4EC),
      child: const Center(
        child: Icon(Icons.storefront, size: 26, color: Color(0xFFE0A3B8)),
      ),
    );
  }

  Widget _emptyHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 56, color: AppTheme.accent),
            const SizedBox(height: 16),
            const Text(
              '南京美食推荐官',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '它只从真实餐厅库里为你推荐\n可以问它：\n"周末适合约会的餐厅"、"鼓楼区哪家川菜好吃"',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textLight, height: 1.7),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(String role, String content, {bool streaming = false}) {
    final isUser = role == 'user';
    return BouncyIn(
      offsetY: 18,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          decoration: BoxDecoration(
            color: isUser ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: Text(
            streaming ? '$content▌' : content,
            style: TextStyle(
              color: isUser ? Colors.white : AppTheme.textDark,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  /// 「正在输入」气泡：三个圆点依次跳动
  Widget _typingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: const TypingDots(color: AppTheme.textLight),
      ),
    );
  }
}
