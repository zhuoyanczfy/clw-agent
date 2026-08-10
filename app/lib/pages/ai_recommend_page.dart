import 'dart:async';

import 'package:flutter/material.dart';

import '../services/foodmap_api.dart';
import '../theme.dart';
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

  /// 从 AI 回复中提取形如「店名（区）」的推荐，供一键收藏
  void _extractRecommendations(String reply) {
    final regex = RegExp(r'[「【】"]?\s*([\u4e00-\u9fa5A-Za-z0-9·&（）()]{2,20}?)\s*[」】"]?\s*(?:（|\(|【)([\u4e00-\u9fa5]{2,4}区)(?:）|\)|】)');
    final found = <Map<String, dynamic>>[];
    for (final m in regex.allMatches(reply)) {
      final name = m.group(1)!.trim();
      final district = m.group(2)!.trim();
      if (name.isEmpty || name.length > 16) continue;
      if (found.any((f) => f['name'] == name)) continue;
      found.add({'name': name, 'district': district});
    }
    if (found.isEmpty) return;
    setState(() {
      _recommended
        ..clear()
        ..addAll(found);
    });
  }

  Future<void> _collect(Map<String, dynamic> item) async {
    try {
      await FoodmapApi.addWishlist(
        name: item['name'] as String,
        district: (item['district'] as String?) ?? '',
        source: 'ai',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「${item['name']}」已加入待尝清单')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('美食推荐官'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WishlistPage()),
            ),
            icon: const Icon(Icons.favorite_outline),
            tooltip: '待尝清单',
          ),
          IconButton(
            onPressed: _busy
                ? null
                : () => setState(() => _messages.clear()),
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清空对话',
          ),
        ],
      ),
      body: Column(
        children: [
          // 推荐卡片（AI 回复中识别出的餐厅）
          if (_recommended.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              color: const Color(0xFFFFF3E0),
              child: SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final item in _recommended)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: const Icon(Icons.favorite, size: 16, color: AppTheme.primary),
                          label: Text('${item['name']}'),
                          onPressed: () => _collect(item),
                        ),
                      ),
                  ],
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
                    itemCount: _messages.length + (_streaming.isNotEmpty ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return _bubble('assistant', _streaming, streaming: true);
                      }
                      final m = _messages[index];
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
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send),
                    style: IconButton.styleFrom(backgroundColor: AppTheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
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
            const Text('南京美食推荐官',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
    return Align(
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
    );
  }
}
