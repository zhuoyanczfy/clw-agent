import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';
import '../widgets/cute_widgets.dart';

/// 添加宠物事项：疫苗 / 驱虫 / 体重 / 其他（字段随类型动态变化）。
class PetEventFormPage extends StatefulWidget {
  const PetEventFormPage({super.key, required this.pet, required this.kind});

  final Pet pet;
  final String kind;

  @override
  State<PetEventFormPage> createState() => _PetEventFormPageState();
}

class _PetEventFormPageState extends State<PetEventFormPage> {
  late final TextEditingController _title;
  late final TextEditingController _weight;
  late final TextEditingController _note;
  late String _kind;
  String _date = '';
  String _dueDate = '';
  bool _saving = false;

  static const _kindMeta = {
    PetEvent.kindVaccine: ('💉', '疫苗', '猫三联', '比如：猫三联加强针、狂犬疫苗'),
    PetEvent.kindDeworm: ('🐛', '驱虫', '体内驱虫', '比如：体内驱虫、体外驱虫'),
    PetEvent.kindWeight: ('⚖️', '称体重', '称重', ''),
    PetEvent.kindOther: ('📌', '其他', '', '比如：绝育手术、体检、生日派对'),
  };

  @override
  void initState() {
    super.initState();
    _kind = widget.kind;
    _title = TextEditingController(text: _kindMeta[_kind]!.$3);
    _weight = TextEditingController();
    _note = TextEditingController();
    _date = _today();
  }

  @override
  void dispose() {
    _title.dispose();
    _weight.dispose();
    _note.dispose();
    super.dispose();
  }

  String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate({required bool due}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(due ? _dueDate : _date) ?? now,
      // 日期可以是过去（补记）也可以是未来（预约）
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    final text =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() {
      if (due) {
        _dueDate = text;
      } else {
        _date = text;
      }
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填一下标题～')));
      return;
    }
    double? weight;
    if (_kind == PetEvent.kindWeight) {
      weight = double.tryParse(_weight.text.trim());
      if (weight == null || weight <= 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请填一个有效的体重数字（kg）')));
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await FoodmapApi.addPetEvent(
        widget.pet.id,
        kind: _kind,
        title: title,
        date: _date,
        dueDate: _dueDate,
        weight: weight,
        note: _note.text.trim(),
      );
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
    final meta = _kindMeta[_kind]!;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '记录${meta.$2}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // 类型切换
            Wrap(
              spacing: 10,
              children: [
                for (final entry in _kindMeta.entries)
                  ChoiceChip(
                    avatar: Text(entry.value.$1, style: const TextStyle(fontSize: 16)),
                    label: Text(entry.value.$2),
                    selected: _kind == entry.key,
                    onSelected: (_) => setState(() {
                      _kind = entry.key;
                      if (_title.text.isEmpty) {
                        _title.text = _kindMeta[entry.key]!.$3;
                      }
                    }),
                    selectedColor: const Color(0xFFFFE9E9),
                    labelStyle: TextStyle(
                      fontSize: 13,
                      color: _kind == entry.key
                          ? AppTheme.primaryDark
                          : AppTheme.textLight,
                      fontWeight: _kind == entry.key
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            _label('标题 *'),
            TextField(
              controller: _title,
              decoration: _decoration(
                hint: meta.$4.isEmpty ? '给这条记录起个名字' : meta.$4,
              ),
            ),
            const SizedBox(height: 16),
            _label(_kind == PetEvent.kindWeight ? '称重日期 *' : '日期 *'),
            _dateRow(
              text: _date,
              onTap: () => _pickDate(due: false),
            ),
            if (_kind == PetEvent.kindVaccine || _kind == PetEvent.kindDeworm) ...[
              const SizedBox(height: 16),
              _label('下次到期（选填）'),
              _dateRow(
                text: _dueDate.isEmpty ? '下次什么时候要再打？' : _dueDate,
                onTap: () => _pickDate(due: true),
                onClear: _dueDate.isEmpty
                    ? null
                    : () => setState(() => _dueDate = ''),
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  '到期前 7 天会提醒你，不再错过～',
                  style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                ),
              ),
            ],
            if (_kind == PetEvent.kindWeight) ...[
              const SizedBox(height: 16),
              _label('体重（kg）*'),
              TextField(
                controller: _weight,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _decoration(hint: '比如：4.2').copyWith(
                  suffixText: 'kg',
                ),
              ),
            ],
            const SizedBox(height: 16),
            _label('备注（选填）'),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: _decoration(hint: '还想记点什么？'),
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
                          '保存记录 ${meta.$1}',
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
