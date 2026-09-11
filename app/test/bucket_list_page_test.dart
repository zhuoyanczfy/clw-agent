import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gifting_app/pages/bucket_form_page.dart';
import 'package:gifting_app/pages/bucket_list_page.dart';

void main() {
  testWidgets('点 FAB 应打开种草表单页（含三级植物选择器）', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BucketListPage()));
    // 让 _load 的失败 Future 完成（测试环境无网络，走 _error 态）
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 16));
    await tester.pump(const Duration(milliseconds: 100));

    // 列表页标题为「植物园」，FAB 存在
    expect(find.widgetWithText(AppBar, '植物园'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // 点击 FAB（不用 pumpAndSettle：背景可能有无限动画）
    await tester.tap(find.byType(FloatingActionButton), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));

    // 表单页应打开
    expect(find.byType(BucketFormPage), findsOneWidget,
        reason: '点击 + 应跳转到种草表单页');
    expect(find.widgetWithText(AppBar, '种草'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2),
        reason: '表单应含标题与描述两个输入框');

    // 三级植物选择器：种草 / 种花 / 种树（"种草"与 AppBar 标题重名，故用 2）
    expect(find.text('想实现程度'), findsOneWidget);
    expect(find.text('种草'), findsNWidgets(2));
    expect(find.text('种花'), findsOneWidget);
    expect(find.text('种树'), findsOneWidget);

    // 提交按钮
    expect(find.text('种下 🌱'), findsOneWidget);
  });

  testWidgets('等级选择器可切到种树', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BucketFormPage()));
    await tester.pump();

    // 点「种树」选项后不应报错，且仍可渲染
    await tester.tap(find.text('种树'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('种树'), findsOneWidget);
    expect(find.text('种下 🌱'), findsOneWidget);
  });

  testWidgets('表单页空标题保存应在输入框标红提示', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BucketFormPage()));
    await tester.pump();

    await tester.tap(find.text('种下 🌱'));
    await tester.pump(const Duration(milliseconds: 300));

    // 空标题：输入框标红 + errorText 提示（灰字 hint 易被误认为已填写）
    expect(find.text('写一句想一起做的事吧（灰字只是示例）'), findsOneWidget);

    // 输入内容后错误提示消失
    await tester.enterText(find.byType(TextField).first, '去看一次日出');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('写一句想一起做的事吧（灰字只是示例）'), findsNothing);
  });
}
