import 'package:flutter/material.dart';

import '../models/bucket_item.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';

/// 心愿表单页：新建/编辑想一起做的事。
///
/// 用独立页面而非 AlertDialog——微信等 WKWebView 上 dialog +
/// 键盘的布局不可靠，页面路由最稳，写文案体验也更好。
class BucketFormPage extends StatefulWidget {
  final BucketItem? item; // null = 新建

  const BucketFormPage({super.key, this.item});

  @override
  State<BucketFormPage> createState() => _BucketFormPageState();
}

class _BucketFormPageState extends State<BucketFormPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.item?.title ?? '');
    _descCtrl = TextEditingController(text: widget.item?.description ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标题不能为空')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final item = widget.item;
      if (item == null) {
        await FoodmapApi.createBucketItem(
          title: title,
          description: _descCtrl.text.trim(),
        );
      } else {
        await FoodmapApi.updateBucketItem(
          item.id,
          title: title,
          description: _descCtrl.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.item != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '编辑心愿' : '添加心愿'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: '想一起做的事',
              hintText: '去颐和路踩满地梧桐碎金，接住飘落的秋叶片',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 16),
            maxLength: 100,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descCtrl,
            maxLines: 6,
            minLines: 3,
            decoration: const InputDecoration(
              labelText: '描述 / 文案（可选）',
              hintText: '写点期待：为什么想去、想和谁、什么季节最好…',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(_saving ? '保存中…' : (editing ? '保存修改' : '添加到心愿清单')),
          ),
        ],
      ),
    );
  }
}