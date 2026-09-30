import 'package:flutter/material.dart';

import '../models/game.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';
import '../widgets/cute_widgets.dart';
import 'game_daily_page.dart';
import 'game_draw_guess_page.dart';
import 'game_history_detail_page.dart';
import 'game_this_or_that_page.dart';

/// 游戏中心：三个双人小游戏的入口 + 进行中的局 + 最近战绩。
///
/// 所有游戏都是异步回合制（轮到谁谁玩，下次打开继续），
/// 对方进度靠进入页面时拉取 + 游戏页内轮询，无需实时推送。
class GamesPage extends StatefulWidget {
  const GamesPage({super.key});

  @override
  State<GamesPage> createState() => _GamesPageState();
}

class _GamesPageState extends State<GamesPage> {
  List<GameSession> _active = [];
  List<GameSession> _history = [];
  int _historyTotal = 0; // 后端战绩总数（用于「查看更多」）
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final activeGames = await FoodmapApi.fetchActiveGames();
      if (!mounted) return;
      final history = await FoodmapApi.fetchGameHistory(limit: 10);
      if (!mounted) return;
      setState(() {
        _active = activeGames;
        _history = history.games;
        _historyTotal = history.total;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// 战绩分页：追加下一页（按 id 去重，防期间新完局的局插队导致重复）
  Future<void> _loadMoreHistory() async {
    if (_loadingMore || _history.length >= _historyTotal) return;
    setState(() => _loadingMore = true);
    try {
      final more = await FoodmapApi.fetchGameHistory(
          limit: 10, offset: _history.length);
      if (!mounted) return;
      setState(() {
        final seen = _history.map((g) => g.id).toSet();
        _history = [..._history, ...more.games.where((g) => seen.add(g.id))];
        _historyTotal = more.total;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  /// 进入游戏页，返回后刷新（刚玩完的局会挪到战绩区）
  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('游戏时光')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const Text(
                '两个人一起玩的小游戏 ⭐',
                style: TextStyle(fontSize: 13, color: AppTheme.textLight),
              ),
              const SizedBox(height: 16),
              _buildEntry('💬', '每日一问', '每天一个问题，答完互相揭晓',
                  () => _open(const GameDailyPage())),
              const SizedBox(height: 12),
              _buildEntry('🤔', '二选一对决', '火锅还是烧烤？看看 TA 怎么选',
                  () => _open(const GameThisOrThatPage())),
              const SizedBox(height: 12),
              _buildEntry('🎨', '你画我猜', '从美食库抽词，一个人画一个人猜',
                  () => _open(const GameDrawGuessPage())),
              if (_active.isNotEmpty) ...[
                const SizedBox(height: 28),
                const Text(
                  '进行中的局',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 12),
                for (final g in _active)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildActiveCard(g),
                  ),
              ],
              if (_history.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text(
                  _historyTotal > 0 ? '最近战绩 · 共 $_historyTotal 局' : '最近战绩',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    child: Column(
                      children: [
                        for (var i = 0; i < _history.length; i++) ...[
                          if (i > 0)
                          const Divider(height: 1, color: Color(0x11000000)),
                          _historyRow(_history[i]),
                        ],
                        if (_history.length < _historyTotal) ...[
                          const Divider(height: 1, color: Color(0x11000000)),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Center(
                              child: _loadingMore
                                  ? const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    )
                                  : TextButton.icon(
                                      onPressed: _loadMoreHistory,
                                      icon: const Icon(Icons.expand_more,
                                          size: 18),
                                      label: Text(
                                          '查看更多（还有 ${_historyTotal - _history.length} 局）'),
                                    ),
                            ),
                          ),
                        ] else if (_history.length > 10)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Center(
                              child: Text('没有更多啦 ⭐',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textLight)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 20),
                Text(
                  '$_error\n下拉重试，或到设置页检查后端地址',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textLight, height: 1.6),
                ),
              ],
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  '不用同时在线，轮到谁谁玩 ⭐',
                  style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 游戏入口卡 ----
  Widget _buildEntry(
      String emoji, String title, String subtitle, VoidCallback onTap) {
    return Card(
      child: SquishyTap(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3D6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 22))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textLight)),
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

  // ---- 进行中的会话卡（点击直接续玩） ----
  Widget _buildActiveCard(GameSession g) {
    String emoji;
    String title;
    String status;
    VoidCallback onTap;
    switch (g.gameType) {
      case 'daily_question':
        emoji = '💬';
        title = '每日一问';
        status = g.myAnswer == null
            ? '今天还没作答'
            : (g.partnerAnswered ? 'TA 答完了，等你揭晓' : 'TA 还没作答');
        onTap = () => _open(const GameDailyPage());
      case 'this_or_that':
        emoji = '🤔';
        title = '二选一对决';
        status = g.myChoice == null ? '还没选' : (g.partnerAnswered ? 'TA 选完了，去看结果' : '等 TA 选择');
        onTap = () => _open(const GameThisOrThatPage());
      default:
        emoji = '🎨';
        title = '你画我猜';
        status = g.amIDrawer
            ? (!g.ready ? '你还没画完 / 交卷' : '等 TA 猜')
            : (g.ready ? 'TA 画完了，等你猜' : 'TA 正在画…');
        onTap = () => _open(const GameDrawGuessPage());
    }
    return Card(
      child: SquishyTap(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark)),
                    const SizedBox(height: 3),
                    Text('$status · 点击继续',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textLight)),
                  ],
                ),
              ),
              const Icon(Icons.play_arrow, color: AppTheme.primaryDark),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 战绩行 ----
  Widget _historyRow(GameSession g) {
    String title;
    String result;
    switch (g.gameType) {
      case 'daily_question':
        title = '💬 每日一问';
        result = (g.question ?? '').length > 18
            ? '${g.question!.substring(0, 18)}…'
            : (g.question ?? '');
      case 'this_or_that':
        title = '🤔 二选一';
        result = g.same == true
            ? '${g.myChoice == 'a' ? g.optionA : g.optionB} · 心有灵犀 ⭐'
            : '我选${g.myChoice == 'a' ? g.optionA : g.optionB}，TA 选${g.partnerChoice == 'a' ? g.optionA : g.optionB}';
      default:
        title = '🎨 你画我猜';
        result = g.correct == true ? '「${g.word ?? ''}」一猜就中 ⭐' : '「${g.word ?? ''}」差一点点';
    }
    return SquishyTap(
      onTap: () => _open(GameHistoryDetailPage(game: g)),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark)),
            ),
            Expanded(
              flex: 2,
              child: Text(result,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textLight)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 18, color: AppTheme.textLight),
          ],
        ),
      ),
    );
  }
}
