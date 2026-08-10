// APP 冒烟测试：验证主框架能正常构建并显示底部导航
import 'package:flutter_test/flutter_test.dart';

import 'package:gifting_app/main.dart';

void main() {
  testWidgets('主框架冒烟测试', (WidgetTester tester) async {
    // 加载页依赖网络，测试直接进入主框架
    await tester.pumpWidget(const GiftingApp(showSplash: false));
    await tester.pump(const Duration(seconds: 1));

    // 底部导航三个 Tab 存在
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('美食'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
