import 'package:flutter/material.dart';

import '../models/game.dart';
import '../theme.dart';
import '../widgets/cute_widgets.dart';
import '../widgets/game_draw_canvas.dart';

/// 战绩回顾：点开「最近战绩」里的任意一局，回看当时的图画与双方回答。
///
/// 只读展示（数据来自 history 接口，完局即全部揭晓），无任何操作。
class GameHistoryDetailPage extends StatelessWidget {
  const GameHistoryDetailPage({super.key, required this.game});

  final GameSession game;

  String get _dateLabel {
    final dt = DateTime.tryParse(game.createdAt)?.toLocal();
    if (dt == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}年${dt.month}月${dt.day}日 ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final (title, emoji) = switch (game.gameType) {
      'daily_question' => ('每日一问 · 回顾', '💬'),
      'this_or_that' => ('二选一 · 回顾', '🤔'),
      _ => ('你画我猜 · 回顾', '🎨'),
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text('$emoji $_dateLabel',
                style:
                    const TextStyle(fontSize: 12, color: AppTheme.textLight)),
            const SizedBox(height: 12),
            switch (game.gameType) {
              'daily_question' => _dailyBody(),
              'this_or_that' => _thisOrThatBody(),
              _ => _drawGuessBody(),
            },
          ],
        ),
      ),
    );
  }

  // ---- 每日一问：问题 + 双方答案 ----
  Widget _dailyBody() {
    final herAnswer = game.myRole == 'her' ? game.myAnswer : game.partnerAnswer;
    final himAnswer = game.myRole == 'him' ? game.myAnswer : game.partnerAnswer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BouncyIn(
          child: Card(
            color: const Color(0xFFFFF8E6),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                game.question ?? '',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                    height: 1.6),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _answerRow(Icons.female, '她 ♀ 说', herAnswer ?? '（没作答）'),
        const SizedBox(height: 10),
        _answerRow(Icons.male, '他 ♂ 说', himAnswer ?? '（没作答）'),
      ],
    );
  }

  Widget _answerRow(IconData icon, String who, String answer) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: AppTheme.primaryDark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(who,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textLight)),
                  const SizedBox(height: 4),
                  Text(answer,
                      style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textDark,
                          height: 1.6)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 二选一：题目 + 等高双卡 + 灵犀结论 ----
  Widget _thisOrThatBody() {
    final herChoice = game.myRole == 'her' ? game.myChoice : game.partnerChoice;
    final himChoice = game.myRole == 'him' ? game.myChoice : game.partnerChoice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BouncyIn(
          child: Card(
            color: const Color(0xFFFFF8E6),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                game.prompt,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                    height: 1.6),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _choiceCard(
                    game.optionA, herChoice == 'a', himChoice == 'a'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _choiceCard(
                    game.optionB, herChoice == 'b', himChoice == 'b'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            game.same == true ? '心有灵犀 ⭐⭐' : '各有各的想法 ⭐',
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryDark),
          ),
        ),
      ],
    );
  }

  /// 选项卡：展示谁选了这一项（她 ♀ / 他 ♂ 徽标），被选中的高亮。
  Widget _choiceCard(String option, bool herPicked, bool himPicked) {
    final picked = herPicked || himPicked;
    return Card(
      color: picked ? const Color(0xFFFFF8E6) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: picked
            ? const BorderSide(color: AppTheme.primary, width: 1.6)
            : const BorderSide(color: Color(0x11000000)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(option,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark)),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                if (herPicked)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.female,
                          size: 16, color: AppTheme.primaryDark),
                      Text('她',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.primaryDark)),
                    ],
                  ),
                if (himPicked)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.male, size: 16, color: AppTheme.primaryDark),
                      Text('他',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.primaryDark)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- 你画我猜：图画回放 + 词语结果 + 猜测记录 ----
  Widget _drawGuessBody() {
    final win = game.correct == true;
    final judgedWin = win && game.judged;
    final drawerIsHer = game.drawer == 'her';
    final resultLabel = judgedWin
        ? '判你对 ⭐'
        : win
            ? '一猜就中 ⭐⭐'
            : '差一点点 ⭐';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GameDrawCanvas(strokes: game.strokes),
        const SizedBox(height: 14),
        BouncyIn(
          child: Card(
            color: const Color(0xFFFFF8E6),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(resultLabel,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryDark)),
                  const SizedBox(height: 8),
                  Text(
                    '词语是「${game.word ?? ''}」· ${drawerIsHer ? '她画的，他猜' : '他画的，她猜'}',
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textDark),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (game.guesses.isNotEmpty) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drawerIsHer ? '他猜了 ${game.attempts} 次' : '她猜了 ${game.attempts} 次',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < game.guesses.length; i++)
                        Chip(
                          label: Text(
                            '${i + 1}. ${game.guesses[i]}',
                          ),
                          backgroundColor: const Color(0xFFFFF3D6),
                          labelStyle: const TextStyle(
                              fontSize: 13, color: AppTheme.textDark),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
