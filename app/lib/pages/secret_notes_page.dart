import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/secret_note.dart';
import '../services/remote_config.dart';
import '../theme.dart';

/// 彩蛋「星语」：只属于两个人的小小星空。
///
/// 整个屏幕是一小片贴面的球面视野：碎碎念星星随机分布在球面上，
/// 上下左右斜着拖动可以像转地球仪一样四处环视，轻甩一下还会带着惯性
/// 顺滑地多转一小段，然后停在那里，随时能把任意一片星空转到眼前。
/// 没看过的星星微微闪烁，看过的安静亮着，点开可以看到里面的话。

const _readKey = 'secret_notes_read_ids';
const _maxPitch = 75 * math.pi / 180; // 俯仰上限（水平方向可以一直转圈）
const _glideDrag = 0.02; // 甩动摩擦：越小滑得越远
const _maxGlideSpeed = 5.0; // 甩动角速度上限（弧度/秒），避免一拨转出去太远

/// 稳定的伪随机因子：同一条碎碎念每次进入星空的位置一致
double _noise(int i, int salt) {
  final v = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453;
  return v - v.floorToDouble();
}

// ============================================================
// 球面数据
// ============================================================

/// 碎碎念星星在球面上的方位（yaw：水平角，pitch：俯仰角，正值朝上）
class _NoteDir {
  const _NoteDir(this.yaw, this.pitch);
  final double yaw;
  final double pitch;
}

/// 初始视野里的专属座次：保证一打开就有星星出现在眼前
const List<List<double>> _coreSlots = [
  [0, 7], // 中偏上
  [-25, -15], // 左下
  [26, -10], // 右下
  [-16, 25], // 左上
  [17, 27], // 右上
  [0, -25], // 中偏下
];

/// 为每条碎碎念分配球面方位
List<_NoteDir> _buildNoteDirs(int count) {
  final dirs = <_NoteDir>[];
  for (var i = 0; i < count; i++) {
    if (i < _coreSlots.length) {
      // 核心座次 + 轻微抖动，像随手撒出来的
      final slot = _coreSlots[i];
      dirs.add(_NoteDir(
        (slot[0] + (_noise(i, 11) - 0.5) * 10) * math.pi / 180,
        (slot[1] + (_noise(i, 12) - 0.5) * 10) * math.pi / 180,
      ));
    } else {
      // 其余的散落在球面各处（避开正背后与两极，保证转得过去都够得着）
      dirs.add(_NoteDir(
        (_noise(i, 13) - 0.5) * 320 * math.pi / 180,
        (_noise(i, 14) - 0.5) * 144 * math.pi / 180,
      ));
    }
  }
  return dirs;
}

/// 背景装饰星点：均匀铺满球面的远景星 + 一条斜斜的银河带
class _DecoDot {
  const _DecoDot(this.yaw, this.pitch, this.radius, this.alpha, this.color,
      this.twinkleSpeed);

  final double yaw;
  final double pitch;
  final double radius;
  final double alpha;
  final Color color;
  final double twinkleSpeed;
}

const _decoColors = [Color(0xFFFFFFFF), Color(0xFFD8E4FF), Color(0xFFE8DFFF)];

List<_DecoDot> _buildDecoDots() {
  final dots = <_DecoDot>[];

  // 1) 均匀背景星：斐波那契球面分布，铺满整个球
  const uniformCount = 64;
  for (var i = 0; i < uniformCount; i++) {
    final wy = 1 - 2 * (i + 0.5) / uniformCount;
    final r = math.sqrt(math.max(0.0, 1 - wy * wy));
    final theta = i * 2.399963229728653; // 黄金角
    final x = r * math.cos(theta);
    final z = r * math.sin(theta);
    dots.add(_DecoDot(
      math.atan2(x, z),
      math.asin(-wy),
      0.9 + _noise(i, 31) * 1.5,
      0.16 + _noise(i, 32) * 0.34,
      _decoColors[i % 3],
      0.6 + _noise(i, 33) * 1.6,
    ));
  }

  // 2) 银河带：倾斜大圆附近的细小星点，转动时像一条光带流过
  const beltCount = 44;
  const tilt = 0.62; // 圆面倾斜角
  for (var i = 0; i < beltCount; i++) {
    final theta = _noise(i, 41) * math.pi * 2;
    var x = math.cos(theta);
    var y = -math.sin(theta) * math.sin(tilt);
    var z = math.sin(theta) * math.cos(tilt);
    y += (_noise(i, 42) - 0.5) * 0.5; // 带宽抖动
    final norm = math.sqrt(x * x + y * y + z * z);
    x /= norm;
    y /= norm;
    z /= norm;
    dots.add(_DecoDot(
      math.atan2(x, z),
      math.asin((-y).clamp(-1.0, 1.0).toDouble()),
      0.7 + _noise(i, 43) * 1.0,
      0.12 + _noise(i, 44) * 0.3,
      _decoColors[(i + 1) % 3],
      0.5 + _noise(i, 45) * 1.8,
    ));
  }
  return dots;
}

// ============================================================
// 页面
// ============================================================

class SecretNotesPage extends StatefulWidget {
  const SecretNotesPage({super.key});

  @override
  State<SecretNotesPage> createState() => _SecretNotesPageState();
}

/// 球面投影结果：屏幕坐标 + 深度（视线方向余弦，1 = 正前方）
class _Proj {
  const _Proj(this.x, this.y, this.depth);
  final double x;
  final double y;
  final double depth;
}

class _SecretNotesPageState extends State<SecretNotesPage>
    with TickerProviderStateMixin {
  late final List<SecretNote> _notes = RemoteConfig.secretNotes;
  late final List<_NoteDir> _dirs = _buildNoteDirs(_notes.length);
  late final List<_DecoDot> _decoDots = _buildDecoDots();
  final Set<String> _readIds = {};

  // 当前环视角度（像地球仪一样，转到哪就停在哪）
  double _yaw = 0;
  double _pitch = 0;

  /// 甩动惯性：松手后顺着速度继续滑一小段
  late final AnimationController _yawGlide =
      AnimationController.unbounded(vsync: this);
  late final AnimationController _pitchGlide =
      AnimationController.unbounded(vsync: this);

  /// 入场时的星星浮现动画
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  /// 远景装饰星的呼吸闪烁（全局相位）
  late final AnimationController _twinkle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void initState() {
    super.initState();
    _loadReadIds();
    _entrance.forward();
    _twinkle.repeat();
    _yawGlide.addListener(() => setState(() => _yaw = _yawGlide.value));
    _pitchGlide.addListener(() {
      final v = _pitchGlide.value;
      if (v.abs() >= _maxPitch) {
        // 滑到两极附近就停下
        _pitchGlide.stop();
        setState(() => _pitch = v.clamp(-_maxPitch, _maxPitch).toDouble());
      } else {
        setState(() => _pitch = v);
      }
    });
  }

  @override
  void dispose() {
    _yawGlide.dispose();
    _pitchGlide.dispose();
    _entrance.dispose();
    _twinkle.dispose();
    super.dispose();
  }

  Future<void> _loadReadIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_readKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          _readIds.addAll(list.map((e) => e.toString()));
        }
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _markRead(SecretNote note) async {
    if (note.id.isEmpty || _readIds.contains(note.id)) return;
    setState(() => _readIds.add(note.id));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_readKey, jsonEncode(_readIds.toList()));
    } catch (_) {}
  }

  void _openNote(int index) {
    final note = _notes[index];
    _markRead(note);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.72,
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              _NoteCard(note: note, index: index, total: _notes.length),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // 拖动环视（地球仪手感：转到哪停在哪，轻甩带惯性）
  // ==========================================================

  void _onPanStart() {
    _yawGlide.stop(); // 手指按下即接管，停止滑行
    _pitchGlide.stop();
  }

  void _onPanUpdate(DragUpdateDetails details, double focal) {
    setState(() {
      // 水平方向可以一直转圈；俯仰到两极附近就顶住
      _yaw += details.delta.dx / focal;
      _pitch = (_pitch + details.delta.dy / focal)
          .clamp(-_maxPitch, _maxPitch)
          .toDouble();
    });
  }

  void _onPanEnd(DragEndDetails details, double focal) {
    final vx = details.velocity.pixelsPerSecond.dx / focal;
    final vy = details.velocity.pixelsPerSecond.dy / focal;
    // 慢慢松手就安静停住，快速甩动才顺着力滑一段
    if (vx.abs() < 0.08 && vy.abs() < 0.08) return;
    final cvx = vx.clamp(-_maxGlideSpeed, _maxGlideSpeed).toDouble();
    final cvy = vy.clamp(-_maxGlideSpeed, _maxGlideSpeed).toDouble();
    _yawGlide.value = _yaw;
    _pitchGlide.value = _pitch;
    _yawGlide.animateWith(FrictionSimulation(_glideDrag, _yaw, cvx));
    _pitchGlide.animateWith(FrictionSimulation(_glideDrag, _pitch, cvy));
  }

  // ==========================================================
  // 球面投影
  // ==========================================================

  /// 把球面方位 (yawS, pitchS) 投影到屏幕。
  /// depth ≤ 0 表示在身后，调用方需自行过滤。
  _Proj _project(double yawS, double pitchS, double focal, Offset center) {
    final cosY = math.cos(_yaw), sinY = math.sin(_yaw);
    final cosP = math.cos(_pitch), sinP = math.sin(_pitch);
    final dx = math.sin(yawS) * math.cos(pitchS);
    final dy = -math.sin(pitchS);
    final dz = math.cos(yawS) * math.cos(pitchS);
    final x1 = dx * cosY + dz * sinY;
    final z1 = -dx * sinY + dz * cosY;
    final y2 = dy * cosP + z1 * sinP;
    final z2 = -dy * sinP + z1 * cosP;
    return _Proj(center.dx + focal * x1 / z2, center.dy + focal * y2 / z2, z2);
  }

  /// 深度 → 浓度：越正对越亮，转到侧后方渐渐隐没
  double _depthAlpha(double depth) =>
      ((depth - 0.3) / 0.45).clamp(0.0, 1.0).toDouble();

  // ==========================================================
  // 构建
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 顶部色与渐变首色一致，透明 AppBar 下视觉无缝
      backgroundColor: const Color(0xFF0B1026),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '星语',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 3,
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1026), Color(0xFF1A1F45), Color(0xFF2B1E4E)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final focal = math.max(constraints.maxWidth * 0.62, 160.0);
              final center = Offset(
                constraints.maxWidth / 2,
                constraints.maxHeight / 2,
              );
              return Stack(
                children: [
                  // 远处的星云光斑
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: const _NebulaPainter()),
                    ),
                  ),
                  // 球面上的远景星与银河带
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _twinkle,
                          builder: (context, _) => CustomPaint(
                            painter: _DecoPainter(
                              _projectDecoDots(focal, center),
                              _twinkle.value * math.pi * 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_notes.isEmpty)
                    const Center(
                      child: Text('星星还在赶来的路上',
                          style: TextStyle(color: Colors.white54)),
                    )
                  else
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => _onPanStart(),
                        onPanUpdate: (d) => _onPanUpdate(d, focal),
                        onPanEnd: (d) => _onPanEnd(d, focal),
                        child: Stack(
                          children: [
                            ..._buildNoteStars(focal, center),
                            _topHint(),
                            _bottomHints(),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildNoteStars(double focal, Offset center) {
    // 投影并按深度排序：越靠前的星画得越上层
    final projected = <(_Proj, int)>[];
    for (var i = 0; i < _notes.length; i++) {
      final p = _project(_dirs[i].yaw, _dirs[i].pitch, focal, center);
      if (p.depth > 0.3) projected.add((p, i));
    }
    projected.sort((a, b) => a.$1.depth.compareTo(b.$1.depth));

    final entrance = Curves.easeOutCubic.transform(_entrance.value);
    final stars = <Widget>[];
    for (final (p, i) in projected) {
      final note = _notes[i];
      // 入场：按星星顺序错峰浮现
      final appear = ((entrance - math.min(i, 8) * 0.055) / 0.35)
          .clamp(0.0, 1.0)
          .toDouble();
      final depthAlpha = _depthAlpha(p.depth);
      final starSize = (20 + _noise(i, 51) * 8) *
          (0.78 + 0.22 * depthAlpha) *
          (0.72 + 0.28 * appear);
      final labelAlpha =
          ((p.depth - 0.62) / 0.25).clamp(0.0, 1.0).toDouble() * appear;

      stars.add(Positioned(
        key: ValueKey('star-${note.id}'),
        left: p.x - 42,
        top: p.y - starSize / 2,
        child: Opacity(
          opacity: (depthAlpha * appear).clamp(0.0, 1.0).toDouble(),
          child: _NoteStar(
            size: starSize,
            isNew: !_readIds.contains(note.id),
            twinkleDelayMs: (_noise(i, 52) * 1200).round(),
            label: note.displayDate,
            labelAlpha: labelAlpha,
            onTap: () => _openNote(i),
          ),
        ),
      ));
    }
    return stars;
  }

  List<_DecoProj> _projectDecoDots(double focal, Offset center) {
    final out = <_DecoProj>[];
    for (final d in _decoDots) {
      final p = _project(d.yaw, d.pitch, focal, center);
      if (p.depth <= 0.28) continue;
      out.add(_DecoProj(
        p.x,
        p.y,
        d.radius * (0.8 + 0.3 * p.depth),
        d.alpha * ((p.depth - 0.28) / 0.5).clamp(0.0, 1.0).toDouble(),
        d.color,
        d.twinkleSpeed,
      ));
    }
    return out;
  }

  Widget _topHint() {
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Text(
          '有些话，藏在了星光里',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 1,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }

  Widget _bottomHints() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 20,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '点开星星，看看里面的话',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.38),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '拖动星空，像转地球仪一样到处看看',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.26),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一颗可点的星星：新星星微微闪烁，看过的星星安静亮着。
class _NoteStar extends StatefulWidget {
  const _NoteStar({
    required this.size,
    required this.isNew,
    required this.twinkleDelayMs,
    required this.label,
    required this.labelAlpha,
    required this.onTap,
  });

  final double size;
  final bool isNew;
  final int twinkleDelayMs;
  final String label;
  final double labelAlpha;
  final VoidCallback onTap;

  @override
  State<_NoteStar> createState() => _NoteStarState();
}

class _NoteStarState extends State<_NoteStar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final Animation<double> _glow =
      Tween<double>(begin: 0.5, end: 1).animate(
    CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
  );
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    if (widget.isNew) {
      // 错峰开始闪烁，避免整片星空同频闪动
      _delayTimer = Timer(Duration(milliseconds: widget.twinkleDelayMs), () {
        if (mounted) _ctrl.repeat(reverse: true);
      });
    } else {
      _ctrl.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _NoteStar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 刚被点开（新星 → 已读）：停止闪烁，柔和地亮起
    if (oldWidget.isNew && !widget.isNew) {
      _delayTimer?.cancel();
      _ctrl.animateTo(1, duration: const Duration(milliseconds: 400));
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _glow,
              builder: (context, _) {
                final t = _glow.value; // 0.5~1
                return Icon(
                  Icons.star_rounded,
                  size: widget.size,
                  color: Color.lerp(
                    const Color(0xFFCC9E3A),
                    const Color(0xFFFFE082),
                    t,
                  ),
                  shadows: [
                    Shadow(
                      color:
                          const Color(0xFFFFC94D).withValues(alpha: 0.85 * t),
                      blurRadius: 16 * t,
                    ),
                    Shadow(
                      color: const Color(0xFFFFB300).withValues(alpha: 0.4 * t),
                      blurRadius: 30 * t,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 3),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 10,
                color:
                    Colors.white.withValues(alpha: 0.34 * widget.labelAlpha),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 装饰星点的屏幕投影数据
class _DecoProj {
  const _DecoProj(this.x, this.y, this.radius, this.alpha, this.color,
      this.twinkleSpeed);

  final double x;
  final double y;
  final double radius;
  final double alpha;
  final Color color;
  final double twinkleSpeed;
}

/// 远景星与银河带：随视角转动、轻微呼吸闪烁
class _DecoPainter extends CustomPainter {
  const _DecoPainter(this.dots, this.phase);

  final List<_DecoProj> dots;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in dots) {
      final tw = 0.68 +
          0.32 * math.sin(phase * d.twinkleSpeed + d.twinkleSpeed * 7.3);
      final alpha = (d.alpha * tw).clamp(0.0, 1.0).toDouble();
      if (alpha < 0.02) continue;
      canvas.drawCircle(
        Offset(d.x, d.y),
        d.radius,
        Paint()..color = d.color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DecoPainter oldDelegate) => true;
}

/// 深空里的几团星云微光
class _NebulaPainter extends CustomPainter {
  const _NebulaPainter();

  @override
  void paint(Canvas canvas, Size size) {
    _glow(canvas, size, const Alignment(-0.55, -0.35), 0.75,
        const Color(0xFF7C6CFF), 0.085);
    _glow(canvas, size, const Alignment(0.7, 0.4), 0.85,
        const Color(0xFF3E6CFF), 0.07);
    _glow(canvas, size, const Alignment(0.05, 0.9), 0.7,
        const Color(0xFFFFB300), 0.045);
  }

  void _glow(Canvas canvas, Size size, Alignment align, double radiusFactor,
      Color color, double opacity) {
    final center = align.alongSize(size);
    final radius = size.shortestSide * radiusFactor;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 信纸卡片：点开星星后弹出的内容卡。
class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.index,
    required this.total,
  });

  final SecretNote note;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 34),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFDF7), Color(0xFFFFF3D6)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB300).withValues(alpha: 0.28),
            blurRadius: 44,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, size: 16, color: AppTheme.primary),
              const SizedBox(width: 6),
              Text(
                '第 ${index + 1} 颗星 · 共 $total 颗',
                style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
              ),
              const Spacer(),
              Text(
                note.displayDate,
                style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            note.text,
            style: const TextStyle(
              fontSize: 16,
              height: 1.8,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }
}
