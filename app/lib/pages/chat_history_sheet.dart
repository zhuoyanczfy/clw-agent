import 'package:flutter/material.dart';

import '../theme.dart';

/// 历史会话列表底部弹层：切换/删除/新建会话。
class ChatHistorySheet extends StatefulWidget {
  final List<Map<String, dynamic>> sessions;
  final int? currentId;
  final void Function(Map<String, dynamic> session) onSelect;
  final Future<void> Function(Map<String, dynamic> session) onDelete;
  final VoidCallback onNew;

  const ChatHistorySheet({
    super.key,
    required this.sessions,
    required this.currentId,
    required this.onSelect,
    required this.onDelete,
    required this.onNew,
  });

  @override
  State<ChatHistorySheet> createState() => _ChatHistorySheetState();
}

class _ChatHistorySheetState extends State<ChatHistorySheet> {
  late final List<Map<String, dynamic>> _sessions = [
    ...widget.sessions,
  ];
  final Set<int> _deleting = {};

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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
            const SizedBox(height: 4),
            if (_sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    '还没有历史会话',
                    style: TextStyle(color: AppTheme.textLight, fontSize: 13),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _sessions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = _sessions[i];
                    final id = s['id'] as int;
                    final title = (s['title'] ?? '').toString();
                    final count = s['message_count'] ?? 0;
                    final updated = (s['updated_at'] ?? '').toString();
                    final isCurrent = id == widget.currentId;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isCurrent ? Icons.chat_bubble : Icons.chat_bubble_outline,
                        color: isCurrent
                            ? AppTheme.primary
                            : AppTheme.textLight,
                      ),
                      title: Text(
                        title.isEmpty ? '未命名会话' : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isCurrent ? FontWeight.w600 : FontWeight.w400,
                          color: AppTheme.textDark,
                        ),
                      ),
                      subtitle: Text(
                        '$updated · $count 条消息',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textLight,
                        ),
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
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
