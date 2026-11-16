// On-device: 工坊 → 专业创作 → 九个模块 → 填字、锁、撤销 → 预览 → 存进书架。
//
//   flutter test integration_test/app_studio_test.dart -d <device>
//
// P0 的地基在真机上跑通一遍：模块列表、字段编辑、撤销真的退回去、
// 预览里的描述是转换器拼出来的、存完能进角色页。

import 'package:dsh_app/app.dart';
import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/ui/tavern/tavern_studio_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final container = ProviderContainer();
    await container.read(settingsProvider.notifier).ready;
    container.dispose();
  });

  testWidgets('专业创作跑通一遍：模块、字段、锁、撤销、预览、存卡', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    await tester.pumpWidget(const ProviderScope(child: TavernLiteApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 书架右上角魔法棒 → 工坊 → 专业创作。
    await tester.tap(find.byKey(const ValueKey('tavern-card-studio')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('tavern-card-studio-pro')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('专业创作'), findsWidgets);

    // 九个模块一个一个列出来（后面几个在懒加载区，滚到才建）。
    for (final id in ['profile', 'mind', 'bond']) {
      expect(
        find.byKey(ValueKey('studio-module-$id')),
        findsOneWidget,
        reason: '缺少模块 $id',
      );
    }
    for (final id in ['world', 'voice', 'rules', 'soul']) {
      final finder = find.byKey(ValueKey('studio-module-$id'));
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }
      expect(finder, findsOneWidget, reason: '缺少模块 $id');
    }

    // 回到顶部，进 人物档案。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('studio-module-profile')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-module-profile')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 填姓名。
    final nameRow = find.byKey(const ValueKey('studio-field-name'));
    expect(nameRow, findsOneWidget);
    final nameInput = find.descendant(
      of: nameRow,
      matching: find.byType(TextField),
    );
    await tester.enterText(nameInput, '沈青');
    await tester.pumpAndSettle();

    // 第一次写：没有上一版可退，撤销是灰的。
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('studio-undo-name')))
          .onPressed,
      isNull,
      reason: '刚写第一版不该有撤销',
    );

    // 再改一次：现在能撤销，撤销要真的把字退回去。
    await tester.enterText(nameInput, '沈青。');
    await tester.pumpAndSettle();
    final undo = find.byKey(const ValueKey('studio-undo-name'));
    expect(tester.widget<IconButton>(undo).onPressed, isNotNull);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(nameInput).controller!.text, '沈青');

    // 锁定姓名。
    await tester.tap(find.byKey(const ValueKey('studio-lock-name')));
    await tester.pumpAndSettle();

    // 外貌是必填，不填不让存。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('studio-field-appearance')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('studio-field-appearance')),
        matching: find.byType(TextField),
      ),
      '短发，围裙上有洗不掉的酱油点。',
    );
    await tester.pumpAndSettle();

    // 回模块列表：进度得跟着涨。（这页面是自绘返回键，pageBack 找不到。）
    Navigator.of(tester.element(find.byType(TavernStudioModulePage))).pop();
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('2/12'), findsWidgets, reason: '姓名 + 外貌两个字段有内容');

    // 预览：描述是转换器拼的，能看到外貌。
    await tester.tap(find.byKey(const ValueKey('studio-preview')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('短发'), findsWidgets);
    expect(find.byKey(const ValueKey('studio-save')), findsOneWidget);

    // 存进书架，落到角色页。
    await tester.tap(find.byKey(const ValueKey('studio-save')));
    await tester.pumpAndSettle(const Duration(seconds: 4));
    expect(find.text('沈青'), findsWidgets);
  });
}
