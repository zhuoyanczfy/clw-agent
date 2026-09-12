import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/bucket_item.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';
import '../widgets/plant_level.dart';
import 'bucket_form_page.dart';
import 'plant_bed_list_page.dart';

/// 植物园：想一起做的事，可种草/种花/种树分级，拔草（完成）、附照片和手记。
class BucketListPage extends StatefulWidget {
  const BucketListPage({super.key});

  @override
  State<BucketListPage> createState() => _BucketListPageState();
}

class _BucketListPageState extends State<BucketListPage> {
  List<BucketItem> _items = [];
  bool _loading = true;
  String? _error;
  bool _showCompleted = false;

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
      final items = await FoodmapApi.fetchBucketList();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _addItem() async {
    // 用独立页面而非 AlertDialog：微信等 WKWebView 上 dialog + 键盘布局不可靠
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BucketFormPage()),
    );
    if (saved != true) return;
    _load();
  }

  Future<void> _showDetail(BucketItem item) async {
    // 重新拉取最新数据（含照片）
    BucketItem refreshed;
    try {
      final json = await FoodmapApi.fetchBucketList();
      refreshed = json.firstWhere((i) => i.id == item.id);
    } catch (_) {
      refreshed = item;
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _BucketDetailSheet(
        item: refreshed,
        onChanged: () => _load(),
      ),
    );
  }

  Future<void> _deleteItem(BucketItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('让「${item.title}」枯萎？'),
        content: const Text('不想要了，就让 Ta 从植物园里枯萎吧 🥀'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('枯萎 🥀', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FoodmapApi.deleteBucketItem(item.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _items.where((i) => !i.isCompleted).toList();
    final completed = _items.where((i) => i.isCompleted).toList();
    // 想实现程度从高到低（树→花→草）；后端已排序，这里再兜底一次
    pending.sort((a, b) => b.intensity.compareTo(a.intensity));
    completed.sort((a, b) => b.intensity.compareTo(a.intensity));
    return Scaffold(
      appBar: AppBar(
        title: const Text('植物园'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PlantBedListPage()),
            ),
            icon: const Icon(Icons.local_florist),
            tooltip: '花坛',
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addItem,
        tooltip: '种草',
        child: const Icon(Icons.add),
      ),
      body: _buildBody(pending, completed),
    );
  }

  Widget _buildBody(List<BucketItem> pending, List<BucketItem> completed) {
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _SegBtn(
                  label: '生长中（${pending.length}）',
                  selected: !_showCompleted,
                  onTap: () => setState(() => _showCompleted = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SegBtn(
                  label: '已拔草（${completed.length}）',
                  selected: _showCompleted,
                  onTap: () => setState(() => _showCompleted = true),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _showCompleted ? _buildList(completed, true) : _buildList(pending, false),
          ),
        ),
      ],
    );
  }

  Widget _buildList(List<BucketItem> items, bool completedMode) {
    if (items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Icon(
            completedMode ? Icons.celebration_outlined : Icons.eco_outlined,
            size: 48,
            color: AppTheme.textLight,
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              completedMode ? '还没有拔草记录，一起去实现吧～' : '点 + 种下第一个想一起做的事 🌱',
              style: const TextStyle(color: AppTheme.textLight),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildCard(items[index], completedMode),
    );
  }

  /// 单张卡片：边框粗细 / 左侧色条 / 光晕随「想实现程度」升级（草→花→树），
  /// 标题上方展示 PlantBadge；操作按钮为拔草 / 重新种下。
  Widget _buildCard(BucketItem item, bool completedMode) {
    final lv = PlantLevel.of(item.intensity);

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 状态图标
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 10),
          child: Icon(
            item.isCompleted ? Icons.favorite : Icons.radio_button_unchecked,
            color: item.isCompleted ? AppTheme.accent : AppTheme.textLight,
            size: 22,
          ),
        ),
        // 徽章 + 标题 + 描述 + 照片
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: PlantBadge(level: item.intensity, scale: 0.9),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                item.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              if (item.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textLight,
                    ),
                  ),
                ),
              if (item.photos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.photo_library_outlined,
                          size: 14, color: AppTheme.textLight),
                      const SizedBox(width: 4),
                      Text(
                        '${item.photos.length} 张照片',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textLight),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // 操作按钮：拔草 / 重新种下
        completedMode
            ? IconButton(
                onPressed: () => _unmarkComplete(item),
                icon: const Icon(Icons.undo, color: AppTheme.textLight),
                tooltip: '重新种下',
              )
            : IconButton(
                onPressed: () => _markComplete(item),
                icon: const Icon(Icons.check_circle_outline,
                    color: AppTheme.primaryDark),
                tooltip: '拔草',
              ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: lv.color.withValues(alpha: lv.borderWidth >= 3 ? 0.85 : 0.5),
          width: lv.borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: lv.glow
                ? lv.color.withValues(alpha: 0.28)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: lv.glow ? 10 : 6,
            spreadRadius: lv.glow ? 0.4 : 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20 - lv.borderWidth),
        child: Stack(
          children: [
            // 左侧色条（等级越高越宽）
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: lv.barWidth, color: lv.color),
            ),
            InkWell(
              onTap: () => _showDetail(item),
              onLongPress: () => _deleteItem(item),
              child: Padding(
                padding: EdgeInsets.fromLTRB(12 + lv.barWidth, 14, 8, 14),
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markComplete(BucketItem item) async {
    // 弹窗让写拔草手记
    final memoryCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('拔草啦！'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('「${item.title}」\n写下拔草那天的回忆吧～',
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
        item.id,
        isCompleted: true,
        memoryText: memoryCtrl.text.trim(),
      );
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('拔草成功！又一起实现了一件想做的事 🌿')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _unmarkComplete(BucketItem item) async {
    try {
      await FoodmapApi.updateBucketItem(item.id, isCompleted: false);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

/// 详情底部弹出框（含照片、回忆、编辑）
class _BucketDetailSheet extends StatefulWidget {
  final BucketItem item;
  final VoidCallback onChanged;

  const _BucketDetailSheet({required this.item, required this.onChanged});

  @override
  State<_BucketDetailSheet> createState() => _BucketDetailSheetState();
}

class _BucketDetailSheetState extends State<_BucketDetailSheet> {
  late BucketItem _item;
  late TextEditingController _memoryCtrl;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _memoryCtrl = TextEditingController(text: _item.memoryText);
  }

  @override
  void dispose() {
    _memoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (picked.isEmpty) return;
    if (!mounted) return;
    setState(() => _uploading = true);
    try {
      final photos = await FoodmapApi.uploadBucketPhotos(
        _item.id,
        picked.map((x) => XFile(x.path)).toList(),
      );
      if (!mounted) return;
      setState(() {
        _item = BucketItem(
          id: _item.id,
          title: _item.title,
          description: _item.description,
          category: _item.category,
          intensity: _item.intensity,
          sortOrder: _item.sortOrder,
          isCompleted: _item.isCompleted,
          completedAt: _item.completedAt,
          memoryText: _item.memoryText,
          photos: [..._item.photos, ...photos],
          createdAt: _item.createdAt,
          updatedAt: _item.updatedAt,
        );
        _uploading = false;
      });
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _deletePhoto(int photoId) async {
    try {
      await FoodmapApi.deleteBucketPhoto(photoId);
      if (!mounted) return;
      setState(() {
        _item = BucketItem(
          id: _item.id,
          title: _item.title,
          description: _item.description,
          category: _item.category,
          intensity: _item.intensity,
          sortOrder: _item.sortOrder,
          isCompleted: _item.isCompleted,
          completedAt: _item.completedAt,
          memoryText: _item.memoryText,
          photos: _item.photos.where((p) => p.id != photoId).toList(),
          createdAt: _item.createdAt,
          updatedAt: _item.updatedAt,
        );
      });
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BucketFormPage(item: _item)),
    );
    if (saved != true || !mounted) return;
    // 重新拉取这一条：标题/描述/想实现程度可能已改
    try {
      final items = await FoodmapApi.fetchBucketList();
      final refreshed = items.firstWhere((i) => i.id == _item.id);
      setState(() => _item = refreshed);
    } catch (_) {}
    widget.onChanged();
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('让「${_item.title}」枯萎？'),
        content: const Text('不想要了，就让 Ta 从植物园里枯萎吧 🥀'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('枯萎 🥀', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await FoodmapApi.deleteBucketItem(_item.id);
      widget.onChanged();
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭详情弹窗
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _saveMemory() async {
    final text = _memoryCtrl.text.trim();
    if (text == _item.memoryText) return;
    try {
      await FoodmapApi.updateBucketItem(_item.id, memoryText: text);
      if (!mounted) return;
      setState(() => _item = BucketItem(
            id: _item.id,
            title: _item.title,
            description: _item.description,
            category: _item.category,
            intensity: _item.intensity,
            sortOrder: _item.sortOrder,
            isCompleted: _item.isCompleted,
            completedAt: _item.completedAt,
            memoryText: text,
            photos: _item.photos,
            createdAt: _item.createdAt,
            updatedAt: _item.updatedAt,
          ));
      widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('手记已保存')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: ListView(
          controller: scrollController,
          children: [
            // 拖拽指示条
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 想实现程度徽章
            Align(
              alignment: Alignment.centerLeft,
              child: PlantBadge(level: _item.intensity, scale: 1.1),
            ),
            const SizedBox(height: 12),
            // 标题 + 状态
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _item.title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                Icon(
                  _item.isCompleted ? Icons.favorite : Icons.radio_button_unchecked,
                  color: _item.isCompleted ? AppTheme.accent : AppTheme.textLight,
                  size: 28,
                ),
              ],
            ),
            if (_item.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_item.description,
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textLight, height: 1.5)),
            ],
            if (_item.completedAt.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('拔草时间：${_item.completedAt.substring(0, 10)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textLight)),
            ],
            // 拔草手记
            if (_item.isCompleted) ...[
              const SizedBox(height: 16),
              const Text('拔草手记',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 8),
              TextField(
                controller: _memoryCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: '写下拔草那天的回忆…',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: _saveMemory,
                  child: const Text('保存手记'),
                ),
              ),
            ],
            // 照片区域
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('照片',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const Spacer(),
                if (_uploading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (!_uploading)
                  TextButton.icon(
                    onPressed: _addPhotos,
                    icon: const Icon(Icons.add_a_photo, size: 18),
                    label: const Text('添加照片'),
                  ),
              ],
            ),
            if (_item.photos.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text('还没有照片，点「添加照片」记录这一刻',
                      style: TextStyle(color: AppTheme.textLight)),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _item.photos.length,
                itemBuilder: (context, index) {
                  final photo = _item.photos[index];
                  return GestureDetector(
                    onLongPress: () => _deletePhoto(photo.id),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        photo.url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: Colors.grey[200],
                          child: const Icon(Icons.broken_image,
                              color: AppTheme.textLight),
                        ),
                      ),
                    ),
                  );
                },
              ),
            // 修改 / 枯萎 操作
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _edit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('修改'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Colors.red),
                    label: const Text('枯萎', style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// 分段切换按钮
class _SegBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? Colors.white : AppTheme.textDark,
            ),
          ),
        ),
      ),
    );
  }
}