import 'package:flutter/material.dart';

import '../models/bucket_item.dart';
import '../models/plant_bed.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';
import '../widgets/plant_level.dart';

/// 已选入坛的一株植物（时段备注可变）。
class _Picked {
  final BucketItem item;
  String timeNote;

  _Picked(this.item, this.timeNote);
}

/// 垒花坛表单页：起名 → 定赏花日 → 从"生长中"勾选植物 → 排游园顺序和时段。
///
/// 延续独立页面路由（微信 WKWebView 上 dialog + 键盘不可靠）。
class PlantBedFormPage extends StatefulWidget {
  final PlantBed? bed; // null = 新建

  const PlantBedFormPage({super.key, this.bed});

  @override
  State<PlantBedFormPage> createState() => _PlantBedFormPageState();
}

class _PlantBedFormPageState extends State<PlantBedFormPage> {
  static const _timeNotes = ['早上', '上午', '中午', '下午', '傍晚', '晚上'];

  late final TextEditingController _titleCtrl;
  String _visitDate = ''; // YYYY-MM-DD，空 = 还没定
  List<_Picked> _picked = [];
  List<BucketItem> _candidates = [];
  bool _loadingCandidates = true;
  bool _saving = false;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    final bed = widget.bed;
    _titleCtrl = TextEditingController(text: bed?.title ?? '');
    _visitDate = bed?.visitDate ?? '';
    _loadCandidates();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  /// 候选 = 植物园"生长中"的草（等级高的在前）；编辑时已入坛的已拔草成员单独保留。
  Future<void> _loadCandidates() async {
    try {
      final items = await FoodmapApi.fetchBucketList();
      if (!mounted) return;
      setState(() {
        _candidates =
            items.where((i) => !i.isCompleted).toList();
        if (widget.bed != null) {
          // 编辑：按坛内现有成员恢复顺序与时段（已拔草的成员不在候选里，只出现在已选区）
          _picked = [
            for (final m in widget.bed!.items)
              _Picked(
                BucketItem(
                  id: m.itemId,
                  title: m.title,
                  intensity: m.intensity,
                  isCompleted: m.isCompleted,
                ),
                m.timeNote,
              )
          ];
        }
        _loadingCandidates = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingCandidates = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('拉取植物园失败：$e')));
    }
  }

  void _toggle(BucketItem item) {
    setState(() {
      final idx = _picked.indexWhere((p) => p.item.id == item.id);
      if (idx >= 0) {
        _picked.removeAt(idx);
      } else {
        _picked.add(_Picked(item, ''));
      }
    });
  }

  void _move(int idx, int delta) {
    final target = idx + delta;
    if (target < 0 || target >= _picked.length) return;
    setState(() {
      final p = _picked.removeAt(idx);
      _picked.insert(target, p);
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_visitDate) ??
        now.add(const Duration(days: 1));
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: '选赏花日',
    );
    if (d == null) return;
    final iso =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    setState(() => _visitDate = iso);
  }

  Future<void> _pickTimeNote(_Picked p) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('几点去？',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _timeNotes)
                    ActionChip(
                      label: Text(t),
                      backgroundColor: t == p.timeNote
                          ? AppTheme.primary.withValues(alpha: 0.25)
                          : null,
                      onPressed: () => Navigator.pop(ctx, t),
                    ),
                  ActionChip(
                    label: const Text('不填'),
                    onPressed: () => Navigator.pop(ctx, ''),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null) return;
    setState(() => p.timeNote = chosen);
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = '给这一天起个名字吧（灰字只是示例）');
      return;
    }
    if (_picked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('花坛里至少要种一株植物 🌱')),
      );
      return;
    }
    setState(() {
      _titleError = null;
      _saving = true;
    });
    final members = [
      for (final p in _picked) (itemId: p.item.id, timeNote: p.timeNote),
    ];
    try {
      final bed = widget.bed;
      if (bed == null) {
        await FoodmapApi.createPlantBed(
            title: title, visitDate: _visitDate, members: members);
      } else {
        await FoodmapApi.updatePlantBed(
          bed.id,
          title: title,
          visitDate: _visitDate,
          members: members,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.bed != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '编辑花坛' : '垒花坛'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存',
                    style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _titleCtrl,
            onChanged: (_) {
              if (_titleError != null) setState(() => _titleError = null);
            },
            decoration: InputDecoration(
              labelText: '花坛名称',
              hintText: '例如：金陵秋日漫步',
              errorText: _titleError,
              border: const OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 16),
            maxLength: 30,
          ),
          const SizedBox(height: 12),
          // 赏花日
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: '赏花日（可选）',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.event_outlined),
                suffixIcon: Icon(Icons.edit_calendar_outlined),
              ),
              child: Text(
                _visitDate.isEmpty ? '还没定，点这里选一天' : _visitDate,
                style: TextStyle(
                  fontSize: 15,
                  color: _visitDate.isEmpty
                      ? AppTheme.textLight
                      : AppTheme.textDark,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '坛里的植物（${_picked.length} 株 · 游园顺序）',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text('用 ↑ ↓ 调整一天里的先后，点时段写几点去',
              style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
          const SizedBox(height: 10),
          if (_picked.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('还没选植物，从下面勾选想一起做的事',
                    style: TextStyle(color: AppTheme.textLight)),
              ),
            )
          else
            for (var i = 0; i < _picked.length; i++) _pickedTile(i),
          const SizedBox(height: 24),
          const Text('植物园 · 生长中',
              style:
                  TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('勾选种进花坛（已拔草的不能再入坛）',
              style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
          const SizedBox(height: 8),
          if (_loadingCandidates)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_candidates.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('还没有生长中的植物，先回植物园种草吧 🌱',
                    style: TextStyle(color: AppTheme.textLight)),
              ),
            )
          else
            for (final item in _candidates) _candidateTile(item),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
                _saving ? '保存中…' : (editing ? '保存修改' : '垒好花坛 🌷')),
          ),
        ],
      ),
    );
  }

  /// 已选区一行：序号 + 植物 + 时段 chip + ↑ ↓ 移除。
  Widget _pickedTile(int idx) {
    final p = _picked[idx];
    final lv = PlantLevel.of(p.item.intensity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text('${idx + 1}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textLight)),
          ),
          const SizedBox(width: 4),
          Text(lv.emoji, style: const TextStyle(fontSize: 18, height: 1.1)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              p.item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: p.item.isCompleted ? AppTheme.textLight : AppTheme.textDark,
                decoration:
                    p.item.isCompleted ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 4),
          ActionChip(
            visualDensity: VisualDensity.compact,
            label: Text(
              p.timeNote.isEmpty ? '时段' : p.timeNote,
              style: TextStyle(
                fontSize: 12,
                color: p.timeNote.isEmpty
                    ? AppTheme.textLight
                    : AppTheme.primaryDark,
              ),
            ),
            onPressed: () => _pickTimeNote(p),
          ),
          _miniIcon(Icons.arrow_upward, enabled: idx > 0,
              onTap: () => _move(idx, -1)),
          _miniIcon(Icons.arrow_downward,
              enabled: idx < _picked.length - 1, onTap: () => _move(idx, 1)),
          _miniIcon(Icons.close, onTap: () => _toggle(p.item)),
        ],
      ),
    );
  }

  /// 候选区一行：勾选框 + 小徽章 + 标题。
  Widget _candidateTile(BucketItem item) {
    final checked = _picked.any((p) => p.item.id == item.id);
    return CheckboxListTile(
      value: checked,
      onChanged: (_) => _toggle(item),
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Text(PlantLevel.of(item.intensity).emoji,
              style: const TextStyle(fontSize: 17, height: 1.1)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniIcon(IconData icon, {bool enabled = true, VoidCallback? onTap}) {
    return SizedBox(
      width: 28,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: enabled ? onTap : null,
        icon: Icon(icon,
            size: 16,
            color: enabled ? AppTheme.textLight : Colors.grey[300]),
      ),
    );
  }
}
