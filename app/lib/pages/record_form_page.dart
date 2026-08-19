import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/dining_record.dart';
import '../models/district.dart';
import '../models/restaurant.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';

/// 新建/编辑用餐记录。
/// - 新建：传 [restaurant]（已选定餐厅）或留空（页面内选择餐厅/新建餐厅）
/// - 编辑：传 [record]
class RecordFormPage extends StatefulWidget {
  final Restaurant? restaurant;
  final DiningRecord? record;
  const RecordFormPage({super.key, this.restaurant, this.record});

  @override
  State<RecordFormPage> createState() => _RecordFormPageState();
}

class _RecordFormPageState extends State<RecordFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _restaurantCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();
  final _moodCtrl = TextEditingController();
  final _perCapitaCtrl = TextEditingController();

  late DateTime _date = widget.record != null
      ? DateTime.parse(widget.record!.date)
      : DateTime.now();
  int _rating = 4;

  List<District> _districts = [];
  bool _loadingDistricts = true;
  bool _saving = false;

  /// 编辑模式：记录已有的照片（含本次新上传的）
  late final List<RecordPhoto> _existingPhotos =
      _isEdit ? [...?widget.record?.photos] : [];

  /// 新建模式：暂存的本地照片，保存时统一上传
  final List<String> _pendingPhotoPaths = [];

  int? _selectedRestaurantId; // 选择已有餐厅
  int? _selectedNewDistrictId; // 新建餐厅的区
  bool _createNew = false; // 是否新建餐厅

  bool get _isEdit => widget.record != null;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    if (r != null) {
      // 回填餐厅 ID，否则直接保存时后端会因缺少餐厅报 400
      if (r.restaurantId > 0) _selectedRestaurantId = r.restaurantId;
      _restaurantCtrl.text = r.restaurant;
      _commentCtrl.text = r.comment;
      _moodCtrl.text = r.mood;
      _perCapitaCtrl.text = r.perCapita?.toString() ?? '';
      _rating = r.rating;
    } else if (widget.restaurant != null) {
      _restaurantCtrl.text = widget.restaurant!.name;
      _selectedRestaurantId = widget.restaurant!.id;
    }
    _loadOptions();
  }

  @override
  void dispose() {
    _restaurantCtrl.dispose();
    _commentCtrl.dispose();
    _moodCtrl.dispose();
    _perCapitaCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    // 只加载区列表（11 个）；餐厅改为按需搜索，避免拉全量 2 万+ 家卡住页面。
    try {
      final districts = await FoodmapApi.fetchDistricts();
      if (!mounted) return;
      setState(() {
        _districts = districts;
        _loadingDistricts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingDistricts = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('加载选项失败：$e')));
    }
  }

  /// 打开底部搜索面板选已有餐厅，点选后回填。
  Future<void> _pickExistingRestaurant() async {
    final picked = await showModalBottomSheet<Restaurant>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _RestaurantSearchSheet(
        initial: _selectedRestaurantId != null ? _restaurantCtrl.text : '',
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedRestaurantId = picked.id;
      _restaurantCtrl.text = picked.name;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickPhotos() async {
    if (_isEdit && _saving) return;
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(limit: 9);
    if (files.isEmpty) return;
    // 直接上传到当前记录（编辑模式）或暂存路径（新建模式，保存时上传）
    final paths = [for (final f in files) f.path];
    if (_isEdit) {
      try {
        final uploaded = await FoodmapApi.uploadPhotos(widget.record!.id, paths);
        if (!mounted) return;
        setState(() => _existingPhotos.addAll(uploaded));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('照片已上传')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败：$e')));
      }
    } else {
      _pendingPhotoPaths.addAll(paths);
      setState(() {});
    }
  }

  /// 删除已有照片：确认后调后端删除，成功后从本地列表移除
  Future<void> _deletePhoto(RecordPhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这张照片？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FoodmapApi.deletePhoto(photo.id);
      if (!mounted) return;
      setState(() => _existingPhotos.removeWhere((p) => p.id == photo.id));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('照片已删除')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  /// 照片缩略图（90×90，右上角删除按钮）
  Widget _photoThumb({required Key key, required Widget child, required VoidCallback onDelete}) {
    return ClipRRect(
      key: key,
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final dateStr = '${_date.year.toString().padLeft(4, '0')}-'
          '${_date.month.toString().padLeft(2, '0')}-'
          '${_date.day.toString().padLeft(2, '0')}';
      final perCapita = int.tryParse(_perCapitaCtrl.text.trim());

      final DiningRecord saved;
      if (_isEdit) {
        saved = await FoodmapApi.updateRecord(
          widget.record!.id,
          restaurantId: _selectedRestaurantId,
          date: dateStr,
          rating: _rating,
          comment: _commentCtrl.text.trim(),
          perCapita: perCapita,
          mood: _moodCtrl.text.trim(),
        );
      } else if (_selectedRestaurantId != null) {
        saved = await FoodmapApi.createRecord(
          restaurantId: _selectedRestaurantId,
          date: dateStr,
          rating: _rating,
          comment: _commentCtrl.text.trim(),
          perCapita: perCapita,
          mood: _moodCtrl.text.trim(),
        );
      } else {
        saved = await FoodmapApi.createRecord(
          restaurantName: _restaurantCtrl.text.trim(),
          districtId: _selectedNewDistrictId,
          date: dateStr,
          rating: _rating,
          comment: _commentCtrl.text.trim(),
          perCapita: perCapita,
          mood: _moodCtrl.text.trim(),
        );
      }

      // 新建模式：上传暂存照片
      if (!_isEdit && _pendingPhotoPaths.isNotEmpty) {
        try {
          await FoodmapApi.uploadPhotos(saved.id, _pendingPhotoPaths);
        } catch (_) {}
      }

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_isEdit ? '记录已更新' : '记录已保存')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '编辑记录' : '记录一次用餐')),
      body: _loadingDistricts
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ---- 餐厅选择 ----
                  Text('在哪家吃的？',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        RadioGroup<int>(
                          // groupValue 与 RadioListTile 的 value 对齐：
                          // 0=从已有餐厅里选，1=新餐厅录入（此前写反导致高亮与实际逻辑错位）
                          groupValue: _createNew ? 1 : 0,
                          // 编辑模式：餐厅已定，不允许切换
                          onChanged: (v) {
                            if (_isEdit) return;
                            setState(() {
                              _createNew = v == 1;
                              if (_createNew) {
                                _selectedRestaurantId = null;
                                _restaurantCtrl.clear();
                              }
                            });
                          },
                          child: Column(
                            children: [
                              const RadioListTile<int>(
                                value: 0,
                                title: Text('从已有餐厅里选'),
                              ),
                              if (!_createNew)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  child: TextFormField(
                                    controller: _restaurantCtrl,
                                    readOnly: true,
                                    onTap: _pickExistingRestaurant,
                                    decoration: const InputDecoration(
                                      hintText: '搜索或选择餐厅',
                                      prefixIcon: Icon(Icons.search),
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              const RadioListTile<int>(
                                value: 1,
                                title: Text('新餐厅（我来录入）'),
                              ),
                              if (_createNew) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                  child: TextFormField(
                                    controller: _restaurantCtrl,
                                    decoration: const InputDecoration(
                                      labelText: '餐厅名称',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    validator: (v) => (v == null || v.trim().isEmpty)
                                        ? '请填写餐厅名称'
                                        : null,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  child: DropdownButtonFormField<int>(
                                    initialValue: _selectedNewDistrictId,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: '所属区',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    items: [
                                      for (final d in _districts)
                                        DropdownMenuItem(
                                            value: d.id, child: Text(d.name)),
                                    ],
                                    validator: (v) => v == null ? '请选择所属区' : null,
                                    onChanged: (v) =>
                                        setState(() => _selectedNewDistrictId = v),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ---- 日期与评分 ----
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                            '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('评分 ',
                                  style: TextStyle(color: AppTheme.textLight)),
                              for (var i = 1; i <= 5; i++)
                                GestureDetector(
                                  onTap: () => setState(() => _rating = i),
                                  child: Icon(
                                    i <= _rating
                                        ? Icons.star
                                        : Icons.star_border,
                                    size: 24,
                                    color: Colors.orange,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ---- 点评 ----
                  TextFormField(
                    controller: _commentCtrl,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: '点评 / 回忆（写给未来的我们）',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _moodCtrl,
                          decoration: const InputDecoration(
                            labelText: '心情标签（如：超满足）',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _perCapitaCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '人均（元）',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ---- 照片 ----
                  Row(
                    children: [
                      const Text('照片',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _pickPhotos,
                        icon: const Icon(Icons.photo_library_outlined, size: 18),
                        label: Text(_isEdit ? '上传照片' : '选择照片（可多选）'),
                      ),
                    ],
                  ),
                  // 编辑模式：已有照片预览（含本次新上传的），右上角 ✕ 可删除
                  if (_isEdit && _existingPhotos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 90,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _existingPhotos.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final photo = _existingPhotos[i];
                          return _photoThumb(
                            key: ValueKey('photo-${photo.id}'),
                            onDelete: () => _deletePhoto(photo),
                            child: FutureBuilder<String>(
                              future: FoodmapApi.photoUrl(photo.url),
                              builder: (context, snap) => CachedNetworkImage(
                                imageUrl: snap.data ?? '',
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => Container(
                                  color: const Color(0xFFF0EAE4),
                                  child: const Icon(Icons.broken_image,
                                      color: AppTheme.textLight),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  // 新建模式：待上传照片预览，右上角 ✕ 可移除
                  if (_pendingPhotoPaths.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 90,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _pendingPhotoPaths.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) => _photoThumb(
                          key: ValueKey('pending-$i'),
                          onDelete: () =>
                              setState(() => _pendingPhotoPaths.removeAt(i)),
                          child: Image.file(
                            File(_pendingPhotoPaths[i]),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: const Color(0xFFF0EAE4),
                              child: const Icon(Icons.broken_image,
                                  color: AppTheme.textLight),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isEdit ? '保存修改' : '保存这段回忆'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}

/// 底部弹出的餐厅搜索选择器：输入关键词实时搜索（后端限 50 条），点选返回。
class _RestaurantSearchSheet extends StatefulWidget {
  final String initial;
  const _RestaurantSearchSheet({this.initial = ''});

  @override
  State<_RestaurantSearchSheet> createState() => _RestaurantSearchSheetState();
}

class _RestaurantSearchSheetState extends State<_RestaurantSearchSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Restaurant> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.initial;
    if (widget.initial.isNotEmpty) _search(widget.initial);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {}); // 立即刷新清除按钮显隐
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await FoodmapApi.fetchRestaurants(query: q);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '搜索失败：$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: '输入餐厅名关键词，本地没有会实时查高德地图',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onChanged('');
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _results.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  widget.initial.isEmpty
                                      ? '输入关键词搜索餐厅'
                                      : '没有找到匹配的餐厅，试试其他关键词，或选「新餐厅（我来录入）」',
                                  style: const TextStyle(color: AppTheme.textLight),
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _results.length,
                              itemBuilder: (context, i) {
                                final r = _results[i];
                                return ListTile(
                                  title: Text(r.name,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text([
                                    r.district,
                                    if (r.address.isNotEmpty) r.address,
                                    if (r.recordCount > 0) '已记录 ${r.recordCount} 次',
                                  ].join(' · ')),
                                  onTap: () => Navigator.pop(context, r),
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
