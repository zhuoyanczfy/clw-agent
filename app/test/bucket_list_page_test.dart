import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gifting_app/pages/bucket_form_page.dart';
import 'package:gifting_app/pages/bucket_list_page.dart';

void main() {
  testWidgets('点 FAB 应打开添加心愿页面', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BucketListPage()));
    // 让 _load 的失败 Future 完成（测试环境无网络，走 _error 态）
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 16));
    await tester.pump(const Duration(milliseconds: 100));

    // FAB 存在
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // 点击 FAB（不用 pumpAndSettle：背景可能有无限动画）
    await tester.tap(find.byType(FloatingActionButton), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));

    // 表单页应打开
    expect(find.byType(BucketFormPage), findsOneWidget,
        reason: '点击 + 应跳转到添加心愿页面');
    expect(find.text('添加心愿'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2),
        reason: '表单应含标题与描述两个输入框');
    expect(find.text('添加到心愿清单'), findsOneWidget);
  });

  testWidgets('表单页空标题保存应在输入框标红提示', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BucketFormPage()));
    await tester.pump();

    await tester.tap(find.text('添加到心愿清单'));
    await tester.pump(const Duration(milliseconds: 300));

    // 空标题：输入框标红 + errorText 提示（灰字 hint 易被误认为已填写）
    expect(find.text('写一句想一起做的事吧（灰字只是示例）'), findsOneWidget);

    // 输入内容后错误提示消失
    await tester.enterText(find.byType(TextField).first, '去看一次日出');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('写一句想一起做的事吧（灰字只是示例）'), findsNothing);
  });
}