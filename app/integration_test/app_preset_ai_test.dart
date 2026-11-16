// On-device: 预设里让 AI 写一段提示词，采用后真的存进那条提示。
//
//   flutter test integration_test/app_preset_ai_test.dart -d <device>

import 'dart:convert';
import 'dart:io';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/tavern/preset_new.dart';
import 'package:dsh_app/tavern/tavern_provider.dart';
import 'package:dsh_app/ui/tavern/tavern_preset_page.dart';
import 'package:dsh_app/ui/theme/theme.dart';
import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AI 写提示词：候选 → 采用 → 存进预设', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    final dir = await Directory.systemTemp.createTemp('preset_ai_test');
    final tavern = await openTavern('${dir.path}/tavern');
    addTearDown(() async {
      await tavern.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final id = await createEmptyPreset(tavern, name: '我的预设');

    final client = TavernModelClient(
      clientFactory: () => MockClient(
        (request) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': '你要写得短。每段不超过三句。'},
                'finish_reason': 'stop',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tavernProvider.overrideWithValue(tavern),
          tavernModelClientProvider.overrideWithValue(client),
          tavernModelConfigProvider.overrideWithValue(
            TavernModelConfig(
              apiKey: () async => 'test-key',
              baseUrl: 'https://example.test/v1',
              model: 'deepseek-chat',
              deepseek: false,
              stream: false,
            ),
          ),
        ],
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
          home: TavernPresetPage(presetId: id),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 提示词在页面下面，先滚出来
    final promptRow = find.byKey(const ValueKey('tavern-preset-prompt-main'));
    for (var i = 0; i < 10 && promptRow.evaluate().isEmpty; i++) {
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
    }
    expect(promptRow, findsOneWidget, reason: '该有那条主提示');

    // 打开那条提示
    await tester.tap(promptRow);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // ✨ → 从头写
    await tester.tap(find.byKey(const ValueKey('tavern-prompt-ai')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('tavern-prompt-ai-write')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 想要什么（留空也行，这里填一句）
    await tester.enterText(
      find.byKey(const ValueKey('tavern-prompt-ai-instruction')),
      '更冷漠',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tavern-prompt-ai-go')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 候选出现，采用
    expect(
      find.byKey(const ValueKey('tavern-prompt-ai-preview')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('tavern-prompt-ai-adopt')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 引擎里那条提示的内容变了
    final preset = await tavern.preset(id);
    final prompts = (preset!.raw['prompts']! as List)
        .cast<Map<String, Object?>>();
    final main = prompts.firstWhere((p) => p['identifier'] == 'main');
    expect(main['content'], contains('每段不超过三句'));
  });
}
