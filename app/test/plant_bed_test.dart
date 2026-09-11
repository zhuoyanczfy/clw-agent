import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gifting_app/pages/bucket_list_page.dart';
import 'package:gifting_app/pages/plant_bed_form_page.dart';
import 'package:gifting_app/pages/plant_bed_list_page.dart';

void main() {
  testWidgets('植物园右上角可进入花坛页（标题 + 垒花坛 FAB）', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BucketListPage()));
    // 让 _load 的失败 Future 完成（测试环境无网络，走 _error 态）
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 16));
    await tester.pump(const Duration(milliseconds: 100));

    // 点 AppBar 的花坛入口（tooltip 定位，不与文字重名）
    await tester.tap(find.byTooltip('花坛'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(PlantBedListPage), findsOneWidget,
        reason: '点植物园右上角小花图标应进入花坛页');
    expect(find.widgetWithText(AppBar, '花坛'), findsOneWidget);
    expect(find.byTooltip('垒花坛'), findsOneWidget);
  });

  testWidgets('花坛页点 FAB 应打开垒花坛表单页', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PlantBedListPage()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 16));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('垒花坛'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 16));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(PlantBedFormPage), findsOneWidget);
    expect(find.widgetWithText(AppBar, '垒花坛'), findsOneWidget);
    expect(find.text('花坛名称'), findsOneWidget);
    expect(find.text('赏花日（可选）'), findsOneWidget);
    expect(find.text('还没选植物，从下面勾选想一起做的事'), findsOneWidget);
    expect(find.text('垒好花坛 🌷'), findsOneWidget);
  });

  testWidgets('垒花坛：空名称标红，无植物时提示至少一株', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PlantBedFormPage()));
    await tester.pump(const Duration(seconds: 16));
    await tester.pump(const Duration(milliseconds: 100));

    // 空名称：输入框标红 + errorText 提示
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('给这一天起个名字吧（灰字只是示例）'), findsOneWidget);

    // 输入名称但没选植物：snackbar 提示
    await tester.enterText(find.byType(TextField).first, '金陵秋日漫步');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('给这一天起个名字吧（灰字只是示例）'), findsNothing);

    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('花坛里至少要种一株植物 🌱'), findsOneWidget);
  });
}
