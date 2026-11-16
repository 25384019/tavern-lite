// On-device: 专业创作的 AI 接线 —— ✨ → 动作 → 候选 → 采用/丢弃。
//
//   flutter test integration_test/app_studio_ai_test.dart -d <device>
//
// 用 MockClient 顶掉传输层：不花钱、不需要 Key、结果固定，但走的是**真的**
// TavernModelClient、真的提示组装、真的 JSON 解析和真的界面。
// 验的是接线，不是模型聪不聪明。

import 'dart:convert';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/tavern/tavern_provider.dart';
import 'package:dsh_app/tavern/tavern_studio_draft.dart';
import 'package:dsh_app/ui/tavern/tavern_studio_page.dart';
import 'package:dsh_app/ui/theme/theme.dart';
import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

Future<String?> testKey() async => 'test-key';

/// 把 App 外壳搭好，传输层换成固定回话的假客户端。
Future<void> pumpStudio(
  WidgetTester tester, {
  required String reply,
  StudioDraft? draft,
  List<int>? calls,
}) async {
  final client = TavernModelClient(
    clientFactory: () => MockClient((request) async {
      calls?.add(1);
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': reply},
              'finish_reason': 'stop',
            },
          ],
          'usage': {
            'prompt_tokens': 120,
            'completion_tokens': 30,
            'total_tokens': 150,
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tavernModelClientProvider.overrideWithValue(client),
        tavernModelConfigProvider.overrideWithValue(
          const TavernModelConfig(
            apiKey: testKey,
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
        home: TavernStudioPage(initial: draft ?? StudioDraft()),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

String fieldText(WidgetTester tester, String key) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byKey(ValueKey('studio-field-$key')),
        matching: find.byType(TextField),
      ),
    )
    .controller!
    .text;

Future<void> openModule(WidgetTester tester, String module) async {
  final row = find.byKey(ValueKey('studio-module-$module'));
  // 九个模块在懒加载列表里，靠后的（world / rules / soul）要先滚出来。
  await reveal(tester, row);
  await tester.tap(row);
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      160,
      scrollable: find.byType(Scrollable).first,
    );
  }
  // 建出来了不代表在屏幕上：不滚进来 tap 会点空。
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('补全：候选先给看，采用后才写进字段', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    await pumpStudio(
      tester,
      reply: '{"fields":{"appearance":"短发，围裙上有洗不掉的酱油点。"}}',
    );
    await openModule(tester, 'profile');

    final sparkle = find.byKey(const ValueKey('studio-ai-appearance'));
    await reveal(tester, sparkle);
    await tester.tap(sparkle);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await tester.tap(find.byKey(const ValueKey('studio-ai-fill')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 候选：文字出现了，但字段还空着
    expect(find.text('短发，围裙上有洗不掉的酱油点。'), findsWidgets);
    expect(fieldText(tester, 'appearance'), isEmpty, reason: '候选阶段不许动字段');

    // 采用：这才写进去
    await tester.tap(find.byKey(const ValueKey('studio-ai-adopt')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(fieldText(tester, 'appearance'), '短发，围裙上有洗不掉的酱油点。');
  });

  testWidgets('整模块生成：一次填好几格，锁定的那格不动', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    // 先锁住「昵称」，再让模型连它一起回——采用后必须还是空。
    final draft = StudioDraft()..toggleLock('profile', 'nickname');
    await pumpStudio(
      tester,
      draft: draft,
      reply:
          '{"fields":{"appearance":"短发。","body":"左手有疤。","nickname":"不该写进来"}}',
    );
    await openModule(tester, 'profile');

    await tester.tap(find.byKey(const ValueKey('studio-ai-module')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('studio-ai-wholeModule')));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await tester.tap(find.byKey(const ValueKey('studio-ai-adopt')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(fieldText(tester, 'appearance'), '短发。');
    expect(fieldText(tester, 'body'), '左手有疤。');
    expect(fieldText(tester, 'nickname'), isEmpty, reason: '锁定的字段不许被写');
  });

  testWidgets('检查：只列问题，没有「采用」', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    await pumpStudio(
      tester,
      reply: '{"issues":[{"field":"appearance","issue":"外貌里写了围裙有酱油点，却没交代她开面馆","suggest":"补一句她的身份"}]}',
    );
    await openModule(tester, 'profile');

    final sparkle = find.byKey(const ValueKey('studio-ai-appearance'));
    await reveal(tester, sparkle);
    await tester.tap(sparkle);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('studio-ai-check')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.textContaining('酱油点'), findsWidgets);
    expect(find.textContaining('补一句她的身份'), findsWidgets);
    // 检查不改文本：没有「采用」，只有「丢弃」
    expect(find.byKey(const ValueKey('studio-ai-adopt')), findsNothing);
    expect(find.byKey(const ValueKey('studio-ai-discard')), findsOneWidget);
  });

  testWidgets('模型回废话：不写东西，只提示', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    await pumpStudio(tester, reply: '好的，我来帮你写。');
    await openModule(tester, 'profile');

    final sparkle = find.byKey(const ValueKey('studio-ai-appearance'));
    await reveal(tester, sparkle);
    await tester.tap(sparkle);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('studio-ai-fill')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(fieldText(tester, 'appearance'), isEmpty);
    expect(find.text('模型这次没给出能用的内容'), findsWidgets);
  });

  testWidgets('重写时点取消：不发请求、不花钱', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    final calls = <int>[];
    await pumpStudio(
      tester,
      reply: '{"fields":{"appearance":"不该用到"}}',
      calls: calls,
    );
    await openModule(tester, 'profile');

    final sparkle = find.byKey(const ValueKey('studio-ai-appearance'));
    await reveal(tester, sparkle);
    await tester.tap(sparkle);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('studio-ai-rewrite')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 要求对话框里点「取消」
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(calls, isEmpty, reason: '取消了就不该发请求');
    expect(fieldText(tester, 'appearance'), isEmpty);
  });

  testWidgets('世界书：从关系模块生成条目，采用后进草稿', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    await pumpStudio(
      tester,
      reply:
          '{"entries":[{"title":"码头","keys":["码头","潮水"],"content":"潮水一天两次。"},'
          '{"title":"雨","keys":["雨"],"content":"一年下三百天雨。","constant":true}]}',
    );
    // 关系模块的内容本来就该进书
    await tester.tap(find.byKey(const ValueKey('studio-module-bond')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.byKey(const ValueKey('studio-ai-module')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('studio-ai-book')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 候选里能看到两条的标题和关键词；采用前草稿里还没有
    expect(find.text('码头'), findsWidgets);
    expect(find.textContaining('潮水'), findsWidgets);
    expect(find.byKey(const ValueKey('studio-book-count')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('studio-ai-adopt')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 采用后：页脚说有两条目
    final count = find.byKey(const ValueKey('studio-book-count'));
    await reveal(tester, count);
    expect(find.textContaining('世界书 2 条'), findsWidgets);
  });
}
