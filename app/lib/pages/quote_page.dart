import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quote.dart';
import '../services/foodmap_api.dart';
import '../services/remote_config.dart';
import '../theme.dart';
import '../widgets/cute_widgets.dart';

/// 好句好段页：展示今日句子 + 历史列表 + 再来一条。
class QuotePage extends StatefulWidget {
  const QuotePage({super.key});

  @override
  State<QuotePage> createState() => _QuotePageState();
}

class _QuotePageState extends State<QuotePage> {
  Quote? _today;
  List<Quote> _history = [];
  bool _loading = true;
  bool _fetchingRandom = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static const _prefKeyRandomQuote = 'random_quote';

  Future<void> _saveRandomQuote(Quote quote) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyRandomQuote, jsonEncode(quote.toJson()));
  }

  Future<Quote?> _restoreRandomQuote() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKeyRandomQuote);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return Quote.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        FoodmapApi.fetchTodayQuote(),
        FoodmapApi.fetchQuoteHistory(),
        _restoreRandomQuote(),
      ]);
      if (!mounted) return;
      final todayQuote = results[0] as Quote;
      final history = results[1] as List<Quote>;
      final savedRandom = results[2] as Quote?;
      
      setState(() {
        // 如果有保存的随机句子，优先显示；否则显示今日句子
        _today = savedRandom ?? todayQuote;
        _history = history;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '好句没能取回来，稍后再试试';
        _loading = false;
      });
    }
  }

  Future<void> _fetchRandom() async {
    if (_fetchingRandom) return;
    setState(() => _fetchingRandom = true);
    try {
      final quote = await FoodmapApi.fetchRandomQuote();
      if (!mounted) return;
      // 直接更新今日句子，页面自动刷新显示新内容
      setState(() {
        _today = quote;
      });
      // 保存到 SharedPreferences，刷新后也能保持
      await _saveRandomQuote(quote);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('好句没能取回来，稍后再试试')),
      );
    } finally {
      if (mounted) setState(() => _fetchingRandom = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('好句好段')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '为${RemoteConfig.herName}收集的文字星光',
                  style: const TextStyle(fontSize: 14, color: AppTheme.textLight),
                ),
                const SizedBox(height: 20),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(60),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _buildError()
                else if (_today != null)
                  _buildTodayCard(_today!),
                const SizedBox(height: 20),
                // 再来一条按钮
                Center(
                  child: FilledButton.icon(
                    onPressed: _fetchingRandom ? null : _fetchRandom,
                    icon: _fetchingRandom
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('🔀'),
                    label: Text(_fetchingRandom ? '拉取中…' : '再来一条'),
                  ),
                ),
                const SizedBox(height: 28),
                if (_history.length > 1) ...[
                  const Text(
                    '往期回顾',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final q in _history.skip(1))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildHistoryItem(q),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Column(
      children: [
        Text(
          _error ?? '加载失败',
          style: const TextStyle(fontSize: 13, color: Colors.redAccent),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _load, child: const Text('重新加载')),
      ],
    );
  }

  // ---- 今日好句卡片 ----
  Widget _buildTodayCard(Quote q) {
    return BouncyIn(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 配图
            AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: q.imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  color: const Color(0xFFFFF3D6),
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, _, _) => Container(
                  color: const Color(0xFFFFF3D6),
                  child: const Center(
                    child: Text('📖', style: TextStyle(fontSize: 48)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 分类 + 日期
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          q.category,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.primaryDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        q.date,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textLight,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 金句
                  Text(
                    q.text,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 出处
                  Text(
                    '—— ${q.author}《${q.source}》',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textLight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 历史列表项 ----
  Widget _buildHistoryItem(Quote q) {
    return BouncyIn(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                q.text,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textDark,
                  height: 1.6,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${q.author}《${q.source}》',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textLight,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    q.date,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textLight,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
