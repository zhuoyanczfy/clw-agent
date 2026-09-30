import 'dart:ui';

/// 一笔画画：归一化点列 + 颜色（ARGB）+ 线宽系数（相对画布宽，渲染时乘宽度）。
class GameStroke {
  const GameStroke({
    required this.points,
    this.color = 0xFF37474F,
    this.width = 0.012,
  });

  final List<Offset> points; // 归一化坐标(0~1)
  final int color;
  final double width;
}

/// 双人小游戏会话（与后端 `_game_json` 双盲视图对应）。
///
/// 双盲铁律：partner 系列字段在双方都答完前由后端置空（本地不猜不补）；
/// 画猜的 word 在揭晓前仅画者可见。
class GameSession {
  const GameSession({
    required this.id,
    required this.gameType,
    required this.status,
    required this.myRole,
    this.date,
    required this.createdAt,
    // 每日一问
    this.question,
    this.myAnswer,
    this.partnerAnswer,
    this.partnerAnswered = false,
    // 二选一
    this.prompt = '',
    this.optionA = '',
    this.optionB = '',
    this.myChoice,
    this.partnerChoice,
    this.same,
    // 你画我猜
    this.drawer,
    this.amIDrawer = false,
    this.words,
    this.word,
    this.strokes = const [],
    this.ready = false,
    this.attempts = 0,
    this.maxAttempts = 3,
    this.guesses = const [],
    this.pendingJudge = false,
    this.judged = false,
    this.correct,
  });

  final int id;
  final String gameType; // daily_question / this_or_that / draw_guess
  final String status; // waiting / active / completed / abandoned
  final String myRole; // her / him
  final String? date;
  final String createdAt;

  // ---- 每日一问 ----
  final String? question;
  final String? myAnswer;
  final String? partnerAnswer;
  final bool partnerAnswered;

  // ---- 二选一 ----
  final String prompt;
  final String optionA;
  final String optionB;
  final String? myChoice; // 'a' / 'b'
  final String? partnerChoice;
  final bool? same;

  // ---- 你画我猜 ----
  final String? drawer;
  final bool amIDrawer;
  final List<String>? words; // 候选词（仅画者选词前可见）
  final String? word; // 正确词（画者或揭晓后可见）
  final List<GameStroke> strokes;
  final bool ready; // 画者是否交卷
  final int attempts;
  final int maxAttempts;
  final List<String> guesses;
  final bool pendingJudge; // 三次未中，等画者仲裁
  final bool judged; // 结果含画者仲裁成分
  final bool? correct;

  bool get isActive => status == 'active' || status == 'waiting';
  bool get isCompleted => status == 'completed';
  bool get revealed => isCompleted; // 双盲揭晓以完局为准

  factory GameSession.fromJson(Map<String, dynamic> json) {
    List<GameStroke> parseStrokes(dynamic raw) {
      if (raw is! List) return const [];
      return [
        for (final stroke in raw)
          if (stroke is Map && stroke['p'] is List && (stroke['p'] as List).isNotEmpty)
            GameStroke(
              color: (stroke['c'] as num?)?.toInt() ?? 0xFF37474F,
              width: (stroke['w'] as num?)?.toDouble() ?? 0.012,
              points: [
                for (final p in stroke['p'])
                  if (p is Map)
                    Offset(
                      (p['x'] as num?)?.toDouble() ?? 0,
                      (p['y'] as num?)?.toDouble() ?? 0,
                    ),
              ],
            ),
      ];
    }

    return GameSession(
      id: json['id'] as int,
      gameType: json['game_type']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      myRole: json['my_role']?.toString() ?? 'her',
      date: json['date']?.toString(),
      createdAt: json['created_at']?.toString() ?? '',
      question: json['question']?.toString(),
      myAnswer: json['my_answer']?.toString(),
      partnerAnswer: json['partner_answer']?.toString(),
      partnerAnswered: json['partner_answered'] == true,
      prompt: json['prompt']?.toString() ?? '',
      optionA: json['option_a']?.toString() ?? '',
      optionB: json['option_b']?.toString() ?? '',
      myChoice: json['my_choice']?.toString(),
      partnerChoice: json['partner_choice']?.toString(),
      same: json['same'] == null ? null : json['same'] == true,
      drawer: json['drawer']?.toString(),
      amIDrawer: json['am_i_drawer'] == true,
      words: (json['words'] as List?)?.map((e) => e.toString()).toList(),
      word: json['word']?.toString(),
      strokes: parseStrokes(json['strokes']),
      ready: json['ready'] == true,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      maxAttempts: (json['max_attempts'] as num?)?.toInt() ?? 3,
      guesses: (json['guesses'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      pendingJudge: json['pending_judge'] == true,
      judged: json['judged'] == true,
      correct: json['correct'] == null ? null : json['correct'] == true,
    );
  }

  /// 笔画转 JSON 提交：每笔 {c 颜色, w 线宽系数, p 点列}，坐标 0~1 保留 3 位小数。
  static List<Map<String, dynamic>> strokesToJson(List<GameStroke> strokes) {
    double round3(double v) => (v.clamp(0.0, 1.0) * 1000).round() / 1000;
    return [
      for (final stroke in strokes)
        {
          'c': stroke.color,
          'w': round3(stroke.width),
          'p': [
            for (final p in stroke.points) {'x': round3(p.dx), 'y': round3(p.dy)},
          ],
        },
    ];
  }
}
