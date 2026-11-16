// On-device: 资源库 → 状态模板 → 新建一项 → 保存 → 应用到角色 → 卡里读得回来。
//
//   flutter test integration_test/app_state_template_test.dart -d <device>
//
// 真引擎 + 临时目录（不碰设备上真实数据）。验的是闭环：
// 模板管理页能建、能存、能应用；应用之后卡片的 extensions.dshgo.state 就是模板折出来的样子。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/tavern/state_templates.dart';
import 'package:dsh_app/tavern/tavern_provider.dart';
import 'package:dsh_app/ui/state/state_templates_page.dart';
import 'package:dsh_app/ui/theme/theme.dart';
import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _card = '''
{
  "spec": "chara_card_v3",
  "spec_version": "3.0",
  "data": {
    "name": "林晚",
    "description": "",
    "personality": "",
    "scenario": "",
    "first_mes": "",
    "mes_example": "",
    "creator_notes": "",
    "system_prompt": "",
    "post_history_instructions": "",
    "alternate_greetings": [],
    "tags": [],
    "creator": "",
    "character_version": "1.0",
    "extensions": {"dshgo": {}}
  }
}
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('状态模板：建一项 → 保存 → 应用到角色 → 卡里读得回来', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    final dir = await Directory.systemTemp.createTemp('state_template_test');
    final tavern = await openTavern('${dir.path}/tavern');
    final store = StateTemplateStore(Directory('${dir.path}/templates'));
    addTearDown(() async {
      await tavern.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final card = await tavern.importCard(
      Uint8List.fromList(utf8.encode(_card)),
      fileName: 'card.json',
    );

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
          home: const StateTemplatesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('state-templates-empty')), findsOneWidget);

    // 新建模板
    await tester.tap(find.byKey(const ValueKey('state-template-new')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.enterText(
      find.byKey(const ValueKey('state-template-name')),
      '客栈日常',
    );
    await tester.pumpAndSettle();

    // 加一项：好感 / affection / 数字 / 初始 20 / -100..100
    await tester.tap(find.byKey(const ValueKey('state-template-add-field')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('state-field-done')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('state-field-title')),
      '好感',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('state-field-key')),
      'affection',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('state-field-initial')),
      '20',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('state-field-min')),
      '-100',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('state-field-max')),
      '100',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('state-field-done')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('好感'), findsWidgets, reason: '状态项要出现在模板里');

    // 保存模板
    await tester.tap(find.byKey(const ValueKey('state-template-save')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('客栈日常'), findsWidgets, reason: '列表里要有这个模板');

    // 打开模板的菜单 → 应用到角色 → 选这张卡
    await tester.tap(find.text('客栈日常').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.text('应用到角色'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.byKey(ValueKey('state-template-target-${card.id}')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 卡里读回来：schema 和 init 都在
    final fields = (await tavern.characterFields(card.id))!;
    final dshgo = (fields['extensions']! as Map)['dshgo']! as Map;
    final state = dshgo['state']! as Map;
    final properties =
        ((state['schema']! as Map)['properties']! as Map)
            as Map<String, Object?>;
    expect(properties.keys, contains('affection'));
    final affection = properties['affection']! as Map<String, Object?>;
    expect(affection['title'], '好感');
    expect(affection['minimum'], -100);
    expect(affection['maximum'], 100);
    expect((state['init']! as Map)['affection'], 20);
  });
}
