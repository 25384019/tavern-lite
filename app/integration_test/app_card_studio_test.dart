// On-device: 书架 → AI 角色工坊 → 两档都在、空需求不花钱、高级档的字段能选。
//
//   flutter test integration_test/app_card_studio_test.dart -d <device>
//
// It stops short of generating: that costs tokens and needs a key on the
// device. What it proves is the part a static check cannot — that the page
// opens from the shelf, 快速创作 is the default, 高级创作 actually reveals its
// fields, and the choices land on the controls (not just look selected).

import 'package:dsh_app/app.dart';
import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/tavern/tavern_card_studio.dart';
import 'package:dsh_app/ui/common/capsule_chip.dart';
import 'package:dsh_app/ui/common/segmented_pill.dart';
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

  testWidgets('AI 角色工坊: 快速是默认，高级能展开，空需求不花钱', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    await tester.pumpWidget(const ProviderScope(child: TavernLiteApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    final studio = find.byKey(const ValueKey('tavern-card-studio'));
    expect(studio, findsOneWidget, reason: '书架右上角应该有 AI 制卡');
    await tester.tap(studio);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('AI 角色工坊'), findsWidgets);
    expect(
      find.byKey(const ValueKey('tavern-card-studio-idea')),
      findsOneWidget,
    );
    expect(find.text('快速创作'), findsOneWidget);
    expect(find.text('高级创作'), findsOneWidget);
    expect(find.text('简短'), findsOneWidget);
    expect(find.text('标准'), findsOneWidget);
    expect(find.text('详细'), findsOneWidget);

    // 快速档不该露出高级才有的字段。
    expect(find.byKey(const ValueKey('tavern-card-studio-name')), findsNothing);
    expect(
      find.byKey(const ValueKey('tavern-card-studio-traits')),
      findsNothing,
    );

    // 什么都没写就点：只提示，不发请求。
    await tester.tap(find.byKey(const ValueKey('tavern-card-studio-generate')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('先写一句你想要的角色'), findsWidgets);

    // 切到高级：姓名、身份先出来，其余的在下面（懒加载，滚到才建）。
    await tester.tap(find.text('高级创作'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    final nameField = find.byKey(const ValueKey('tavern-card-studio-name'));
    expect(nameField, findsOneWidget);
    expect(
      find.byKey(const ValueKey('tavern-card-studio-identity')),
      findsOneWidget,
    );

    // 姓名填得进去。
    await tester.enterText(
      find.descendant(of: nameField, matching: find.byType(TextField)),
      '沈青',
    );
    await tester.pumpAndSettle();
    expect(find.text('沈青'), findsOneWidget);

    // 页面往下才有的字段：滚到它出现为止，顺序从下往上不行，只能一路向下。
    Future<void> reveal(Key key, {String? label}) async {
      final finder = find.byKey(key);
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }
      expect(finder, findsOneWidget, reason: '高级创作应该露出 ${label ?? key}');
    }

    // 世界观：先自己打字（自由输入），再点右边箭头从常见项里挑一个。
    await reveal(const ValueKey('tavern-card-studio-world'), label: '世界观');
    final worldField = find.byKey(const ValueKey('tavern-card-studio-world'));
    await tester.enterText(
      find.descendant(of: worldField, matching: find.byType(TextField)),
      '雨港',
    );
    await tester.pumpAndSettle();
    expect(find.text('雨港'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('tavern-card-studio-world-pick')),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('studio-pick-校园')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('studio-pick-校园')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('校园'), findsOneWidget);

    // 与玩家关系：同样能自己写。
    await reveal(const ValueKey('tavern-card-studio-relation'), label: '关系');
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('tavern-card-studio-relation')),
        matching: find.byType(TextField),
      ),
      '房东与租客',
    );
    await tester.pumpAndSettle();
    expect(find.text('房东与租客'), findsOneWidget);

    // 性格标签：点了就真的选中。
    await reveal(const ValueKey('tavern-card-studio-traits'), label: '性格标签');
    await tester.ensureVisible(find.text('毒舌'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('毒舌'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CapsuleChoiceChip>(
            find.widgetWithText(CapsuleChoiceChip, '毒舌'),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<CapsuleChoiceChip>(
            find.widgetWithText(CapsuleChoiceChip, '温柔'),
          )
          .selected,
      isFalse,
    );

    // 补充设定。
    await reveal(const ValueKey('tavern-card-studio-extra'), label: '补充设定');

    // 篇幅：切到详细，控件状态要跟着变。
    await reveal(const ValueKey('tavern-card-studio-length'), label: '篇幅');
    await tester.tap(find.text('详细'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedPill<TavernCardLength>>(
            find.byKey(const ValueKey('tavern-card-studio-length')),
          )
          .selected,
      TavernCardLength.rich,
    );
    // 一圈点下来没跳走：还在这一页。（顶部那行已经滚出懒加载范围，
    // 所以不按「高级创作」再断言，篇幅的状态上面已经验过了。）
    expect(find.text('详细'), findsWidgets);
  });
}
