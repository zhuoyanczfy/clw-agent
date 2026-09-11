import 'package:flutter/material.dart';

import '../models/plant_bed.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';
import '../widgets/plant_level.dart';
import 'plant_bed_form_page.dart';

/// 花坛详情 · 游园清单：按顺序逐站拔草（复用植物园拔草，状态两边同步），
/// 全部拔完即"满坛收获 🧺"。
class PlantBedDetailPage extends StatefulWidget {
  final int bedId;

  const PlantBedDetailPage({super.key, required this.bedId});

  @override
  State<PlantBedDetailPage> createState() => _PlantBedDetailPageState();
}

class _PlantBedDetailPageState extends State<PlantBedDetailPage> {
  PlantBed? _bed;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bed = await FoodmapApi.fetchPlantBed(widget.bedId);
      if (!mounted) return;
      setState(() {
        _bed = bed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _edit() async {
    final bed = _bed;
    if (bed == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PlantBedFormPage(bed: bed)),
    );
    if (saved != true) return;
    _load();
  }

  Future<void> _deleteBed() async {
    final bed = _bed;
    if (bed == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('拆掉「${bed.title}」？'),
        content: const Text('花坛拆掉就没了，坛里的植物会回到植物园，不受影响 🌱'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('拆掉', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FoodmapApi.deletePlantBed(bed.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  /// 游园清单里给一站拔草（复用植物园的拔草弹窗，可顺手写手记）。
  Future<void> _markComplete(PlantBedMember m) async {
    final memoryCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('拔草啦！'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('「${m.title}」\n写下拔草那天的回忆吧～',
                style: const TextStyle(height: 1.5)),
            const SizedBox(height: 12),
            TextField(
              controller: memoryCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '拔草手记（可选）',
                hintText: '秋天的阳光正好，落叶踩起来沙沙响…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('还没实现'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('拔草！'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await FoodmapApi.updateBucketItem(
        m.itemId,
        isCompleted: true,
        memoryText: memoryCtrl.text.trim(),
      );
      await _load();
      if (!mounted) return;
      final bed = _bed;
      if (bed != null && bed.isHarvested) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('满坛收获！这一天过得真完整 🧺')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _unmarkComplete(PlantBedMember m) async {
    try {
      await FoodmapApi.updateBucketItem(m.itemId, isCompleted: false);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('游园'),
        actions: [
          IconButton(
            onPressed: _bed == null ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑花坛',
          ),
          IconButton(
            onPressed: _bed == null ? null : _deleteBed,
            icon: const Icon(Icons.delete_outline),
            tooltip: '拆掉花坛',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _bed == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? '花坛不存在',
                style: const TextStyle(color: AppTheme.textLight)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final bed = _bed!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildHeader(bed),
          const SizedBox(height: 16),
          for (var i = 0; i < bed.items.length; i++) ...[
            _buildStop(bed.items[i], i, bed.items.length),
            if (i < bed.items.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Container(
                  width: 2,
                  height: 10,
                  color: AppTheme.primary.withValues(alpha: 0.35),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 头部：名称 + 赏花日 + 倒计时 + 进度（全拔完显示满坛收获）。
  Widget _buildHeader(PlantBed bed) {
    final days = bed.daysUntilVisit;
    final visitText = bed.visitDate.isEmpty
        ? '赏花日还没定，编辑花坛选一天吧'
        : '赏花日：${bed.visitDate}';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppTheme.primary.withValues(alpha: bed.isHarvested ? 0.28 : 0.55),
            width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🌷', style: TextStyle(fontSize: 30, height: 1.1)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  bed.title,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w700, height: 1.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.event_outlined,
                  size: 15, color: AppTheme.textLight),
              const SizedBox(width: 4),
              Expanded(
                child: Text(visitText,
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textLight)),
              ),
              if (days != null && !bed.isHarvested)
                Text(
                  days == 0
                      ? '今天游园 🌿'
                      : days > 0
                          ? '还有 $days 天'
                          : '过花季了',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: days == 0
                        ? AppTheme.primaryDark
                        : days > 0
                            ? const Color(0xFF43A047)
                            : AppTheme.textLight,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: bed.total == 0 ? 0 : bed.doneCount / bed.total,
                    minHeight: 7,
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                bed.isHarvested ? '满坛收获 🧺' : '已拔 ${bed.doneCount}/${bed.total}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: bed.isHarvested ? FontWeight.w700 : FontWeight.normal,
                  color: bed.isHarvested ? AppTheme.primaryDark : AppTheme.textLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 游园清单的一站。
  Widget _buildStop(PlantBedMember m, int idx, int total) {
    final lv = PlantLevel.of(m.intensity);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: lv.color.withValues(alpha: m.isCompleted ? 0.25 : 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 站点序号 / 已拔打勾
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: m.isCompleted
                    ? AppTheme.primary.withValues(alpha: 0.16)
                    : lv.color.withValues(alpha: 0.13),
              ),
              child: m.isCompleted
                  ? const Icon(Icons.check, size: 16, color: AppTheme.primaryDark)
                  : Text(
                      '${idx + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: lv.color,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            // 时段 + 徽章 + 标题 + 手记预览
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (m.timeNote.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(m.timeNote,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primaryDark)),
                        ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: PlantBadge(level: m.intensity, scale: 0.78),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    m.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      decoration:
                          m.isCompleted ? TextDecoration.lineThrough : null,
                      color:
                          m.isCompleted ? AppTheme.textLight : AppTheme.textDark,
                    ),
                  ),
                  if (m.isCompleted && m.completedAt.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('拔草于 ${m.completedAt}',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textLight)),
                    ),
                  if (m.isCompleted && m.memoryText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        m.memoryText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textLight,
                            fontStyle: FontStyle.italic,
                            height: 1.4),
                      ),
                    ),
                ],
              ),
            ),
            // 拔草 / 重新种下
            m.isCompleted
                ? IconButton(
                    onPressed: () => _unmarkComplete(m),
                    icon: const Icon(Icons.undo,
                        size: 20, color: AppTheme.textLight),
                    tooltip: '重新种下',
                  )
                : IconButton(
                    onPressed: () => _markComplete(m),
                    icon: Icon(Icons.check_circle_outline,
                        size: 22, color: lv.color),
                    tooltip: '拔草',
                  ),
          ],
        ),
      ),
    );
  }
}
