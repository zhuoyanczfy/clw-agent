import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/foodmap_api.dart';
import '../theme.dart';
import '../widgets/cute_widgets.dart';

/// 启动加载页：从后端拉取当日随机图片展示，至少停留 1.5 秒；
/// 5 秒超时、未配置后端或拉图失败时直接进入主界面（不阻塞使用）。
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.onFinished});

  /// 展示结束后回调（由外层切换到主界面）
  final VoidCallback onFinished;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  String? _fullUrl;
  bool _ready = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    // 至少停留 1.5 秒，避免闪一下就走
    final minShow = Future<void>.delayed(const Duration(milliseconds: 1500));
    try {
      final splash = await FoodmapApi.fetchSplash().timeout(
        const Duration(seconds: 5),
      );
      final fullUrl = await FoodmapApi.mediaUrl(splash.url);
      // 至少停留 1.5 秒，避免闪一下就走
      await minShow;
      if (!mounted) return;
      if (splash.url.isEmpty) {
        _finish();
        return;
      }
      setState(() {
        _fullUrl = fullUrl;
        _ready = true;
      });
      // 图片展示 2 秒后自动进入主界面，也可点「跳过」
      _timer = Timer(const Duration(seconds: 2), _finish);
    } catch (_) {
      await minShow;
      if (!mounted) return;
      _finish();
    }
  }

  void _finish() {
    _timer?.cancel();
    if (!mounted) return;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _ready && _fullUrl != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  _fullUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : _brandPlaceholder(),
                  errorBuilder: (_, _, _) => _brandPlaceholder(),
                ),
                // 底部渐变遮罩，保证文字可读
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black45],
                      stops: [0.55, 1.0],
                    ),
                  ),
                ),
                // 品牌文字
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 56,
                  child: BouncyIn(
                    offsetY: 30,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Compass of Light',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const Text(
                          '& Wanderlust',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: _finish,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                            child: const Text(
                              '跳过 ›',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : _brandPlaceholder(),
    );
  }

  /// 无图片/加载中/加载失败时的品牌渐变背景
  Widget _brandPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primary, AppTheme.primaryDark],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _FloatingHearts(),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // logo 弹性入场后持续心跳
                BouncyIn(
                  child: HeartBeat(
                    maxScale: 1.15,
                    child: const Text('❤️', style: TextStyle(fontSize: 56)),
                  ),
                ),
                const SizedBox(height: 16),
                BouncyIn(
                  delay: const Duration(milliseconds: 180),
                  offsetY: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Compass of Light',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        '& Wanderlust',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                BouncyIn(
                  delay: const Duration(milliseconds: 360),
                  child: const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 加载页飘浮的爱心粒子（固定种子随机分布，循环上浮淡出）
class _FloatingHearts extends StatefulWidget {
  const _FloatingHearts();

  @override
  State<_FloatingHearts> createState() => _FloatingHeartsState();
}

class _FloatingHeartsState extends State<_FloatingHearts>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..repeat();

  late final List<_HeartParticle> _particles = _makeParticles();

  static List<_HeartParticle> _makeParticles() {
    final rnd = math.Random(7); // 固定种子，保证每次布局一致
    const glyphs = ['❤️', '💕', '💖', '✨', '🫧'];
    return List.generate(9, (i) {
      return _HeartParticle(
        glyph: glyphs[i % glyphs.length],
        dx: 0.06 + rnd.nextDouble() * 0.88,
        phase: rnd.nextDouble(),
        size: 14 + rnd.nextDouble() * 14,
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            return Stack(
              children: [
                for (final p in _particles)
                  Positioned(
                    left: p.dx * w - 20,
                    top: (1 - ((t + p.phase) % 1.0)) * h - 20,
                    child: Opacity(
                      opacity: math.sin(math.pi * ((t + p.phase) % 1.0)),
                      child: Text(p.glyph, style: TextStyle(fontSize: p.size)),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _HeartParticle {
  final String glyph;
  final double dx; // 水平位置（0~1）
  final double phase; // 相位偏移
  final double size;

  _HeartParticle({
    required this.glyph,
    required this.dx,
    required this.phase,
    required this.size,
  });
}
