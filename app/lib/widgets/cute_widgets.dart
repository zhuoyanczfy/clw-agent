import 'dart:async';

import 'package:flutter/material.dart';

/// Q 版通用动效组件集：软糖按压、心跳、弹性入场、数字滚动、三点跳动等。
/// 全部基于 Flutter 内置动画实现，零额外依赖、不增加 APK 体积。

// ---- 软糖按压：按下缩小、松开回弹（保留 ripple） ----
class SquishyTap extends StatefulWidget {
  const SquishyTap({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final BorderRadius? borderRadius;

  @override
  State<SquishyTap> createState() => _SquishyTapState();
}

class _SquishyTapState extends State<SquishyTap> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? widget.pressedScale : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (v) => setState(() => _pressed = v),
        borderRadius: widget.borderRadius,
        child: widget.child,
      ),
    );
  }
}

// ---- 循环心跳：像果冻一样「怦怦」跳 ----
class HeartBeat extends StatefulWidget {
  const HeartBeat({
    super.key,
    required this.child,
    this.maxScale = 1.12,
    this.duration = const Duration(milliseconds: 950),
  });

  final Widget child;
  final double maxScale;
  final Duration duration;

  @override
  State<HeartBeat> createState() => _HeartBeatState();
}

class _HeartBeatState extends State<HeartBeat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat(reverse: true);
  late final Animation<double> _scale = Tween<double>(
    begin: 1.0,
    end: widget.maxScale,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

// ---- 弹性入场：从小到大「啵」地弹出来（支持延迟错峰） ----
class BouncyIn extends StatefulWidget {
  const BouncyIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 600),
    this.offsetY = 24,
    this.curve = Curves.elasticOut,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;
  final Curve curve;

  @override
  State<BouncyIn> createState() => _BouncyInState();
}

class _BouncyInState extends State<BouncyIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _ctrl,
    curve: widget.curve,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        // elasticOut 会过冲（t > 1），缩放/透明度按 0~1 截断，保留过冲感
        final t = _t.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, widget.offsetY * (1 - t)),
            child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
          ),
        );
      },
    );
  }
}

// ---- 数字滚动：从 0 快速滚动到目标值 ----
class BouncyNumber extends StatelessWidget {
  const BouncyNumber({
    super.key,
    required this.value,
    required this.style,
    this.duration = const Duration(milliseconds: 700),
  });

  final int value;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('$v', style: style),
    );
  }
}

// ---- 底部导航图标：选中时弹跳一下 ----
class BounceNavIcon extends StatefulWidget {
  const BounceNavIcon({
    super.key,
    required this.selected,
    required this.icon,
    required this.selectedIcon,
  });

  final bool selected;
  final Widget icon;
  final Widget selectedIcon;

  @override
  State<BounceNavIcon> createState() => _BounceNavIconState();
}

class _BounceNavIconState extends State<BounceNavIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.5,
        end: 1.3,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 55,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.3,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 45,
    ),
  ]).animate(_ctrl);

  @override
  void initState() {
    super.initState();
    // 未选中停在正常大小；初始选中的 tab 也弹一次
    if (widget.selected) {
      _ctrl.forward(from: 0);
    } else {
      _ctrl.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(BounceNavIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.selected && widget.selected) {
      _ctrl.forward(from: 0);
    } else if (oldWidget.selected && !widget.selected) {
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: widget.selected ? widget.selectedIcon : widget.icon,
    );
  }
}

// ---- 「正在输入」三点跳动 ----
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.color = const Color(0xFFB0A79E)});

  final Color color;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: EdgeInsets.only(right: i < 2 ? 5 : 0),
            child: _dot(i),
          ),
      ],
    );
  }

  Widget _dot(int i) {
    final anim = CurvedAnimation(
      parent: _ctrl,
      curve: Interval(i * 0.15, 0.6 + i * 0.15, curve: Curves.easeInOut),
    );
    return AnimatedBuilder(
      animation: anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
      builder: (context, child) =>
          Transform.scale(scale: 0.6 + 0.55 * anim.value, child: child),
    );
  }
}

// ---- Q 版页面转场：缩放 + 淡入（挂在 PageTransitionsTheme 全局生效） ----
class CutePageTransitionsBuilder extends PageTransitionsBuilder {
  const CutePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}
