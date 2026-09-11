import 'package:flutter/material.dart';

/// 植物园「想实现程度」= 种什么：草 < 花 < 树（越大越想要）。
///
/// 三级暖色系植物皮肤，贴合光旅之盘暖黄主题：
/// 等级越高，徽章越大、边框越粗、色条越宽、光晕越强，像植物越长越大。
class PlantLevel {
  final int level; // 1..3

  /// 名称：种草 / 种花 / 种树。
  final String name;

  /// emoji 图标（彩色，跨端一致）。
  final String emoji;

  /// 备用矢量图标。
  final IconData icon;

  /// 代表色。
  final Color color;

  /// 卡片边框粗细。
  final double borderWidth;

  /// 卡片左侧色条宽度。
  final double barWidth;

  /// 是否发光（种花起）。
  final bool glow;

  const PlantLevel({
    required this.level,
    required this.name,
    required this.emoji,
    required this.icon,
    required this.color,
    this.borderWidth = 1,
    this.barWidth = 3,
    this.glow = false,
  });

  /// emoji 字号随等级变大（草 14 → 树 22）。
  double get emojiSize => 14 + (level - 1) * 4;

  /// 名称字号随等级变大（草 13 → 树 17）。
  double get nameSize => 13 + (level - 1) * 2;

  static const List<PlantLevel> all = [
    PlantLevel(
      level: 1,
      name: '种草',
      emoji: '🌱',
      icon: Icons.eco,
      color: Color(0xFF8BC34A), // 嫩绿
      borderWidth: 1,
      barWidth: 3,
    ),
    PlantLevel(
      level: 2,
      name: '种花',
      emoji: '🌻',
      icon: Icons.local_florist,
      color: Color(0xFFFFB300), // 暖金（主题色）
      borderWidth: 2,
      barWidth: 4,
      glow: true,
    ),
    PlantLevel(
      level: 3,
      name: '种树',
      emoji: '🌳',
      icon: Icons.park,
      color: Color(0xFF43A047), // 深绿
      borderWidth: 3,
      barWidth: 5,
      glow: true,
    ),
  ];

  /// 取等级配置，自动 clamp 到 1~3。
  static PlantLevel of(int level) => all[level.clamp(1, 3) - 1];
}

/// 等级徽章胶囊：emoji + 名称，随等级变大，带代表色底与描边（花/树发光）。
class PlantBadge extends StatelessWidget {
  final int level;
  final double scale;

  const PlantBadge({super.key, required this.level, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    final lv = PlantLevel.of(level);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
      decoration: BoxDecoration(
        color: lv.color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: lv.color.withValues(alpha: 0.55), width: 1.2),
        boxShadow: lv.glow
            ? [
                BoxShadow(
                  color: lv.color.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 0.3,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(lv.emoji, style: TextStyle(fontSize: lv.emojiSize * scale, height: 1.1)),
          SizedBox(width: 4 * scale),
          Text(
            lv.name,
            style: TextStyle(
              fontSize: lv.nameSize * scale,
              fontWeight: FontWeight.w700,
              color: lv.color,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// 表单里的等级选择器：3 个可点选项（草/花/树），选中放大 + 描边 + 对勾。
class PlantPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const PlantPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('想实现程度',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        const Text('越想要，就种得越大棵 🌱 → 🌻 → 🌳',
            style: TextStyle(fontSize: 12, color: Color(0xFF9B8F85))),
        const SizedBox(height: 10),
        Row(
          children: List.generate(3, (i) {
            final lv = i + 1;
            final conf = PlantLevel.of(lv);
            final selected = lv == value;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: lv == 3 ? 0 : 8),
                child: GestureDetector(
                  onTap: () => onChanged(lv),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: selected ? 14 : 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? conf.color.withValues(alpha: 0.15)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? conf.color : const Color(0xFFE4DCCC),
                        width: selected ? 2 : 1,
                      ),
                      boxShadow: selected && conf.glow
                          ? [
                              BoxShadow(
                                color: conf.color.withValues(alpha: 0.28),
                                blurRadius: 8,
                                spreadRadius: 0.3,
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Text(
                              conf.emoji,
                              style: TextStyle(
                                fontSize: conf.emojiSize * (selected ? 1.25 : 1.0),
                                height: 1.1,
                              ),
                            ),
                            if (selected)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Icon(Icons.check_circle,
                                    size: 15, color: conf.color),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          conf.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? conf.color : const Color(0xFF9B8F85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
