// On-device: 舞台 › 状态 面板 —— 中文标题、类型化编辑、非法输入不写入。
//
//   flutter test integration_test/app_state_panel_test.dart -d <device>
//
// 直接挂 TavernStagePanel（真引擎、临时目录里的真卡真会话），不走导航，
// 这样测的就是这一块本身：schema 的 title 盖过键名、数字字段给范围和 ±、
// 超范围被挡下且引擎里的值一点没变。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/tavern/tavern_provider.dart';
import 'package:dsh_app/ui/tavern/tavern_stage_panel.dart';
import 'package:dsh_app/ui/theme/theme.dart';
import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 一张最小状态卡：两项数字、一项枚举，够验标题和控件。
const _card = '''
{
  "spec": "chara_card_v3",
  "spec_version": "3.0",
  "data": {
    "name": "状态面板测试",
    "description": "只用来测状态面板。",
    "personality": "无。",
    "scenario": "测试。",
    "first_mes": "坐吧。",
    "mes_example": "",
    "creator_notes": "",
    "system_prompt": "",
    "post_history_instructions": "",
    "alternate_greetings": [],
    "tags": ["测试"],
    "creator": "test",
    "character_version": "1.0",
    "extensions": {
      "dshgo": {
        "v": 1,
        "state": {
          "schema": {
            "type": "object",
            "properties": {
              "affection": {"type": "integer", "title": "好感", "minimum": -100, "maximum": 100, "default": 20},
              "stamina": {"type": "integer", "title": "体力", "minimum": 0, "maximum": 100, "default": 80},
              "mood": {"type": "string", "title": "心情", "enum": ["平静", "高兴"], "default": "平静"}
            }
          },
          "init": {"affection": 20, "stamina": 80, "mood": "平静"}
        }
      }
    }
  }
}
''';

/// 快照里的值是 Object?，这里取成 Map 方便断言。
Map<String, Object?>? stateValue(TavernStateSnapshot state) =>
    state.values is Map<String, Object?>
    ? state.values! as Map<String, Object?>
    : null;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('状态面板：中文标题、数字给范围、超范围不写入', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    final dir = await Directory.systemTemp.createTemp('state_panel_test');
    final tavern = await openTavern('${dir.path}/tavern');
    addTearDown(() async {
      await tavern.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final character = await tavern.importCard(
      Uint8List.fromList(utf8.encode(_card)),
      fileName: 'state-panel.json',
    );
    final chatId = await tavern.createChat(character.id);

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
          home: Scaffold(
            body: TavernStagePanel(
              chatId: chatId,
              characterId: character.id,
              name: character.name,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 切到「状态」
    await tester.tap(find.text('状态'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 卡片写了中文 title，就该显示中文，而不是内部键
    expect(find.text('好感'), findsWidgets, reason: '应该显示 schema 的 title');
    expect(find.text('affection'), findsNothing, reason: '不该露出内部键');

    // 点开「好感」→ 改
    await tester.tap(find.text('好感').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    final edit = find.byKey(const ValueKey('tavern-state-edit'));
    expect(edit, findsOneWidget, reason: '有消息节点时才给改');
    await tester.tap(edit);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 数字字段：± 键、范围提示都在
    final number = find.byKey(const ValueKey('tavern-state-edit-number'));
    expect(number, findsOneWidget);
    expect(
      find.byKey(const ValueKey('tavern-state-edit-minus')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('tavern-state-edit-plus')),
      findsOneWidget,
    );
    expect(find.textContaining('-100'), findsWidgets, reason: '范围要说出来');

    // 超范围：挡在面板上，不写进去
    await tester.enterText(number, '999');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tavern-state-edit-save')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('要在'), findsWidgets, reason: '要说清超了范围');
    expect(
      stateValue(await tavern.readState(chatId))?['affection'],
      20,
      reason: '被挡下的值不许写进引擎',
    );

    // 合法值：保存后面板和引擎都变
    await tester.enterText(number, '42');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tavern-state-edit-save')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('42'), findsWidgets, reason: '面板要显示新值');
    expect(stateValue(await tavern.readState(chatId))?['affection'], 42);
  });
}
