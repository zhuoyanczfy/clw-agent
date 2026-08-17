import 'package:flutter/material.dart';

import '../theme.dart';

/// 历史会话左侧抽屉：像网页 agent 一样的侧边栏，切换/删除/新建会话。
/// 列表分页加载：滚动到底部自动拉下一页，旧会话也能翻到。
class ChatHistorySheet extends StatefulWidget {
  final int? currentId;
  final void Function(Map<String, dynamic> session) onSelect;
  final Future<void> Function(Map<String, dynamic> session) onDelete;
  final VoidCallback onNew;

  /// 分页加载一页会话，返回 (本页会话, 总数)；[offset] 为已加载条数。
  final Future<(List<Map<String, dynamic>>, int)> Function(int offset, int limit)
      onLoadPage;

  const ChatHistorySheet({
    super.key,
    required this.currentId,
    required this.onSelect,
    required this.onDelete,
    required this.onNew,
    required this.onLoadPage,
  });

  @override
  State<ChatHistorySheet> createState() => _ChatHistorySheetState();
}

class _ChatHistorySheetState extends State<ChatHistorySheet> {
  static const _pageSize = 20;

  final List<Map<String, dynamic>> _sessions = [];
  final Set<int> _deleting = {};
  final ScrollController _scrollCtrl = ScrollController();

  int _total = 0;
  bool _loading = true; // 首屏加载中
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.extentAfter < 120) _loadMore();
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (list, total) = await widget.onLoadPage(0, _pageSize);
      if (!mounted) return;
      setState(() {
        _sessions
          ..clear()
          ..addAll(list);
        _total = total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败：$e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _sessions.length >= _total) return;
    _loadingMore = true;
    setState(() {});
    try {
      final (list, total) = await widget.onLoadPage(_sessions.length, _pageSize);
      if (!mounted) return;
      setState(() {
        _sessions.addAll(list);
        _total = total;
        _loadingMore = false;
      });
    } catch (_) {
      // 翻页失败静默，继续滚动时会再试
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> session) async {
    final title = (session['title'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定删除「${title.isEmpty ? '未命名会话' : title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting.add(session['id'] as int));
    try {
      await widget.onDelete(session);
      if (!mounted) return;
      setState(() {
        _deleting.remove(session['id'] as int);
        _sessions.removeWhere((s) => s['id'] == session['id']);
        _total -= 1;
      });
    } catch (e) {
      // 删除失败不移除列表项，提示用户重试
      if (!mounted) return;
      setState(() => _deleting.remove(session['id'] as int));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                const Text(
                  '历史会话',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: widget.onNew,
                  icon: const Icon(Icons.add_comment_outlined, size: 18),
                  label: const Text('新会话'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadFirstPage, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_sessions.isEmpty) {
      return const Center(
        child: Text(
          '还没有历史会话',
          style: TextStyle(color: AppTheme.textLight, fontSize: 13),
        ),
      );
    }
    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: _sessions.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i >= _sessions.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _buildTile(_sessions[i]);
      },
    );
  }

  Widget _buildTile(Map<String, dynamic> s) {
    final id = s['id'] as int;
    final title = (s['title'] ?? '').toString();
    final count = s['message_count'] ?? 0;
    final updated = (s['updated_at'] ?? '').toString();
    final isCurrent = id == widget.currentId;
    return ListTile(
      dense: true,
      leading: Icon(
        isCurrent ? Icons.chat_bubble : Icons.chat_bubble_outline,
        color: isCurrent ? AppTheme.primary : AppTheme.textLight,
      ),
      title: Text(
        title.isEmpty ? '未命名会话' : title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
          color: AppTheme.textDark,
        ),
      ),
      subtitle: Text(
        '$updated · $count 条消息',
        style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
      ),
      trailing: _deleting.contains(id)
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppTheme.textLight,
              tooltip: '删除会话',
              onPressed: () => _confirmDelete(s),
            ),
      onTap: () => widget.onSelect(s),
    );
  }
}
