import 'dart:convert';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/divination.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';
import '../widgets/cute_widgets.dart';

/// 每日占卜页：点击罗盘开始，指针旋转动画后展示今日塔罗解读。
/// 结果由后端按日期缓存，当天多次占卜结果一致，零点自动刷新。
/// 当天已占卜过再进入页面：直接展示上次结果，不再重新抽牌。
class DivinationPage extends StatefulWidget {
  const DivinationPage({super.key});

  @override
  State<DivinationPage> createState() => _DivinationPageState();
}

class _DivinationPageState extends State<DivinationPage>
    with TickerProviderStateMixin {
  static const _prefsKeyDate = 'divination_last_date_v2';
  static const _prefsKeyJson = 'divination_last_json_v2';

  // 指针旋转动画（点击后持续转，拿到结果后减速停止）
  late final AnimationController _spinCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  // 结果卡片入场动画
  late final AnimationController _resultCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  _Phase _phase = _Phase.idle;
  Divination? _result;
  String? _error;
  double _spinTurns = 0;

  /// 缓存已解析的塔罗牌图片完整 URL，避免 AnimatedBuilder 里重复创建 Future
  final Map<String, Future<String>> _imageFutures = {};

  Future<String> _resolveImage(String path) =>
      _imageFutures.putIfAbsent(path, () => FoodmapApi.mediaUrl(path));

  @override
  void initState() {
    super.initState();
    _restoreTodayResult();
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    _resultCtrl.dispose();
    super.dispose();
  }

  /// 当天已占卜过则直接展示结果（无动画、无请求）；未占卜或跨天保持待占卜状态。
  Future<void> _restoreTodayResult() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_prefsKeyDate) != _todayStr()) return;
      final jsonStr = prefs.getString(_prefsKeyJson);
      if (jsonStr == null || jsonStr.isEmpty) return;
      final d = Divination.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );
      if (d.cards.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _result = d;
      });
      _resultCtrl.value = 1.0; // 跳过入场动画直接展示
    } catch (_) {
      // 本地数据损坏则忽略，回到未占卜状态
    }
  }

  /// 占卜成功后落本地，当天再次进入页面直接展示结果
  Future<void> _saveTodayResult(Divination d) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyDate, d.date);
      await prefs.setString(_prefsKeyJson, jsonEncode(d.toJson()));
    } catch (_) {
      // 本地存储失败不影响本次展示
    }
  }

  static String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _startDivination() async {
    // 已占卜过则不再重新占卜（结果当天恒定，罗盘点击已被禁用，双保险）
    if (_phase != _Phase.idle) return;
    setState(() {
      _phase = _Phase.spinning;
      _error = null;
      _result = null;
    });
    _resultCtrl.reset();
    _spinCtrl.repeat();

    Divination? result;
    String? error;
    try {
      // 至少转 2.4 秒，让仪式感拉满
      final r = await Future.wait<dynamic>([
        FoodmapApi.fetchTodayDivination(),
        Future<void>.delayed(const Duration(milliseconds: 2400)),
      ]);
      result = r[0] as Divination;
    } catch (_) {
      // 展示友好文案，不把技术异常细节给用户看
      error = '占卜师没能连线成功，稍后再试试';
    }
    if (!mounted) return;

    if (result != null) _saveTodayResult(result);

    // 停针：补到最近的整圈，带一点回弹
    setState(() {
      _phase = result != null ? _Phase.done : _Phase.idle;
      _result = result;
      _error = error;
    });
    await _spinCtrl.animateTo(
      1.0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
    );
    _spinTurns += 1;
    _spinCtrl.value = 0;
    if (result != null && mounted) _resultCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('每日占卜')),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          child: Column(
            children: [
              _buildSubtitle(),
              const SizedBox(height: 20),
              _buildCompass(),
              const SizedBox(height: 24),
              if (_phase == _Phase.idle && _error == null) _buildHintButton(),
              if (_phase == _Phase.spinning) _buildLoadingHint(),
              if (_error != null) _buildError(),
              if (_result != null) _buildResult(_result!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitle() {
    final now = DateTime.now();
    return Text(
      '${now.month}月${now.day}日 · 为你抽取今日塔罗',
      style: const TextStyle(fontSize: 14, color: AppTheme.textLight),
    );
  }

  // ---- 罗盘 ----
  Widget _buildCompass() {
    final spinning = _phase == _Phase.spinning;
    return SquishyTap(
      onTap: spinning || _phase == _Phase.done ? null : _startDivination,
      borderRadius: BorderRadius.circular(160),
      child: SizedBox(
        width: 300,
        height: 300,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 底盘
            Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF3D6), Color(0xFFFFE0A8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: AppTheme.primary, width: 5),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
            ),
            // 方位刻度
            for (final (angle, label) in const [
              (0.0, '北'), (pi / 2, '东'), (pi, '南'), (3 * pi / 2, '西'),
            ])
              Transform.rotate(
                angle: angle,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                  ),
                ),
              ),
            // 旋转的指针盘
            AnimatedBuilder(
              animation: _spinCtrl,
              builder: (context, child) => Transform.rotate(
                angle: (_spinTurns + _spinCtrl.value) * 2 * pi,
                child: child,
              ),
              child: SizedBox(
                width: 240,
                height: 240,
                child: CustomPaint(painter: _NeedlePainter()),
              ),
            ),
            // 中心宝石
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryDark.withValues(alpha: 0.4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Center(
                child: spinning
                    ? const TypingDots(color: Colors.white)
                    : const Text('🔮', style: TextStyle(fontSize: 30)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHintButton() {
    return Column(
      children: [
        const Text(
          '心中默念一个小问题，然后轻触罗盘',
          style: TextStyle(fontSize: 13, color: AppTheme.textLight),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _startDivination,
          icon: const Text('✨'),
          label: const Text('开始今日占卜'),
        ),
      ],
    );
  }

  Widget _buildLoadingHint() {
    return const Column(
      children: [
        Text(
          '星辰正在排列，占卜师连线中…',
          style: TextStyle(fontSize: 13, color: AppTheme.textLight),
        ),
        SizedBox(height: 10),
        TypingDots(),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      children: [
        Text(
          _error ?? '占卜失败了',
          style: const TextStyle(fontSize: 13, color: Colors.redAccent),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _startDivination, child: const Text('再试一次')),
      ],
    );
  }

  // ---- 占卜结果 ----
  Widget _buildResult(Divination d) {
    return AnimatedBuilder(
      animation: _resultCtrl,
      builder: (context, child) {
        final t = CurvedAnimation(
          parent: _resultCtrl,
          curve: Curves.elasticOut,
        ).value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.7 + 0.3 * t, child: child),
        );
      },
      child: Column(
        children: [
          const SizedBox(height: 8),
          // 三张牌阵（时间之流：过去-现在-未来）
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < d.cards.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _buildTarotCard(d.cards[i], i),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          // 解读卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text('📜', style: TextStyle(fontSize: 16)),
                      SizedBox(width: 6),
                      Text(
                        '今日解读',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    d.reading,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.8,
                      color: AppTheme.textDark,
                    ),
                  ),
                  if (d.lucky.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3D6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '🍀 ${d.lucky}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.primaryDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '每日零点刷新，今天的好运已锁定 ✨',
            style: TextStyle(fontSize: 12, color: AppTheme.textLight),
          ),
        ],
      ),
    );
  }

  /// 单张塔罗牌卡：位置标签 + 塔罗牌图（韦特套图）+ 名称/正逆位 + 牌意关键词，
  /// 入场时按 index 依次从背面翻到正面。
  Widget _buildTarotCard(TarotCard card, int index) {
    final interval = Interval(
      index * 0.22,
      0.5 + index * 0.28,
      curve: Curves.easeOutCubic,
    );
    const positionColors = {
      '过去': Color(0xFF8A93A6),
      '现在': Color(0xFFE69600),
      '未来': Color(0xFF5CA36B),
    };
    return AnimatedBuilder(
      animation: _resultCtrl,
      builder: (context, child) {
        final t = interval.transform(_resultCtrl.value).clamp(0.0, 1.0);
        final flip = (1 - t) * pi; // 从背面翻到正面
        return Column(
          children: [
            Text(
              card.position,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: positionColors[card.position] ?? AppTheme.textLight,
              ),
            ),
            const SizedBox(height: 6),
            Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(flip),
                child: t < 0.5
                    ? _buildCardBack()
                    : _buildCardFace(card),
              ),
            ),
            const SizedBox(height: 6),
            // 牌名（逆位时带（逆位）标注）
            Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Text(
                card.isReversed ? '${card.name}（逆位）' : card.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ),
            const SizedBox(height: 2),
            // 正逆位小标签
            Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: card.isReversed
                      ? const Color(0xFF7B68B0).withValues(alpha: 0.18)
                      : const Color(0xFFE69600).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  card.orientation,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: card.isReversed
                        ? const Color(0xFF7B68B0)
                        : const Color(0xFFE69600),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Text(
                card.keyword,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.4,
                  color: AppTheme.textLight,
                ),
              ),
            ),
          ],
        );
      },
      child: const SizedBox.shrink(),
    );
  }

  /// 牌背面：只展示装饰纹理（翻转前半段）
  Widget _buildCardBack() {
    return Container(
      width: 92,
      height: 148,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B68B0), Color(0xFF4A3F7A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Center(child: Text('✨', style: TextStyle(fontSize: 26))),
    );
  }

  /// 牌正面：塔罗牌套图（韦特塔罗，公有领域），
  /// 逆位时图片旋转 180°（倒置），图片加载中显示加载动画，失败回退到渐变背景。
  Widget _buildCardFace(TarotCard card) {
    return FutureBuilder<String>(
      future: _resolveImage(card.image),
      builder: (context, snapshot) {
        final imageUrl = snapshot.data ?? '';
        final child = Container(
          width: 92,
          height: 148,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.primary, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      color: const Color(0xFF5B4B8A),
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                    errorWidget: (_, _, _) => _buildFaceFallback(card),
                  )
                : _buildFaceFallback(card),
          ),
        );
        // 逆位：整张牌旋转 180°
        if (card.isReversed) {
          return Transform.rotate(
            angle: pi,
            child: child,
          );
        }
        return child;
      },
    );
  }
  
  /// 图片加载失败或未就绪时：渐变背景 + 月亮装饰（保持视觉一致性）
  Widget _buildFaceFallback(TarotCard card) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF5B4B8A), Color(0xFF2F2650)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: const Center(
        child: Text('🌙', style: TextStyle(fontSize: 36)),
      ),
    );
  }
}

enum _Phase { idle, spinning, done }

/// 罗盘指针：上下双针 + 装饰圆环。
class _NeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFE69600).withValues(alpha: 0.6);
    canvas.drawCircle(c, r, ringPaint);
    canvas.drawCircle(c, r * 0.72, ringPaint..strokeWidth = 1);

    // 刻度
    final tickPaint = Paint()
      ..strokeWidth = 2
      ..color = const Color(0xFF9B8F85);
    for (var i = 0; i < 12; i++) {
      final a = i * pi / 6;
      final p1 = c + Offset(cos(a), sin(a)) * (r - 2);
      final p2 = c + Offset(cos(a), sin(a)) * (r - 10);
      canvas.drawLine(p1, p2, tickPaint);
    }

    // 北针（金）与南针（灰）
    final north = Path()
      ..moveTo(c.dx, c.dy - r * 0.82)
      ..lineTo(c.dx - 9, c.dy)
      ..lineTo(c.dx + 9, c.dy)
      ..close();
    final south = Path()
      ..moveTo(c.dx, c.dy + r * 0.82)
      ..lineTo(c.dx - 9, c.dy)
      ..lineTo(c.dx + 9, c.dy)
      ..close();
    canvas.drawPath(north, Paint()..color = const Color(0xFFFFB300));
    canvas.drawPath(south, Paint()..color = const Color(0xFFB0A79E));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
