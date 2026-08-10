import 'dart:async';

import 'package:flutter/material.dart';

import '../services/foodmap_api.dart';
import '../theme.dart';

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
      final splash =
          await FoodmapApi.fetchSplash().timeout(const Duration(seconds: 5));
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '珍惜 · 爱 · 温暖',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Cherish Love Warmth · 专属美食关怀',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 24),
                      GestureDetector(
                        onTap: _finish,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
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
                                fontSize: 13, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
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
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('❤️', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const Text(
              '珍惜 · 爱 · 温暖',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cherish Love Warmth',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
