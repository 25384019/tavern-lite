// On-device flow: sample card → character page → chat → 舞台 four tabs.
//
//   flutter test integration_test/app_tavern_flow_test.dart -d <device>
//
// It is the one thing a static check cannot show: that the story page still
// builds its 本局 / 状态 / 导演 / 本回合 panel from the ported UI.

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

  testWidgets('the sample card opens a chat with the stage panel', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    await tester.pumpWidget(const ProviderScope(child: TavernLiteApp()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 书架 → 试试示范卡
    expect(find.byKey(const ValueKey('tavern-try-sample')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tavern-try-sample')));
    await tester.pumpAndSettle(const Duration(seconds: 8));

    // 角色页：开始（开场白）
    expect(find.text('开始'), findsWidgets);
    await tester.tap(find.text('开始').first);
    await tester.pumpAndSettle(const Duration(seconds: 8));

    // 聊天页：宽屏时舞台在正文右侧；窄屏（手机）时在右侧抽屉里，先点开。
    if (find.text('本局').evaluate().isEmpty) {
      expect(find.byKey(const ValueKey('bot-action')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bot-action')));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
    expect(find.text('本局'), findsWidgets);
    expect(find.text('状态'), findsWidgets);
    expect(find.text('导演'), findsWidgets);
    expect(find.text('本回合'), findsWidgets);
  });
}
