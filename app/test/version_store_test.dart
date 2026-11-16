// 版本快照：存得下、列得出、读得回、删得掉，超上限丢最旧的。
//
//   flutter test test/version_store_test.dart

import 'dart:io';

import 'package:dsh_app/tavern/version_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late VersionStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('versions');
    store = VersionStore(Directory('${dir.path}/versions'));
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('没存过就是空的', () async {
    expect(await store.list('lorebook', 'b1'), isEmpty);
    expect(await store.read('lorebook', 'b1', 'v0'), isNull);
  });

  test('存一份能列出来、能读回来', () async {
    final id = await store.save('lorebook', 'b1', {
      'name': '雨港',
      'entries': {
        '0': {'comment': '码头'},
      },
    }, label: '开工前');

    final versions = await store.list('lorebook', 'b1');
    expect(versions, hasLength(1));
    expect(versions.single.id, id);
    expect(versions.single.label, '开工前');
    expect(versions.single.bytes, greaterThan(0));

    final back = await store.read('lorebook', 'b1', id);
    expect(back!['name'], '雨港');
  });

  test('新的排在前面', () async {
    final first = await store.save('lorebook', 'b1', {
      'name': 'A',
    }, at: DateTime(2026, 1, 1, 10));
    final second = await store.save('lorebook', 'b1', {
      'name': 'B',
    }, at: DateTime(2026, 1, 1, 11));
    final versions = await store.list('lorebook', 'b1');
    expect(versions.map((v) => v.id), [second, first]);
  });

  test('不同资产互不干扰', () async {
    await store.save('lorebook', 'b1', {'name': 'A'});
    await store.save('lorebook', 'b2', {'name': 'B'});
    await store.save('preset', 'b1', {'name': 'P'});
    expect(await store.list('lorebook', 'b1'), hasLength(1));
    expect(await store.list('lorebook', 'b2'), hasLength(1));
    expect(await store.list('preset', 'b1'), hasLength(1));
  });

  test('超上限丢最旧的，文件也删掉', () async {
    for (var i = 0; i < versionLimit + 5; i++) {
      await store.save('lorebook', 'b1', {
        'n': i,
      }, at: DateTime(2026, 1, 1).add(Duration(minutes: i)));
    }
    final versions = await store.list('lorebook', 'b1');
    expect(versions, hasLength(versionLimit));
    // 最旧的几条读不出来了
    expect(await store.read('lorebook', 'b1', 'v0'), isNull);
    // 最新的还在
    expect(await store.read('lorebook', 'b1', versions.first.id), isNotNull);
  });

  test('删掉一份，列表和文件都对', () async {
    final id = await store.save('lorebook', 'b1', {'name': 'A'});
    await store.delete('lorebook', 'b1', id);
    expect(await store.list('lorebook', 'b1'), isEmpty);
    expect(await store.read('lorebook', 'b1', id), isNull);
  });

  test('索引坏了当没有，不炸', () async {
    await store.save('lorebook', 'b1', {'name': 'A'});
    final index = File(
      '${dir.path}${Platform.pathSeparator}versions'
      '${Platform.pathSeparator}lorebook${Platform.pathSeparator}b1'
      '${Platform.pathSeparator}index.json',
    );
    await index.writeAsString('{坏');
    expect(await store.list('lorebook', 'b1'), isEmpty);
  });
}
