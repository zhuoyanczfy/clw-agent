import 'package:flutter/material.dart';

import '../models/plant_bed.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';
import '../widgets/plant_level.dart';
import 'plant_bed_detail_page.dart';
import 'plant_bed_form_page.dart';

/// 花坛：把多株种草组合成一天的游园计划（定一个赏花日，逐站拔草）。
///
/// 坛里的植物引用植物园条目，在哪边拔草状态都同步；全部拔完即"已收获 🧺"。
class PlantBedListPage extends StatefulWidget {
  const PlantBedListPage({super.key});

  @override
  State<PlantBedListPage> createState() => _PlantBedListPageState();
}

class _PlantBedListPageState extends State<PlantBedListPage> {
  List<PlantBed> _beds = [];
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
      final beds = await FoodmapApi.fetchPlantBeds();
      if (!mounted) return;
      setState(() {
        _beds = beds;
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

  Future<void> _addBed() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PlantBedFormPage()),
    );
    if (saved != true) return;
    _load();
  }

  Future<void> _openDetail(PlantBed bed) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlantBedDetailPage(bedId: bed.id)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final ongoing = _beds.where((b) => !b.isHarvested).toList();
    final harvested = _beds.where((b) => b.isHarvested).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('花坛'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addBed,
        tooltip: '垒花坛',
        child: const Icon(Icons.add),
      ),
      body: _buildBody(ongoing, harvested),
    );
  }

  Widget _buildBody(List<PlantBed> ongoing, List<PlantBed> harvested) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppTheme.textLight)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_beds.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Icon(Icons.local_florist_outlined, size: 48, color: AppTheme.textLight),
          SizedBox(height: 12),
          Center(
            child: Text(
              '还没有花坛，点 + 把种过的草垒成一天 🌷',
              style: TextStyle(color: AppTheme.textLight),
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        children: [
          for (final bed in ongoing) ...[
            _buildBedCard(bed),
            const SizedBox(height: 10),
          ],
          if (harvested.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 10),
              child: Text('已收获 🧺',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textLight)),
            ),
            for (final bed in harvested) ...[
              _buildBedCard(bed),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }

  /// 花坛卡片：名称 + 倒计时徽章 + 坛内植物（时段 + emoji + 标题）+ 进度条。
  Widget _buildBedCard(PlantBed bed) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primary.withValues(
              alpha: bed.isHarvested ? 0.28 : 0.55),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openDetail(bed),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🌷', style: TextStyle(fontSize: 22, height: 1.1)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        bed.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _VisitBadge(days: bed.daysUntilVisit),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final m in bed.items) _memberChip(m)],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: bed.total == 0 ? 0 : bed.doneCount / bed.total,
                          minHeight: 6,
                          backgroundColor: Colors.grey[200],
                          valueColor:
                              const AlwaysStoppedAnimation(AppTheme.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      bed.isHarvested ? '满坛收获 🧺' : '已拔 ${bed.doneCount}/${bed.total}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: bed.isHarvested ? FontWeight.w600 : FontWeight.normal,
                        color:
                            bed.isHarvested ? AppTheme.primaryDark : AppTheme.textLight,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 坛内一株植物的小胶囊：时段 + emoji（已拔换 ✅）+ 标题。
  Widget _memberChip(PlantBedMember m) {
    final lv = PlantLevel.of(m.intensity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: lv.color.withValues(alpha: m.isCompleted ? 0.07 : 0.13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: lv.color.withValues(alpha: m.isCompleted ? 0.25 : 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.timeNote.isNotEmpty) ...[
            Text(
              m.timeNote,
              style: TextStyle(
                  fontSize: 11,
                  color: lv.color.withValues(alpha: m.isCompleted ? 0.7 : 1)),
            ),
            const SizedBox(width: 3),
          ],
          Text(m.isCompleted ? '✅' : lv.emoji,
              style: const TextStyle(fontSize: 13, height: 1.1)),
          const SizedBox(width: 3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              m.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                decoration: m.isCompleted ? TextDecoration.lineThrough : null,
                color:
                    m.isCompleted ? AppTheme.textLight : AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 赏花日倒计时徽章：没定灰 / 未来绿 / 今天金 / 过期暗。
class _VisitBadge extends StatelessWidget {
  final int? days;

  const _VisitBadge({required this.days});

  @override
  Widget build(BuildContext context) {
    final (text, fg, bg) = switch (days) {
      null => ('日子待定', AppTheme.textLight, Colors.grey.withValues(alpha: 0.14)),
      0 => ('今天游园 🌿', Colors.white, AppTheme.primary),
      > 0 => (
          '还有 $days 天',
          const Color(0xFF43A047),
          const Color(0xFF43A047).withValues(alpha: 0.13)
        ),
      _ => (
          '过花季了',
          AppTheme.textLight,
          Colors.grey.withValues(alpha: 0.14)
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: fg, height: 1.2),
      ),
    );
  }
}
