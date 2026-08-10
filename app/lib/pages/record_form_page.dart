import 'dart:io';

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
  List<Restaurant> _restaurants = [];
  bool _loadingDistricts = true;
  bool _saving = false;

  int? _selectedRestaurantId; // 选择已有餐厅
  int? _selectedNewDistrictId; // 新建餐厅的区
  bool _createNew = false; // 是否新建餐厅

  bool get _isEdit => widget.record != null;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    if (r != null) {
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
    try {
      final results = await Future.wait([
        FoodmapApi.fetchDistricts(),
        FoodmapApi.fetchRestaurants(),
      ]);
      if (!mounted) return;
      setState(() {
        _districts = results[0] as List<District>;
        _restaurants = results[1] as List<Restaurant>;
        _loadingDistricts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingDistricts = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('加载选项失败：$e')));
    }
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
        await FoodmapApi.uploadPhotos(widget.record!.id, paths);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('照片已上传')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败：$e')));
      }
    } else {
      _pendingPhotoPaths = [..._pendingPhotoPaths, ...paths];
      setState(() {});
    }
  }

  List<String> _pendingPhotoPaths = [];

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
                          groupValue: _createNew ? 0 : 1,
                          // 编辑模式：餐厅已定，不允许切换
                          onChanged: (v) {
                            if (_isEdit) return;
                            setState(() => _createNew = v == 1);
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
                                  child: DropdownButtonFormField<int>(
                                    initialValue: _selectedRestaurantId,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      hintText: '搜索或选择餐厅',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    items: [
                                      for (final r in _restaurants)
                                        DropdownMenuItem(
                                          value: r.id,
                                          child: Text(
                                            '${r.name}（${r.district}）',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                    onChanged: (v) => setState(() => _selectedRestaurantId = v),
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
                  if (_pendingPhotoPaths.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 90,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _pendingPhotoPaths.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) => ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(_pendingPhotoPaths[i]),
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 90,
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
