import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gifting_app/pages/secret_notes_page.dart';
import 'package:gifting_app/pages/settings_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('星语页渲染兜底星星，点开第一颗显示内容卡片', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SecretNotesPage()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2)); // 星星入场

    expect(find.widgetWithText(AppBar, '星语'), findsOneWidget);
    expect(find.text('有些话，藏在了星光里'), findsOneWidget);
    expect(find.text('点开星星，看看里面的话'), findsOneWidget);

    // 点第一颗星（兜底数据 seed-1，初始落在眼前）
    await tester.tap(find.byKey(const ValueKey('star-seed-1')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('第 1 颗星'), findsOneWidget,
        reason: '点开星星应弹出信纸卡片');
    expect(find.textContaining('被你找到啦'), findsOneWidget,
        reason: '卡片应展示碎碎念正文');
  });

  testWidgets('三颗兜底星星各带日期标注', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SecretNotesPage()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2));

    expect(find.textContaining('9月16日'), findsNWidgets(3));
  });

  testWidgets('像转地球仪一样拖动星空，松手后停在新位置不回弹', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SecretNotesPage()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2)); // 入场结束

    final star = find.byKey(const ValueKey('star-seed-1'));
    final before = tester.getCenter(star);

    await tester.drag(star, const Offset(-90, 50));
    await tester.pump();
    final moved = tester.getCenter(star);
    expect((moved - before).distance, greaterThan(10),
        reason: '拖动时星空应跟着转到新位置');

    await tester.pump(const Duration(seconds: 2));
    final later = tester.getCenter(star);
    expect((later - moved).distance, lessThan(1),
        reason: '松手后应停留在移到的位置，不弹回');
  });

  testWidgets('快速甩动星空会带着惯性滑一小段再停稳', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SecretNotesPage()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2)); // 入场结束

    final star = find.byKey(const ValueKey('star-seed-1'));
    await tester.fling(star, const Offset(-60, 0), 1000);
    await tester.pump(); // 松手，惯性滑行开始
    final p1 = tester.getCenter(star);
    await tester.pump(const Duration(milliseconds: 250));
    final p2 = tester.getCenter(star);
    expect((p2 - p1).distance, greaterThan(3),
        reason: '松手后应带着惯性继续滑');

    await tester.pump(const Duration(seconds: 4)); // 等滑行衰减结束
    final p3 = tester.getCenter(star);
    await tester.pump(const Duration(seconds: 2));
    final p4 = tester.getCenter(star);
    expect((p4 - p3).distance, lessThan(0.5),
        reason: '滑行结束后应稳稳停住');
  });

  testWidgets('设置页小星星入口可打开星语页，且看起来只是装饰', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pump(const Duration(milliseconds: 200));

    final star = find.byIcon(Icons.star_rounded);
    expect(star, findsOneWidget, reason: '设置页底部应有唯一的装饰小星');

    await tester.ensureVisible(star);
    await tester.pump();
    await tester.tap(star);
    await tester.pump(const Duration(milliseconds: 500)); // 星星闪光
    await tester.pump(const Duration(seconds: 1)); // 页面转场

    expect(find.byType(SecretNotesPage), findsOneWidget);
  });
}
