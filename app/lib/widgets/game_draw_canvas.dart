import 'package:flutter/material.dart';

import '../models/game.dart';

/// 只读画板：白底圆角 4:3 画布渲染笔画（猜者看画、战绩回顾共用）。
class GameDrawCanvas extends StatelessWidget {
  const GameDrawCanvas({
    super.key,
    required this.strokes,
    this.eraserHint = false,
  });

  final List<GameStroke> strokes;
  final bool eraserHint; // 画者视角：橡皮白笔渲染成浅灰便于自见

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x1A000000)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: CustomPaint(
            painter: GameStrokesPainter(strokes, eraserHint: eraserHint),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

/// 笔画绘制器：每笔独立颜色/线宽；单点画圆；橡皮白笔可选渲染成浅灰。
class GameStrokesPainter extends CustomPainter {
  GameStrokesPainter(this.strokes, {this.eraserHint = false});

  final List<GameStroke> strokes;
  final bool eraserHint;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      // 橡皮存的是白笔：画者本地渲染成浅灰便于看见轨迹，猜者按真白渲染
      final c = eraserHint && stroke.color == 0xFFFFFFFF
          ? 0xFFBDBDBD
          : stroke.color;
      final paint = Paint()
        ..color = Color(c)
        ..strokeWidth = (stroke.width * size.width).clamp(1.5, 60.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (stroke.points.length == 1) {
        // 单点也画个圆点，方便画"点睛"
        final p = stroke.points.first;
        canvas.drawCircle(
          Offset(p.dx * size.width, p.dy * size.height),
          paint.strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
        continue;
      }
      final path = Path()
        ..moveTo(stroke.points.first.dx * size.width,
            stroke.points.first.dy * size.height);
      for (final p in stroke.points.skip(1)) {
        path.lineTo(p.dx * size.width, p.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant GameStrokesPainter old) =>
      !identical(old.strokes, strokes);
}
