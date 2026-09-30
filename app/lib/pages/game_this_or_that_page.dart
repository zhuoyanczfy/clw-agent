import 'dart:async';

import 'package:flutter/material.dart';

import '../models/game.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';
import '../widgets/cute_widgets.dart';

/// 二选一对决：双方各自选 A/B，都选完互相揭晓，看默契。
class GameThisOrThatPage extends StatefulWidget {
  const GameThisOrThatPage({super.key});

  @override
  State<GameThisOrThatPage> createState() => _GameThisOrThatPageState();
}

class _GameThisOrThatPageState extends State<GameThisOrThatPage> {
  GameSession? _game;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  Timer? _pollTimer; // 我已选、对方未选时轮询

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// 恢复进行中的一局；没有则提示开局（不自动 start，避免她打开就替她开题）
  Future<void> _load() async {
    try {
      GameSession? game;
      final active = await FoodmapApi.fetchActiveGames();
      for (final g in active) {
        if (g.gameType == 'this_or_that') {
          game = g;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _game = game;
        _loading = false;
        _error = null;
      });
      if (game != null) _syncPolling(game);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _syncPolling(GameSession game) {
    _pollTimer?.cancel();
    if (game.myChoice != null && !game.isCompleted) {
      _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
    }
  }

  Future<void> _startNew() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final game = await FoodmapApi.startGame('this_or_that');
      if (!mounted) return;
      setState(() {
        _game = game;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _choose(String choice) async {
    final game = _game;
    if (game == null || _busy) return;
    setState(() => _busy = true);
    try {
      final updated =
          await FoodmapApi.gameMove(game.id, 'choose', value: choice);
      if (!mounted) return;
      setState(() {
        _game = updated;
        _busy = false;
      });
      _syncPolling(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('二选一对决')),
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
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Text(
                            '$_error\n下拉重试',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textLight,
                                height: 1.6),
                          ),
                        ),
                      )
                    else if (_game == null)
                      _buildStartView()
                    else
                      _buildGameView(_game!),
                  ],
                ),
              ),
      ),
    );
  }

  // ---- 开局视图 ----
  Widget _buildStartView() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          const Text('🍕', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          const Text(
            '每一局随机一道二选一\n两个人各自选，选完互相揭晓',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, color: AppTheme.textDark, height: 1.7),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _startNew,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('开始一局 ⭐'),
          ),
        ],
      ),
    );
  }

  // ---- 对局视图 ----
  Widget _buildGameView(GameSession game) {
    final revealed = game.isCompleted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (game.prompt.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              game.prompt,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark),
            ),
          ),
        if (game.myChoice == null && !revealed) ...[
          // ---- 我还没选：两个大按钮 ----
          Row(
            children: [
              Expanded(
                  child: _ChoiceButton(
                label: game.optionA,
                color: AppTheme.primary,
                onTap: () => _choose('a'),
              )),
              const SizedBox(width: 14),
              Expanded(
                  child: _ChoiceButton(
                label: game.optionB,
                color: AppTheme.accent,
                onTap: () => _choose('b'),
              )),
            ],
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              '先选不许偷看，都选完自动揭晓 ⭐',
              style: TextStyle(fontSize: 12, color: AppTheme.textLight),
            ),
          ),
        ] else ...[
          // ---- 已选 / 揭晓：等高对称双卡 + VS 徽章 ----
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ChoiceResult(
                    title: '我选',
                    label: game.myChoice == 'a' ? game.optionA : game.optionB,
                    color: AppTheme.primary,
                    highlight: revealed && game.same == true,
                  ),
                ),
                const _VsBadge(),
                Expanded(
                  child: revealed
                      ? _ChoiceResult(
                          title: 'TA 选',
                          label: game.partnerChoice == 'a'
                              ? game.optionA
                              : game.optionB,
                          color: AppTheme.accent,
                          highlight: revealed && game.same == true,
                        )
                      : const _WaitingChoice(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (revealed)
            BouncyIn(
              child: Card(
                color: const Color(0xFFFFF8E6),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        game.same == true ? '心有灵犀 ⭐⭐' : '各有口味 ⭐',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDark),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        game.same == true ? '这题你们想到一块儿去了' : '没关系，两种都安排上',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textLight),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            const Center(
              child: Text(
                '等 TA 来选，选完自动揭晓',
                style: TextStyle(fontSize: 12, color: AppTheme.textLight),
              ),
            ),
          const SizedBox(height: 20),
          Center(
            child: OutlinedButton(
              onPressed: _busy ? null : _startNew,
              child: Text(revealed ? '再来一局' : '换一题（当前局作废）'),
            ),
          ),
        ],
      ],
    );
  }
}

/// 大选择按钮（未选择时）
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: Card(
        child: SquishyTap(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                  height: 1.4),
            ),
          ),
        ),
      ),
    );
  }
}

/// 已选结果卡：徽章标题 + 居中选项，心有灵犀时点亮边框
class _ChoiceResult extends StatelessWidget {
  const _ChoiceResult({
    required this.title,
    required this.label,
    required this.color,
    this.highlight = false,
  });

  final String title;
  final String label;
  final Color color;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: highlight ? const Color(0xFFFFF8E6) : Colors.white,
      shape: highlight
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppTheme.primary, width: 1.5),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(title,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                  height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// 等待对方选择的占位卡（与结果卡同构，徽章灰底）
class _WaitingChoice extends StatelessWidget {
  const _WaitingChoice();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('TA 选', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
            SizedBox(height: 10),
            Text('…', style: TextStyle(fontSize: 16, color: AppTheme.textLight)),
          ],
        ),
      ),
    );
  }
}

/// 双卡之间的 VS 小圆徽章
class _VsBadge extends StatelessWidget {
  const _VsBadge();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: Text('VS',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryDark)),
          ),
        ),
      ),
    );
  }
}
