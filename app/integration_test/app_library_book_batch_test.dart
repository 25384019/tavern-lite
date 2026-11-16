// On-device: 世界书条目的搜索与批量（启用 / 停用 / 删除）。
//
//   flutter test integration_test/app_library_book_batch_test.dart -d <device>

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
import 'package:integration_test/integration_test.dart';

Future<void> scrollDown(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('搜索过滤 → 全选停用 → 删一条', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    final dir = await Directory.systemTemp.createTemp('library_book_batch');
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
        LorebookDraftEntry(title: '盐行', content: '账房只点盐袋。', keys: ['盐行']),
        LorebookDraftEntry(title: '后厨', content: '只有她能进。', keys: ['后厨']),
      ]),
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
          home: TavernLibraryBookPage(bookId: id),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(
      find.byKey(const ValueKey('tavern-library-entry-0')),
      findsOneWidget,
    );

    // 搜索「码头」：只剩一条
    await tester.enterText(
      find.byKey(const ValueKey('tavern-library-book-search')),
      '码头',
    );
    await tester.pumpAndSettle();
    expect(find.text('码头'), findsWidgets);
    expect(find.text('后厨'), findsNothing, reason: '不匹配的条目要滤掉');

    // 清空搜索
    await tester.enterText(
      find.byKey(const ValueKey('tavern-library-book-search')),
      '',
    );
    await tester.pumpAndSettle();

    // 选择 → 全选 → 停用
    await tester.tap(find.byKey(const ValueKey('tavern-library-book-select')));
    await tester.pumpAndSettle();
    await scrollDown(tester);
    await tester.tap(find.byKey(const ValueKey('tavern-library-select-all')));
    await tester.pumpAndSettle();
    await scrollDown(tester);
    await tester.tap(find.byKey(const ValueKey('tavern-library-disable')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    var raw = (await tavern.lorebook(id))!;
    var entries = (raw['entries']! as Map).values
        .cast<Map<String, Object?>>()
        .toList();
    expect(entries, hasLength(3));
    expect(
      entries.every((e) => e['disable'] == true || e['enabled'] == false),
      isTrue,
      reason: '三条都该被停用',
    );

    // 全选状态先清掉，再只选一条删掉
    await scrollDown(tester);
    await tester.tap(find.byKey(const ValueKey('tavern-library-select-all')));
    await tester.pumpAndSettle();
    await scrollDown(tester);
    await tester.tap(find.byKey(const ValueKey('tavern-library-entry-0')));
    await tester.pumpAndSettle();
    await scrollDown(tester);
    await tester.tap(
      find.byKey(const ValueKey('tavern-library-delete-selected')),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('tavern-library-delete-ok')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    raw = (await tavern.lorebook(id))!;
    entries = (raw['entries']! as Map).values
        .cast<Map<String, Object?>>()
        .toList();
    expect(entries, hasLength(2), reason: '删掉一条还剩两条');
  });
}
