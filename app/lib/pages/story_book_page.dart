import 'package:flutter/material.dart';

import '../models/story.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';

/// 故事书：分类横条 + 故事列表 + 「随机来一篇」。
/// 从首页卡片进入，底部导航调整列入后续待办。
class StoryBookPage extends StatefulWidget {
  const StoryBookPage({super.key});

  @override
  State<StoryBookPage> createState() => _StoryBookPageState();
}

class _StoryBookPageState extends State<StoryBookPage> {
  List<String> _categories = const [];
  String? _selected;
  List<Story> _stories = const [];
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
      final results = await Future.wait([
        FoodmapApi.fetchStoryCategories().catchError((_) => const <String>[]),
        FoodmapApi.fetchStories(category: _selected),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<String>;
        _stories = results[1] as List<Story>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _selectCategory(String? category) {
    if (_selected == category) return;
    setState(() => _selected = category);
    _load();
  }

  Future<void> _openRandom() async {
    try {
      final story = await FoodmapApi.fetchRandomStory();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StoryDetailPage(story: story)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _openStory(Story story) async {
    try {
      final detail = await FoodmapApi.fetchStoryDetail(story.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StoryDetailPage(story: detail)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F4),
      appBar: AppBar(
        title: const Text('故事书', style: TextStyle(color: AppTheme.textDark)),
        backgroundColor: const Color(0xFFFBF7F4),
        actions: [
          TextButton.icon(
            onPressed: _stories.isEmpty ? null : _openRandom,
            icon: const Icon(Icons.casino_outlined,
                size: 18, color: AppTheme.primaryDark),
            label: const Text('随机来一篇',
                style: TextStyle(color: AppTheme.primaryDark)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCategoryBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ---- 分类横条 ----
  Widget _buildCategoryBar() {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _categoryChip(null, '全部'),
          for (final c in _categories) _categoryChip(c, c),
        ],
      ),
    );
  }

  Widget _categoryChip(String? value, String label) {
    final selected = _selected == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _selectCategory(value),
        selectedColor: AppTheme.primary,
        labelStyle: TextStyle(
          fontSize: 13,
          color: selected ? Colors.white : AppTheme.textDark,
        ),
        backgroundColor: Colors.white,
        side: BorderSide(
          color: selected ? AppTheme.primary : const Color(0xFFEDE3DC),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  // ---- 列表 / 空态 / 错误 ----
  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📖', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppTheme.textLight),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_stories.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📚', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 12),
            const Text(
              '书架上还没有故事\n后台添加上传后，这里就会亮起来',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textLight),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _stories.length,
      itemBuilder: (_, i) => _storyCard(_stories[i]),
    );
  }

  Widget _storyCard(Story story) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFF0E6DE)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openStory(story),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0E3),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text('📖', style: TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${story.category}'
                      '${story.source.isNotEmpty ? ' · ${story.source}' : ''}'
                      '${story.updatedAt.isNotEmpty ? ' · ${story.updatedAt}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textLight),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textLight),
            ],
          ),
        ),
      ),
    );
  }
}

/// 故事详情页（含正文）。
class StoryDetailPage extends StatelessWidget {
  const StoryDetailPage({super.key, required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F4),
      appBar: AppBar(
        title: const Text('故事', style: TextStyle(color: AppTheme.textDark)),
        backgroundColor: const Color(0xFFFBF7F4),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              story.title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                height: 1.4,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE9E9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    story.category,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.primaryDark),
                  ),
                ),
                const SizedBox(width: 10),
                if (story.source.isNotEmpty)
                  Text(story.source,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textLight)),
                const Spacer(),
                if (story.updatedAt.isNotEmpty)
                  Text(story.updatedAt,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textLight)),
              ],
            ),
            if (story.cover.isNotEmpty) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: FutureBuilder<String>(
                    future: FoodmapApi.mediaUrl(story.cover),
                    builder: (_, snap) {
                      final url = snap.data;
                      if (url == null || url.isEmpty) {
                        return Container(
                          color: const Color(0xFFFFE9E9),
                          child: const Center(
                            child: Text('📖', style: TextStyle(fontSize: 40)),
                          ),
                        );
                      }
                      return Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: const Color(0xFFFFE9E9),
                          child: const Center(
                            child: Text('📖', style: TextStyle(fontSize: 40)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Divider(color: Color(0xFFEDE3DC)),
            const SizedBox(height: 16),
            Text(
              story.content.isEmpty ? '（暂无正文）' : story.content,
              style: const TextStyle(
                fontSize: 16,
                height: 1.9,
                color: Color(0xFF4A3F3A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
