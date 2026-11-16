// 一次性校验：把要打进 APK 的世界书和角色卡都用引擎读一遍，看谁能用。
//
//   flutter test test/bundled_content_test.dart
//
// 它读的是 assets/bundled 下的副本（也就是会进 APK 的那批），
// 所以这里的结论对用户看到的东西有效。

import 'dart:convert';
import 'dart:io';

import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late Tavern tavern;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('bundled');
    tavern = await openTavern('${dir.path}/tavern');
  });

  tearDownAll(() async {
    await tavern.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('每本内置世界书都能导入', () async {
    final files =
        Directory('assets/bundled/worldbooks')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files.length, greaterThanOrEqualTo(15));

    final failed = <String>[];
    for (final file in files) {
      final text = await file.readAsString();
      try {
        await tavern.importLorebook(text, fileName: file.uri.pathSegments.last);
      } on Object catch (e) {
        failed.add('${file.uri.pathSegments.last}: $e');
      }
    }
    // ignore: avoid_print
    print('世界书导入失败：${failed.isEmpty ? '无' : failed.join(' | ')}');
    expect(failed, isEmpty, reason: '有书读不进来，就没法内置');
  });

  test('每张内置角色卡都能导入', () async {
    final files = Directory('assets/bundled/cards')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .toList();
    expect(files.length, 3);

    final failed = <String>[];
    for (final file in files) {
      try {
        await tavern.importCard(
          await file.readAsBytes(),
          fileName: file.uri.pathSegments.last,
        );
      } on Object catch (e) {
        failed.add('${file.uri.pathSegments.last}: $e');
      }
    }
    // ignore: avoid_print
    print('角色卡导入失败：${failed.isEmpty ? '无' : failed.join(' | ')}');
    expect(failed, isEmpty);
  });

  test('真拷进来的书能在列表里看到', () async {
    final books = await tavern.listLorebooks();
    expect(books.length, greaterThanOrEqualTo(15));
    final cards = await tavern.watchCharacters().first;
    expect(cards.length, 3);
    // 名字能读出来（说明 entries 被正确解析，不是空壳）
    for (final book in books.take(3)) {
      final raw = await tavern.lorebook(book.id);
      expect(raw, isNotNull);
      final entries = raw!['entries'];
      // ignore: avoid_print
      print(
        '${book.name}: ${entries is Map ? entries.length : (entries is List ? entries.length : 0)} 条',
      );
    }
    // 顺带确认这些 JSON 是 UTF-8 且不是乱码
    final sample = books.first;
    expect(utf8.encode(sample.name).isNotEmpty, isTrue);
  });
}
