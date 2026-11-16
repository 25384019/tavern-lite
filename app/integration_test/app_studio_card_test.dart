// On-device: 从一张已有的卡打开工作室 → 改 → 存回这张卡（不是新建）。
//
//   flutter test integration_test/app_studio_card_test.dart -d <device>
//
// 真引擎、临时目录。验的是"安全的写回"：正文改了、草稿存进 extensions、
// 同一命名空间下的 state 还在、书架上的卡还是那一张。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/tavern/studio_store.dart';
import 'package:dsh_app/tavern/tavern_provider.dart';
import 'package:dsh_app/ui/tavern/tavern_studio_page.dart';
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
    "description": "旧描述。",
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
    "extensions": {"dshgo": {"state": {"v": 1}}}
  }
}
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('专业草稿存回已有的卡：不改书架、不丢 state', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    final dir = await Directory.systemTemp.createTemp('studio_card_test');
    final tavern = await openTavern('${dir.path}/tavern');
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
          home: TavernStudioPage(characterId: card.id),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 进「人物档案」，填外貌（必填）
    await tester.tap(find.byKey(const ValueKey('studio-module-profile')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('studio-field-appearance')),
        matching: find.byType(TextField),
      ),
      '短发，围裙上有酱油点。',
    );
    await tester.pumpAndSettle();

    // 回列表 → 预览 → 存回这张卡
    Navigator.of(tester.element(find.byType(TavernStudioModulePage))).pop();
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('studio-preview')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('存回这张卡'), findsWidgets, reason: '绑卡时按钮要说存回这张卡');
    await tester.tap(find.byKey(const ValueKey('studio-save')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 还是那一张卡：没有多出来新的
    final books = await tavern.watchCharacters().first;
    expect(books, hasLength(1));

    // 正文更新了
    final fields = (await tavern.characterFields(card.id))!;
    expect(fields['description'], contains('短发'));

    // 草稿进了 extensions，且同一命名空间下的 state 还在
    final draft = await loadStudioDraftFromCard(tavern, card.id);
    expect(draft.text('profile', 'appearance'), '短发，围裙上有酱油点。');
    final dshgo = (fields['extensions']! as Map)['dshgo']! as Map;
    expect(dshgo['state'], isNotNull, reason: 'state 不能被 studio 冲掉');
  });
}
