// On-device: 预设能从应用里新建、能在列表里看到、能复制。
//
//   flutter test integration_test/app_preset_new_test.dart -d <device>

import 'dart:io';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/tavern/tavern_provider.dart';
import 'package:dsh_app/ui/tavern/tavern_presets_page.dart';
import 'package:dsh_app/ui/theme/theme.dart';
import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('新建预设 → 列表里有 → 复制一份', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    final dir = await Directory.systemTemp.createTemp('preset_ui_test');
    final tavern = await openTavern('${dir.path}/tavern');
    addTearDown(() async {
      await tavern.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [tavernProvider.overrideWithValue(tavern)],
        child: MaterialApp(
          locale: AppLocale.zhCN,
          supportedLocales: AppLocale.supported,
          localizationsDelegates: const [
            L10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildLightTheme(glyphLocale: AppLocale.zhCN),
          home: const TavernPresetsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 新建
    await tester.tap(find.byKey(const ValueKey('tavern-preset-new')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.enterText(
      find.byKey(const ValueKey('tavern-preset-new-name')),
      '我的预设',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tavern-preset-new-ok')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 建完会直接进编辑页，先退回来
    final editPage = find.byType(Scaffold).last;
    if (find.text('我的预设').evaluate().isNotEmpty) {
      Navigator.of(tester.element(editPage)).maybePop();
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    // 引擎里有它
    final presets = await tavern.listPresets();
    expect(presets.map((p) => p.name), contains('我的预设'));
    final created = presets.firstWhere((p) => p.name == '我的预设');
    final full = await tavern.preset(created.id);
    expect(full, isNotNull);
    expect(full!.raw['temperature'], 0.8);
    expect((full.raw['prompts']! as List), hasLength(1));

    // 列表里也看得到
    expect(find.text('我的预设'), findsWidgets);

    // 复制一份
    await tester.tap(find.text('我的预设').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.text('复制一份'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    final after = await tavern.listPresets();
    expect(after, hasLength(2));
    expect(after.map((p) => p.name), contains('我的预设 副本'));
  });
}
