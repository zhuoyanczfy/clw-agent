import 'dart:async';

import 'package:flutter/material.dart';

import '../models/game.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';
import '../widgets/cute_widgets.dart';

/// 每日一问：每天一题（按日期轮换），双方各自作答，都答完才互相揭晓。
///
/// 双盲由后端保证：对方答完前 partnerAnswer 恒为空（partnerAnswered 只有布尔）。
class GameDailyPage extends StatefulWidget {
  const GameDailyPage({super.key});

  @override
  State<GameDailyPage> createState() => _GameDailyPageState();
}

class _GameDailyPageState extends State<GameDailyPage> {
  GameSession? _game;
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  final _answerCtrl = TextEditingController();
  String? _answerError; // 必填为空时标红输入框，绝不静默 return

  Timer? _pollTimer; // 等待对方作答期间轮询（15s 一次，轻量）

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final game = await FoodmapApi.fetchDailyGame();
      if (!mounted) return;
      setState(() {
        _game = game;
        _loading = false;
        _error = null;
        // 回显已提交的答案，避免重复输入
        if (game.myAnswer != null) _answerCtrl.text = game.myAnswer!;
      });
      _syncPolling(game);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// 我已答而对方未答时轮询；揭晓后停止
  void _syncPolling(GameSession game) {
    _pollTimer?.cancel();
    if (game.myAnswer != null && !game.isCompleted) {
      _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
    }
  }

  Future<void> _submit() async {
    final answer = _answerCtrl.text.trim();
    if (answer.isEmpty) {
      setState(() => _answerError = '写下你的答案吧，TA 在等哦');
      return;
    }
    final game = _game;
    if (game == null || _submitting) return;
    setState(() {
      _submitting = true;
      _answerError = null;
    });
    try {
      final updated = await FoodmapApi.gameMove(
        game.id,
        'answer',
        value: answer,
      );
      if (!mounted) return;
      setState(() {
        _game = updated;
        _submitting = false;
      });
      _syncPolling(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('每日一问')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    if (_error != null)
                      _ErrorView(error: _error!)
                    else if (_game != null)
                      ..._buildBody(_game!),
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _buildBody(GameSession game) {
    return [
      BouncyIn(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.star, color: AppTheme.primary, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      game.date ?? '今天',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textLight),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  game.question ?? '',
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                      height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      if (game.myAnswer == null) ...[
        // ---- 我还没答 ----
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('我的答案（TA 答完前互相看不到）',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark)),
                const SizedBox(height: 12),
                TextField(
                  controller: _answerCtrl,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    isDense: true,
                    hintText: '例如：今天想和你一起去吃那家新开的小馆子…',
                    errorText: _answerError,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('提交答案'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ] else ...[
        _AnswerCard(
          emoji: '⭐',
          title: '我的答案',
          answer: game.myAnswer!,
        ),
        const SizedBox(height: 12),
        if (game.isCompleted && game.partnerAnswer != null) ...[
          // ---- 双盲揭晓 ----
          BouncyIn(
            delay: const Duration(milliseconds: 200),
            child: _AnswerCard(
              emoji: '🌟',
              title: 'TA 的答案',
              answer: game.partnerAnswer!,
              highlight: true,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '答案没有对错，重要的是每天都想聊聊 ⭐',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.textLight),
          ),
        ] else ...[
          // ---- 等待对方 ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  HeartBeat(
                    duration: const Duration(milliseconds: 1200),
                    child: const Icon(Icons.star,
                        color: AppTheme.primary, size: 30),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    game.partnerAnswered ? 'TA 答完了，就等你揭晓' : 'TA 还没作答',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '留着这页别关，答完会自动揭晓；也可以先去玩别的',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 12, color: AppTheme.textLight),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ];
  }
}

/// 单条答案卡片（我的 / TA 的 共用）
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.emoji,
    required this.title,
    required this.answer,
    this.highlight = false,
  });

  final String emoji;
  final String title;
  final String answer;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: highlight ? const Color(0xFFFFF8E6) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryDark)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              answer,
              style: const TextStyle(
                  fontSize: 15, color: AppTheme.textDark, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

/// 加载失败视图（统一风格）
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          const Text('🧭', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 12),
          Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, color: AppTheme.textLight, height: 1.6),
          ),
          const SizedBox(height: 8),
          const Text('下拉重试',
              style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
        ],
      ),
    );
  }
}
