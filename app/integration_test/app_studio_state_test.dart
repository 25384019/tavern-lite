// On-device: 专业创作里选状态模板 → 存成卡 → 卡里带着 extensions.dshgo.state。
//
//   flutter test integration_test/app_studio_state_test.dart -d <device>
//
// 真引擎 + 临时目录。验的是「制卡时能把状态一起带进去」这条路。

import 'dart:convert';
import 'dart:io';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/tavern/state_templates.dart';
import 'package:dsh_app/tavern/tavern_provider.dart';
import 'package:dsh_app/tavern/tavern_studio_draft.dart';
import 'package:dsh_app/ui/tavern/tavern_studio_page.dart';
import 'package:dsh_app/ui/theme/theme.dart';
import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('制卡时选一个状态模板，存出来的卡里带着它', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    final dir = await Directory.systemTemp.createTemp('studio_state_test');
    final tavern = await openTavern('${dir.path}/tavern');
    final store = StateTemplateStore(Directory('${dir.path}/templates'));
    final template = StateTemplate(
      id: 'tpl-inn',
      name: '客栈日常',
      fields: [
        StateField(
          key: 'affection',
          title: '好感',
          type: StateFieldType.number,
          initial: 20,
          min: -100,
          max: 100,
        ),
        StateField(
          key: 'mood',
          title: '心情',
          type: StateFieldType.choice,
          initial: '平静',
          options: ['平静', '高兴'],
        ),
      ],
    );
    await store.write([template]);
    addTearDown(() async {
      await tavern.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    // 草稿里先有必填的两项，省得填表。
    final draft = StudioDraft();
    draft.setText('profile', 'name', '林晚');
    draft.setText('profile', 'appearance', '短发，围裙上有酱油点。');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tavernProvider.overrideWithValue(tavern),
          stateTemplateStoreProvider.overrideWith((ref) async => store),
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
          home: TavernStudioPage(initial: draft),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 九个模块在上面，「状态」那一行在下面，先滚出来
    final stateRow = find.byKey(const ValueKey('studio-state'));
    await tester.scrollUntilVisible(
      stateRow,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(stateRow);
    await tester.pumpAndSettle();

    // 打开「状态」→ 选模板
    await tester.tap(stateRow);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('studio-state-tpl-inn')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    // 选完之后数目对不对，由最后卡片里的内容说了算（界面上那一行在懒加载区里）。

    // 预览并保存
    await tester.tap(find.byKey(const ValueKey('studio-preview')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('studio-save')));
    await tester.pumpAndSettle(const Duration(seconds: 4));

    // 新卡里带着状态
    final characters = await tavern.watchCharacters().first;
    expect(characters, hasLength(1));
    final fields = (await tavern.characterFields(characters.single.id))!;
    final state =
        ((fields['extensions']! as Map)['dshgo']! as Map)['state']! as Map;
    final properties =
        ((state['schema']! as Map)['properties']! as Map)
            as Map<String, Object?>;
    expect(properties.keys, containsAll(['affection', 'mood']));
    expect((state['init']! as Map)['affection'], 20);
    expect((state['init']! as Map)['mood'], '平静');
  });

  testWidgets('AI 按角色设计状态方案：先看候选，采用后才进草稿', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    final dir = await Directory.systemTemp.createTemp('studio_state_ai');
    final tavern = await openTavern('${dir.path}/tavern');
    addTearDown(() async {
      await tavern.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final client = TavernModelClient(
      clientFactory: () => MockClient(
        (request) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '{"fields":[{"key":"affection","title":"好感","type":"number","initial":20,"min":-100,"max":100}]}',
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
          stateTemplateStoreProvider.overrideWith(
            (ref) async => StateTemplateStore(Directory('${dir.path}/t')),
          ),
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
          home: TavernStudioPage(
            initial: StudioDraft()
              ..setText('profile', 'name', '??')
              ..setText('profile', 'appearance', '???'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final stateRow = find.byKey(const ValueKey('studio-state'));
    await tester.scrollUntilVisible(
      stateRow,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(stateRow);
    await tester.pumpAndSettle();
    await tester.tap(stateRow);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 菜单里选「状态方案」，等假模型回话
    await tester.tap(find.byKey(const ValueKey('studio-state-ai')));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('好感'), findsWidgets, reason: '候选要列出来');
    await tester.tap(find.byKey(const ValueKey('studio-state-adopt')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 采用后草稿里有状态：存出来的卡就该带着
    await tester.tap(find.byKey(const ValueKey('studio-preview')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('studio-save')));
    await tester.pumpAndSettle(const Duration(seconds: 4));
    final characters = await tavern.watchCharacters().first;
    expect(characters, hasLength(1));
    final fields = (await tavern.characterFields(characters.single.id))!;
    final state =
        ((fields['extensions']! as Map)['dshgo']! as Map)['state']! as Map;
    expect((state['init']! as Map)['affection'], 20);
  });
}

Future<String?> testKey() async => 'test-key';
