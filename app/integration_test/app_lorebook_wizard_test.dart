// On-device: 世界书工坊四步走完，最后落成一本真书。
//
//   flutter test integration_test/app_lorebook_wizard_test.dart -d <device>
//
// 假传输层按调用次数回四种答案（蓝图 / 规划 / 正文 / 审查），其余都是真的：
// 真页面、真解析、真引擎、真落盘。

import 'dart:convert';
import 'dart:io';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/tavern/tavern_provider.dart';
import 'package:dsh_app/ui/tavern/tavern_lorebook_wizard_page.dart';
import 'package:dsh_app/ui/theme/theme.dart';
import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

const _replies = [
  // 1 蓝图
  '{"name":"雨港","overview":"一年下三百天雨的海港城，靠盐和船活着。",'
      '"rules":["没有晴天"],"factions":["盐行"],"places":["码头"],"conflicts":["盐行要涨税"]}',
  // 2 规划
  '{"entries":[{"title":"码头","kind":"place","why":"开场"},'
      '{"title":"盐行","kind":"faction","why":"权力"}]}',
  // 3 正文
  '{"entries":[{"title":"码头","content":"潮水一天两次，第一次来的人常被困住。",'
      '"keys":["码头","潮水"]},'
      '{"title":"盐行","content":"盐行的账房不点钱，只点盐袋。","keys":["盐行"],"constant":true}]}',
  // 4 审查
  '{"issues":[{"title":"码头","issue":"和规则不冲突，但没提雨","suggest":"加一句雨"}]}',
];

/// 往下滚三屏：内容只会越长越多，固定步长就够。
Future<void> _scrollDown(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('世界书工坊：蓝图 → 规划 → 正文 → 检查 → 存成一本', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    final dir = await Directory.systemTemp.createTemp('wizard_test');
    final tavern = await openTavern('${dir.path}/tavern');
    addTearDown(() async {
      await tavern.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    var call = 0;
    final client = TavernModelClient(
      clientFactory: () => MockClient((request) async {
        final reply = _replies[call.clamp(0, _replies.length - 1)];
        call++;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': reply},
                'finish_reason': 'stop',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
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
          home: const TavernLorebookWizardPage(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 1. 灵感 → 蓝图
    await tester.enterText(
      find.byKey(const ValueKey('lorebook-wizard-idea')),
      '一年下三百天雨的海港城',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lorebook-wizard-blueprint')));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(call, 1, reason: '应该只发了一次请求');
    await _scrollDown(tester);
    expect(find.text('雨港'), findsWidgets, reason: '蓝图要出来');

    // 2. 规划
    await _scrollDown(tester);
    await tester.tap(find.byKey(const ValueKey('lorebook-wizard-plan')));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await _scrollDown(tester);
    expect(
      find.byKey(const ValueKey('lorebook-wizard-plan-码头')),
      findsOneWidget,
    );

    // 3. 写正文
    await _scrollDown(tester);
    await tester.tap(find.byKey(const ValueKey('lorebook-wizard-write')));
    await tester.pumpAndSettle(const Duration(seconds: 4));
    await _scrollDown(tester);
    expect(
      find.byKey(const ValueKey('lorebook-wizard-entry-码头')),
      findsOneWidget,
    );

    // 4. 检查
    await _scrollDown(tester);
    await tester.tap(find.byKey(const ValueKey('lorebook-wizard-check')));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await _scrollDown(tester);
    expect(find.textContaining('没提雨'), findsWidgets);

    // 存成一本书
    await _scrollDown(tester);
    await tester.tap(find.byKey(const ValueKey('lorebook-wizard-save')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    final books = await tavern.listLorebooks();
    final book = books.firstWhere((b) => b.name == '雨港');
    final raw = await tavern.lorebook(book.id);
    expect(raw, isNotNull);
    final entries = (raw!['entries']! as Map).values
        .cast<Map<String, Object?>>()
        .toList();
    expect(entries, hasLength(2));
    expect(entries.map((e) => e['comment']), containsAll(['码头', '盐行']));
    final salted = entries.firstWhere((e) => e['comment'] == '盐行');
    expect(salted['constant'], isTrue);
    expect(salted['position'], 0);
  });
}
