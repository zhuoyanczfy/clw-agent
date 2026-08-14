import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/pet.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';
import '../widgets/cute_widgets.dart';

/// 宠物档案表单：创建（pet 为 null）或编辑。
class PetFormPage extends StatefulWidget {
  const PetFormPage({super.key, this.pet});

  final Pet? pet;

  @override
  State<PetFormPage> createState() => _PetFormPageState();
}

class _PetFormPageState extends State<PetFormPage> {
  late final TextEditingController _name;
  late final TextEditingController _breed;
  late final TextEditingController _notes;
  String _gender = '';
  String _birthday = '';
  String _adoptDate = '';
  String? _avatarPath; // 新选择的头像本地路径（null = 不换）
  bool _saving = false;

  bool get _isEdit => widget.pet != null;

  @override
  void initState() {
    super.initState();
    final pet = widget.pet;
    _name = TextEditingController(text: pet?.name ?? '');
    _breed = TextEditingController(text: pet?.breed ?? '');
    _notes = TextEditingController(text: pet?.notes ?? '');
    _gender = pet?.gender ?? '';
    _birthday = pet?.birthday ?? '';
    _adoptDate = pet?.adoptDate ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool birthday}) async {
    final initial = DateTime.tryParse(birthday ? _birthday : _adoptDate) ??
        DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    final text =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() {
      if (birthday) {
        _birthday = text;
      } else {
        _adoptDate = text;
      }
    });
  }

  Future<void> _pickAvatar() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (file != null) setState(() => _avatarPath = file.path);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先填猫咪的名字～')));
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await FoodmapApi.updatePet(
          widget.pet!.id,
          name: name,
          breed: _breed.text.trim(),
          gender: _gender,
          birthday: _birthday,
          adoptDate: _adoptDate,
          notes: _notes.text.trim(),
          avatarPath: _avatarPath,
        );
      } else {
        await FoodmapApi.createPet(
          name: name,
          breed: _breed.text.trim(),
          gender: _gender,
          birthday: _birthday,
          adoptDate: _adoptDate,
          notes: _notes.text.trim(),
          avatarPath: _avatarPath,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEdit ? '编辑猫咪档案' : '创建猫咪名片',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // 头像选择
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFF3D6),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _avatarPath != null
                      ? Image.file(
                          File(_avatarPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _avatarEmpty(),
                        )
                      : _avatarFromRemote(),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text(
                '点击更换头像',
                style: TextStyle(fontSize: 12, color: AppTheme.textLight),
              ),
            ),
            const SizedBox(height: 20),
            _label('名字 *'),
            _field(
              _name,
              hint: '比如：团子、年糕、咪咪',
              icon: Icons.pets_outlined,
            ),
            const SizedBox(height: 16),
            _label('品种'),
            _field(
              _breed,
              hint: '比如：英短银渐层、布偶、中华田园猫',
              icon: Icons.category_outlined,
            ),
            const SizedBox(height: 16),
            _label('性别'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: [
                _genderChip('', '保密'),
                _genderChip('female', '妹妹'),
                _genderChip('male', '弟弟'),
              ],
            ),
            const SizedBox(height: 16),
            _label('生日'),
            _dateRow(
              text: _birthday.isEmpty ? '未知（捡来的小可爱可留空）' : _birthday,
              onTap: () => _pickDate(birthday: true),
              onClear: _birthday.isEmpty
                  ? null
                  : () => setState(() => _birthday = ''),
            ),
            const SizedBox(height: 16),
            _label('来家纪念日'),
            _dateRow(
              text: _adoptDate.isEmpty ? '哪天来到这个家的？' : _adoptDate,
              onTap: () => _pickDate(birthday: false),
              onClear: _adoptDate.isEmpty
                  ? null
                  : () => setState(() => _adoptDate = ''),
            ),
            const SizedBox(height: 16),
            _label('备注'),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: _decoration(
                hint: '爱吃的、怕的、小习惯…都可以记下来',
              ),
            ),
            const SizedBox(height: 32),
            SquishyTap(
              borderRadius: BorderRadius.circular(30),
              onTap: _saving ? null : _save,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primary, AppTheme.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isEdit ? '保存修改' : '创建名片 🐾',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarEmpty() {
    return const Center(child: Text('🐱', style: TextStyle(fontSize: 46)));
  }

  Widget _avatarFromRemote() {
    final pet = widget.pet;
    if (pet == null || pet.avatar.isEmpty) return _avatarEmpty();
    return FutureBuilder<String>(
      future: FoodmapApi.photoUrl(pet.avatar),
      builder: (context, snapshot) {
        final url = snapshot.data ?? '';
        if (url.isEmpty) return _avatarEmpty();
        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _avatarEmpty(),
        );
      },
    );
  }

  Widget _genderChip(String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _gender == value,
      onSelected: (_) => setState(() => _gender = value),
      selectedColor: const Color(0xFFFFF3D6),
      labelStyle: TextStyle(
        fontSize: 14,
        color: _gender == value ? AppTheme.primaryDark : AppTheme.textLight,
        fontWeight: _gender == value ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: AppTheme.textDark,
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller, {
    required String hint,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      decoration: _decoration(hint: hint).copyWith(prefixIcon: Icon(icon)),
    );
  }

  InputDecoration _decoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 14, color: AppTheme.textLight),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _dateRow({
    required String text,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final isEmpty = onClear == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 20,
              color: AppTheme.textLight,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  color: isEmpty ? AppTheme.textLight : AppTheme.textDark,
                ),
              ),
            ),
            if (!isEmpty)
              GestureDetector(
                onTap: onClear,
                child: const Icon(
                  Icons.cancel,
                  size: 18,
                  color: AppTheme.textLight,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
