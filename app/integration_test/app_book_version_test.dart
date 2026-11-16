// On-device: 世界书版本快照 —— 存一份、改坏、回滚。
//
//   flutter test integration_test/app_book_version_test.dart -d <device>

import 'dart:io';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/tavern/lorebook_ai.dart';
import 'package:dsh_app/tavern/lorebook_new.dart';
import 'package:dsh_app/tavern/tavern_provider.dart';
import 'package:dsh_app/tavern/version_store.dart';
import 'package:dsh_app/ui/tavern/tavern_library_book_page.dart';
import 'package:dsh_app/ui/theme/theme.dart';
import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('存快照 → 改坏 → 回滚', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    final dir = await Directory.systemTemp.createTemp('book_version');
    final tavern = await openTavern('${dir.path}/tavern');
    addTearDown(() async {
      await tavern.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final id = newLorebookId();
    await tavern.putLorebook(id, {
      ...emptyLorebookJson('雨港'),
      'entries': lorebookEntriesJson(const [
        LorebookDraftEntry(title: '码头', content: '潮水一天两次。', keys: ['码头']),
      ]),
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tavernProvider.overrideWithValue(tavern),
          versionStoreProvider.overrideWith(
            (ref) async => VersionStore(Directory('${dir.path}/versions')),
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

    // 存一份快照
    await tester.tap(find.byKey(const ValueKey('tavern-library-book-history')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(
      find.byKey(const ValueKey('tavern-book-history-empty')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('tavern-book-snapshot')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 把书改坏：换成一整本别的内容
    await tavern.putLorebook(id, {
      ...emptyLorebookJson('雨港'),
      'entries': lorebookEntriesJson(const [
        LorebookDraftEntry(title: '坏的', content: '全被删光了。', keys: ['坏']),
      ]),
    });

    // 回滚
    await tester.tap(find.byKey(const ValueKey('tavern-library-book-history')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final versions = await tester.runAsync(
      () async =>
          Directory('${dir.path}/versions/lorebook/$id').list().toList(),
    );
    expect(versions, isNotNull);
    // 列表里应该有这一版（点第一行）
    final row = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'tavern-book-version-v',
          ),
    );
    expect(row, findsWidgets, reason: '快照要列出来');
    await tester.tap(row.first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('tavern-book-restore-ok')));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    final raw = (await tavern.lorebook(id))!;
    final entries = (raw['entries']! as Map).values
        .cast<Map<String, Object?>>()
        .toList();
    expect(entries, hasLength(1));
    expect(entries.first['comment'], '码头');
    expect(entries.first['content'], '潮水一天两次。');
  });
}
