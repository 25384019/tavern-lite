// On-device: 资源库 → 世界书 → ＋ → 新建空白书 → 起名 → 进条目页 → 加一条 → 存住。
//
//   flutter test integration_test/app_lorebook_new_test.dart -d <device>
//
// 验的是这条链上没有一处是"画出来的"：书真的写进引擎（putLorebook 当 create），
// 条目真的落盘，返回列表能看到那一条。

import 'package:dsh_app/app.dart';
import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/state/settings_state.dart';
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

  testWidgets('新建一本空白世界书，加一条，再回列表看得到', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    await tester.pumpWidget(const ProviderScope(child: TavernLiteApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 首页 → 资源库 → 世界书
    await tester.tap(find.text('资源库'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('tavern-library-lorebooks')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 右上角 ＋ → 新建空白书
    await tester.tap(find.byKey(const ValueKey('tavern-lorebook-import')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(
      find.byKey(const ValueKey('tavern-lorebook-add-create')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('tavern-lorebook-add-create')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 起名字
    await tester.enterText(find.byType(TextField).last, '雨港');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tavern-lorebook-create-ok')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 空书的条目页：标题是书名，正文是"开始写"的提示
    expect(find.text('雨港'), findsWidgets);
    expect(
      find.byKey(const ValueKey('tavern-library-book-empty')),
      findsOneWidget,
    );

    // 加一条
    await tester.tap(find.byKey(const ValueKey('tavern-library-book-add')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.enterText(
      find.byKey(const ValueKey('tavern-lore-name')),
      '码头',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('tavern-lore-content')),
      '潮水一天两次，第一次来的人总会被困住。',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('tavern-lore-keys')),
      '码头，潮水',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tavern-lore-save')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 回到书的条目页：那一条在，而且有关键词
    expect(find.text('码头'), findsWidgets);
    expect(find.textContaining('潮水'), findsWidgets);

    // 编辑页很长，底下的段落在懒加载区里，滚到才建。
    Future<void> reveal(Finder finder) async {
      if (finder.evaluate().isNotEmpty) {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        return;
      }
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    // 再打开它：把专业触发规则改一遍（默认折叠的那一段）
    await tester.tap(find.text('码头').first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await reveal(find.byKey(const ValueKey('tavern-lore-advanced-toggle')));
    await tester.tap(find.byKey(const ValueKey('tavern-lore-advanced-toggle')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await reveal(find.byKey(const ValueKey('tavern-lore-regex')));
    expect(find.text('正则触发'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('tavern-lore-regex')));
    await tester.pumpAndSettle();

    await reveal(find.byKey(const ValueKey('tavern-lore-exclude-recursion')));
    await tester.tap(
      find.byKey(const ValueKey('tavern-lore-exclude-recursion')),
    );
    await tester.pumpAndSettle();

    await reveal(find.byKey(const ValueKey('tavern-lore-group')));
    await tester.enterText(
      find.byKey(const ValueKey('tavern-lore-group')),
      '港口',
    );
    await tester.pumpAndSettle();

    // 两个递归开关一起开 = 永远不激活：保存要被挡下来，并说清楚为什么。
    await reveal(find.byKey(const ValueKey('tavern-lore-delay-recursion')));
    // ?????????0 = ??????+?? 1 ??
    await tester.tap(
      find.byKey(const ValueKey('tavern-lore-delay-recursion-up')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tavern-lore-save')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('永远不生效'), findsWidgets, reason: '冲突要说出来');
    expect(
      find.byKey(const ValueKey('tavern-lore-save')),
      findsOneWidget,
      reason: '被挡下就该留在编辑页',
    );
    // 关掉一个，存得下去。
    await reveal(find.byKey(const ValueKey('tavern-lore-delay-recursion')));
    await tester.tap(
      find.byKey(const ValueKey('tavern-lore-delay-recursion-down')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tavern-lore-save')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 重新打开：值是从引擎里读回来的，不是界面上留着的
    await tester.tap(find.text('码头').first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await reveal(find.byKey(const ValueKey('tavern-lore-advanced-toggle')));
    await tester.tap(find.byKey(const ValueKey('tavern-lore-advanced-toggle')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await reveal(find.byKey(const ValueKey('tavern-lore-exclude-recursion')));
    expect(
      tester
          .widget<Switch>(
            find.descendant(
              of: find.byKey(const ValueKey('tavern-lore-exclude-recursion')),
              matching: find.byType(Switch),
            ),
          )
          .value,
      isTrue,
      reason: '递归开关应该存住',
    );
    await reveal(find.byKey(const ValueKey('tavern-lore-regex')));
    expect(
      tester
          .widget<Switch>(
            find.descendant(
              of: find.byKey(const ValueKey('tavern-lore-regex')),
              matching: find.byType(Switch),
            ),
          )
          .value,
      isTrue,
      reason: '正则开关应该存住',
    );
    await reveal(find.byKey(const ValueKey('tavern-lore-group')));
    expect(find.text('港口'), findsWidgets, reason: '分组名应该存住');
  });
}
