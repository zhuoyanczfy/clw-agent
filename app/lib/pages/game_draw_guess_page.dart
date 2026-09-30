import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/game.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';
import '../widgets/cute_widgets.dart';
import '../widgets/game_draw_canvas.dart';

/// 美食版你画我猜：从菜库抽 3 个词，画者选 1 个画，猜者最多猜 3 次。
///
/// 异步回合制：画者随画随传（逐笔提交），猜者打开页面实时看重画；
/// 全程无需同时在线，轮到谁谁玩。
class GameDrawGuessPage extends StatefulWidget {
  const GameDrawGuessPage({super.key});

  @override
  State<GameDrawGuessPage> createState() => _GameDrawGuessPageState();
}

class _GameDrawGuessPageState extends State<GameDrawGuessPage> {
  GameSession? _game;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  // 画者本地画板（归一化坐标），提交时整体上传
  final List<GameStroke> _strokes = [];
  Offset? _lastPoint; // 抽稀用：距上一点太近不入列

  // 画笔状态：颜色 / 粗细 / 橡皮（橡皮=白色粗笔，落在白底上即等效擦除）
  int _color = 0xFF37474F;
  double _width = 0.012;
  bool _erasing = false;

  final _guessCtrl = TextEditingController();

  Timer? _pollTimer; // 等对方操作期间轮询

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _guessCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      GameSession? game;
      final active = await FoodmapApi.fetchActiveGames();
      for (final g in active) {
        if (g.gameType == 'draw_guess') {
          game = g;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _game = game;
        _loading = false;
        _error = null;
        // 画者恢复本地画板（继续补几笔）
        if (game != null && game.amIDrawer && !game.ready) {
          _strokes
            ..clear()
            ..addAll(game.strokes);
        }
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

  /// 需要等对方时轮询：画者交卷后等猜（含仲裁）、猜者等画或等判定
  void _syncPolling(GameSession? game) {
    _pollTimer?.cancel();
    if (game == null || game.isCompleted) return;
    final waitingPartner = game.amIDrawer
        ? game.ready // 画者已交卷，等猜（含等仲裁）
        : (!game.ready || game.pendingJudge); // 猜者等画或等判定
    if (waitingPartner) {
      _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
    }
  }

  Future<GameSession?> _move(String action, {dynamic value}) async {
    final game = _game;
    if (game == null || _busy) return null;
    setState(() => _busy = true);
    try {
      final updated = await FoodmapApi.gameMove(game.id, action, value: value);
      if (!mounted) return null;
      setState(() {
        _game = updated;
        _busy = false;
      });
      _syncPolling(updated);
      return updated;
    } catch (e) {
      if (!mounted) return null;
      setState(() => _busy = false);
      _toast(e.toString().replaceFirst('Exception: ', ''));
      return null;
    }
  }

  Future<void> _startAsDrawer() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final game = await FoodmapApi.startGame('draw_guess');
      if (!mounted) return;
      _strokes.clear();
      setState(() {
        _game = game;
        _busy = false;
      });
      _syncPolling(game);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _submitGuess() async {
    final guess = _guessCtrl.text.trim();
    if (guess.isEmpty) {
      _toast('先写一个猜的词吧');
      return;
    }
    final updated = await _move('guess', value: guess);
    if (updated != null) {
      _guessCtrl.clear();
      if (updated.isCompleted) {
        _showResult(updated);
      } else if (updated.pendingJudge) {
        _toast('三次机会用完，TA 正在判定你的答案…');
      } else {
        _toast('差一点！还剩 ${updated.maxAttempts - updated.attempts} 次机会');
      }
    }
  }

  /// 完局揭晓弹层（星星庆祝；含画者仲裁的胜利用不同文案）
  void _showResult(GameSession game) {
    final win = game.correct == true;
    final judgedWin = win && game.judged;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(win ? Icons.emoji_events : Icons.star,
                color: win ? AppTheme.primary : AppTheme.textLight),
            const SizedBox(width: 8),
            Text(judgedWin ? '判你对！' : win ? '一猜就中！' : '差一点点'),
          ],
        ),
        content: Text(
          judgedWin
              ? '「${game.word}」没直接猜中，但 TA 认可了你的叫法 ⭐'
              : win
                  ? '答案就是「${game.word}」⭐ 你们的默契藏不住了'
                  : '其实是「${game.word}」⭐ 不过画得已经很像了',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好耶'),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('你画我猜')),
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

  // ---- 开局视图：我当画者（猜者等对方开局） ----
  Widget _buildStartView() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          const Text('🎨', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          const Text(
            '从美食库抽 3 个词，选 1 个画出来\nTA 打开就能看到你的画，最多猜 3 次',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, color: AppTheme.textDark, height: 1.7),
          ),
          const SizedBox(height: 8),
          const Text(
            '（TA 也可以开局当画者，你来猜）',
            style: TextStyle(fontSize: 12, color: AppTheme.textLight),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _startAsDrawer,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('我来画一局 ⭐'),
          ),
        ],
      ),
    );
  }

  Widget _buildGameView(GameSession game) {
    if (game.amIDrawer) return _buildDrawerView(game);
    return _buildGuesserView(game);
  }

  // ==================== 画者视角 ====================
  Widget _buildDrawerView(GameSession game) {
    final word = game.word;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (word == null && game.words != null) ...[
          const Text('选一个词来画（只有你能看到 ⭐）',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark)),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < game.words!.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: Card(
                    child: SquishyTap(
                      onTap: () =>
                          _move('pick_word', value: game.words![i]),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          game.words![i],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryDark),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ] else if (word != null && !game.ready) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.star, color: AppTheme.primary, size: 16),
              const SizedBox(width: 6),
              Text('本轮词语「$word」（只有你知道）',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark)),
            ],
          ),
          const SizedBox(height: 12),
          _DrawBoard(
            strokes: _strokes,
            enabled: true,
            eraserHint: true, // 橡皮白笔在本地渲染成浅灰，画者能看见轨迹
            onStrokeStart: _onStrokeStart,
            onStrokeMove: _onStrokeMove,
            onStrokeEnd: _onStrokeEnd,
          ),
          const SizedBox(height: 10),
          _buildToolbar(),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submitDrawing,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('画好了，交给 TA 猜 ⭐'),
            ),
          ),
        ] else if (game.ready && !game.isCompleted) ...[
          _DrawBoard(strokes: game.strokes, enabled: false),
          const SizedBox(height: 16),
          if (game.pendingJudge)
            _buildJudgeCard(game)
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    HeartBeat(
                      duration: const Duration(milliseconds: 1200),
                      child: const Icon(Icons.star,
                          color: AppTheme.primary, size: 28),
                    ),
                    const SizedBox(height: 8),
                    const Text('TA 正在看你的画…',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark)),
                    const SizedBox(height: 6),
                    Text(
                      '已猜 ${game.attempts}/${game.maxAttempts} 次，'
                      '${game.attempts == 0 ? '' : '猜过：${game.guesses.join('、')}'}',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textLight),
                    ),
                  ],
                ),
              ),
            ),
        ] else ...[
          _buildRevealed(game),
        ],
      ],
    );
  }

  void _onStrokeStart(Offset p) {
    setState(() => _strokes.add(GameStroke(
          points: [p],
          color: _erasing ? 0xFFFFFFFF : _color,
          width: _erasing ? (_width * 3).clamp(0.03, 0.06) : _width,
        )));
    _lastPoint = p;
  }

  void _onStrokeMove(Offset p) {
    // 抽稀：距上一点 < 0.5% 画布宽/高就不记，控制笔画体积
    final last = _lastPoint;
    if (last != null && (p - last).distance < 0.005) return;
    setState(() => _strokes.last.points.add(p));
    _lastPoint = p;
  }

  void _onStrokeEnd() {
    _lastPoint = null;
    _syncStrokes();
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
    _syncStrokes();
  }

  void _clearAll() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.clear());
    _syncStrokes();
  }

  /// 笔画同步：整份上传（后端覆盖存储），断网/退出最多丢最近一笔
  void _syncStrokes() {
    final game = _game;
    if (game == null || _busy) return;
    FoodmapApi.gameMove(
      game.id,
      'strokes',
      value: GameSession.strokesToJson(_strokes),
    ).then((updated) {
      if (mounted) setState(() => _game = updated);
    }).catchError((_) {}); // 同步失败不打断画画，交卷时会再传整份
  }

  // ---- 画板工具栏：颜色 / 粗细 / 橡皮 / 撤回 / 清空 ----
  static const _palette = <int>[
    0xFF37474F, // 墨色
    0xFFE53935, // 红烧
    0xFFF57C00, // 橙黄
    0xFF43A047, // 葱绿
    0xFF1E88E5, // 蓝莓
    0xFF6D4C41, // 酱棕
  ];
  static const _widths = <double>[0.006, 0.012, 0.024];

  Widget _buildToolbar() {
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < _palette.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _colorDot(_palette[i]),
            ],
            const Spacer(),
            for (var i = 0; i < _widths.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _widthDot(_widths[i]),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  foregroundColor: _erasing
                      ? AppTheme.primaryDark
                      : AppTheme.textLight,
                ),
                onPressed: () => setState(() => _erasing = !_erasing),
                icon: const Icon(Icons.auto_fix_normal, size: 18),
                label: Text(_erasing ? '橡皮中' : '橡皮',
                    style: const TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  foregroundColor: AppTheme.textLight,
                ),
                onPressed: _strokes.isEmpty ? null : _undo,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('撤回', style: TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  foregroundColor: AppTheme.textLight,
                ),
                onPressed: _strokes.isEmpty ? null : _clearAll,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('清空', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _colorDot(int c) {
    final selected = !_erasing && _color == c;
    return GestureDetector(
      onTap: () => setState(() {
        _color = c;
        _erasing = false; // 选色自动退出橡皮
      }),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color(c),
          border: Border.all(
            color: selected ? AppTheme.primaryDark : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : null,
      ),
    );
  }

  Widget _widthDot(double w) {
    final selected = _width == w;
    final d = 10.0 + (w - 0.006) / 0.018 * 12; // 细 10 → 粗 22
    return GestureDetector(
      onTap: () => setState(() => _width = w),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? const Color(0xFFFFF3D6) : Colors.transparent,
          border: Border.all(
            color: selected ? AppTheme.primary : const Color(0x22000000),
            width: 1.5,
          ),
        ),
        child: Container(
          width: d,
          height: d,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: AppTheme.textDark),
        ),
      ),
    );
  }

  Future<void> _submitDrawing() async {
    if (_strokes.isEmpty) {
      _toast('先画点什么吧，一笔也行');
      return;
    }
    // 交卷前再整体传一次，保证最后一笔不丢
    final saved = await _move('strokes',
        value: GameSession.strokesToJson(_strokes));
    if (saved == null) return;
    await _move('ready');
  }

  // ==================== 猜者视角 ====================
  Widget _buildGuesserView(GameSession game) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!game.ready) ...[
          const Text('TA 正在画，先看看已有的笔迹 ⭐',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark)),
          const SizedBox(height: 12),
          _DrawBoard(strokes: game.strokes, enabled: false),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              '画好会自动进入猜词，每 8 秒刷新一次',
              style: TextStyle(fontSize: 12, color: AppTheme.textLight),
            ),
          ),
        ] else if (!game.isCompleted) ...[
          _DrawBoard(strokes: game.strokes, enabled: false),
          const SizedBox(height: 16),
          if (game.pendingJudge)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    HeartBeat(
                      duration: const Duration(milliseconds: 1200),
                      child: const Icon(Icons.star,
                          color: AppTheme.primary, size: 28),
                    ),
                    const SizedBox(height: 8),
                    const Text('三次机会用完啦',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark)),
                    const SizedBox(height: 6),
                    const Text(
                      'TA 正在看你的猜法像不像，稍等一下…',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textLight, height: 1.6),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'TA 画的是哪道美食？',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark),
                        ),
                        const Spacer(),
                        Text(
                          '剩余 ${game.maxAttempts - game.attempts} 次',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.primaryDark),
                        ),
                      ],
                    ),
                    if (game.guesses.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('猜过：${game.guesses.join('、')}',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textLight)),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _guessCtrl,
                      maxLength: 50,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        hintText: '例如：番茄牛腩',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _submitGuess(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _submitGuess,
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('就是它！'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ] else ...[
          _buildRevealed(game),
        ],
      ],
    );
  }

  // ---- 完局揭晓（双方共用） ----
  Widget _buildRevealed(GameSession game) {
    final win = game.correct == true;
    final judgedWin = win && game.judged;
    return Column(
      children: [
        _DrawBoard(strokes: game.strokes, enabled: false),
        const SizedBox(height: 16),
        BouncyIn(
          child: Card(
            color: const Color(0xFFFFF8E6),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    judgedWin
                        ? '判你对 ⭐'
                        : win
                            ? '一猜就中 ⭐⭐'
                            : '差一点点 ⭐',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryDark),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '词语是「${game.word ?? ''}」',
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.textDark),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: OutlinedButton(
            onPressed: _busy ? null : _startAsDrawer,
            child: const Text('再开一局（我画）'),
          ),
        ),
      ],
    );
  }

  // ---- 画者仲裁：三次未中，由画者判定对方的猜法是否算对 ----
  Widget _buildJudgeCard(GameSession game) {
    return BouncyIn(
      child: Card(
        color: const Color(0xFFFFF8E6),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.star, color: AppTheme.primary, size: 28),
              const SizedBox(height: 8),
              const Text('TA 三次都没猜中，你来看看：',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark)),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final g in game.guesses)
                    Chip(
                      label: Text(g),
                      backgroundColor: Colors.white,
                      labelStyle: const TextStyle(
                          fontSize: 13, color: AppTheme.textDark),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '正确答案是「${game.word}」，如果 TA 只是叫法不同，就大方点算对吧',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textLight, height: 1.6),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _busy ? null : () => _move('judge', value: false),
                      child: const Text('真没猜中'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _busy ? null : () => _move('judge', value: true),
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('算 TA 对 ⭐'),
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

/// 画板：CustomPaint 重绘归一化笔画（乘以画布尺寸），画者可动笔。
///
/// AspectRatio 必须在 LayoutBuilder 外层：ListView 给子项的高度约束是无限的，
/// 先定下 4:3 尺寸再取约束做归一化，否则 y/∞ 恒为 0，全部挤成顶部一条线。
class _DrawBoard extends StatelessWidget {
  const _DrawBoard({
    required this.strokes,
    required this.enabled,
    this.eraserHint = false,
    this.onStrokeStart,
    this.onStrokeMove,
    this.onStrokeEnd,
  });

  final List<GameStroke> strokes;
  final bool enabled;
  final bool eraserHint; // 画者视角：橡皮白笔渲染成浅灰便于自见
  final void Function(Offset normalized)? onStrokeStart;
  final void Function(Offset normalized)? onStrokeMove;
  final VoidCallback? onStrokeEnd;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          Offset normalize(Offset local) => Offset(
                (local.dx / constraints.maxWidth).clamp(0.0, 1.0),
                (local.dy / constraints.maxHeight).clamp(0.0, 1.0),
              );
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x1A000000)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              // Immediate 手势：指针刚按下就赢得手势竞技场，ListView 的
              // 滚动手势抢不走拖动（否则斜着划会变成页面滚动）。
              // 回调只给全局坐标，用画布 RenderBox 转回本地再归一化
              child: Builder(
                builder: (canvasCtx) {
                  Offset toLocal(Offset global) {
                    final box =
                        canvasCtx.findRenderObject() as RenderBox?;
                    return box == null ? global : box.globalToLocal(global);
                  }

                  return enabled
                      ? RawGestureDetector(
                          behavior: HitTestBehavior.opaque,
                          gestures: {
                            ImmediateMultiDragGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                    ImmediateMultiDragGestureRecognizer>(
                              () => ImmediateMultiDragGestureRecognizer(),
                              (instance) => instance
                                ..onStart = (initialPosition) {
                                  final start =
                                      normalize(toLocal(initialPosition));
                                  onStrokeStart?.call(start);
                                  return _CanvasDrag(
                                    toLocal: toLocal,
                                    normalize: normalize,
                                    onMove: onStrokeMove,
                                    onEnd: onStrokeEnd,
                                  );
                                },
                            ),
                          },
                          child: CustomPaint(
                            painter: GameStrokesPainter(strokes,
                                eraserHint: eraserHint),
                            size: Size.infinite,
                          ),
                        )
                      : CustomPaint(
                          painter: GameStrokesPainter(strokes,
                              eraserHint: eraserHint),
                          size: Size.infinite,
                        );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 画布拖动：MultiDrag 的回调只给全局坐标，统一转本地再归一化后回调
class _CanvasDrag extends Drag {
  _CanvasDrag({
    required this.toLocal,
    required this.normalize,
    this.onMove,
    this.onEnd,
  });

  final Offset Function(Offset) toLocal;
  final Offset Function(Offset) normalize;
  final void Function(Offset)? onMove;
  final void Function()? onEnd;

  @override
  void update(DragUpdateDetails details) =>
      onMove?.call(normalize(toLocal(details.globalPosition)));

  @override
  void end(DragEndDetails details) => onEnd?.call();

  @override
  void cancel() => onEnd?.call();
}
