// On-device: 世界书条目里让 AI 改写一条，采用后存进书里。
//
//   flutter test integration_test/app_lorebook_entry_ai_test.dart -d <device>
//
// 从书页点进条目（和用户走同一条路），再走 AI。

import 'dart:convert';
import 'dart:io';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/tavern/lorebook_ai.dart';
import 'package:dsh_app/tavern/lorebook_new.dart';
import 'package:dsh_app/tavern/tavern_provider.dart';
import 'package:dsh_app/ui/tavern/tavern_library_book_page.dart';
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

  testWidgets('条目 AI：写长 → 采用 → 保存 → 书里变了', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    final dir = await Directory.systemTemp.createTemp('entry_ai_test');
    final tavern = await openTavern('${dir.path}/tavern');
    addTearDown(() async {
      await tavern.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final id = newLorebookId();
    await tavern.putLorebook(id, {
      ...emptyLorebookJson('雨港'),
      'entries': lorebookEntriesJson(const [
        LorebookDraftEntry(title: '码头', content: '潮水一天两次。', keys: ['码头', '潮水']),
      ]),
    });

    final client = TavernModelClient(
      clientFactory: () => MockClient(
        (request) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '潮水一天两次，第一次来的人常被困住，要等第二天退潮。',
                },
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
          home: TavernLibraryBookPage(bookId: id),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 点进条目
    await tester.tap(find.byKey(const ValueKey('tavern-library-entry-0')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('tavern-lore-content')), findsOneWidget);

    // ✨ → 写长一些（按钮在内容格上，先滚到可见，否则点会落空）
    final sparkle = find.byKey(const ValueKey('tavern-lore-ai'));
    await tester.ensureVisible(sparkle);
    await tester.pumpAndSettle();
    await tester.tap(sparkle);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('tavern-lore-ai-expand')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('tavern-lore-ai-go')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(
      find.byKey(const ValueKey('tavern-lore-ai-preview')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('tavern-lore-ai-adopt')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 保存
    await tester.tap(find.byKey(const ValueKey('tavern-lore-save')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    final raw = (await tavern.lorebook(id))!;
    final entry = (raw['entries']! as Map).values
        .cast<Map<String, Object?>>()
        .first;
    expect(entry['content'], contains('第二天退潮'));
  });
}
