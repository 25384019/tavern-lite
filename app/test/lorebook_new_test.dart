// 新建世界书：真的开一个引擎、真的落盘、真的能读回来。
//
// 这不是 mock——`openTavern` 在宿主上就能跑（它只用 dart:io），
// 所以「putLorebook 能不能当 create 用」这件事可以当场证出来，不用设备。
//
//   flutter test test/lorebook_new_test.dart

import 'dart:io';
import 'dart:math';

import 'package:dsh_app/tavern/lorebook_new.dart';
import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late Tavern tavern;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lorebook_new_test');
    tavern = await openTavern('${dir.path}/tavern');
  });

  tearDown(() async {
    await tavern.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('id 是文件名安全的 32 位十六进制，而且不重复', () {
    final ids = {for (var i = 0; i < 200; i++) newLorebookId()};
    expect(ids.length, 200);
    for (final id in ids) {
      expect(
        RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(id),
        isTrue,
        reason: id,
      );
      expect(id.length, 32);
    }
    // 固定种子时结果稳定，方便别处复现。
    expect(newLorebookId(Random(7)), newLorebookId(Random(7)));
  });

  test('空书的名字：空白当没写', () {
    expect(emptyLorebookJson('  '), containsPair('name', '世界书'));
    expect(emptyLorebookJson(' 雨港 '), containsPair('name', '雨港'));
    expect(emptyLorebookJson('雨港')['entries'], isEmpty);
  });

  test('putLorebook 就是 create：新 id 也写得进去，列表里立刻能看到', () async {
    expect(await tavern.listLorebooks(), isEmpty);

    final book = await createEmptyLorebook(tavern, name: '雨港');
    final listed = await tavern.listLorebooks();
    expect(listed.map((b) => b.id), contains(book.id));
    final summary = listed.firstWhere((b) => b.id == book.id);
    expect(summary.name, '雨港');
    expect(summary.entryCount, 0);

    // 读回来的原始文档还在，而且是我们写的那个形状。
    final raw = await tavern.lorebook(book.id);
    expect(raw, isNotNull);
    expect(raw!['name'], '雨港');
    expect(raw['entries'], isEmpty);
  });

  test('新书能直接加条目：uid 从 0 开始，读回来 1 条', () async {
    final book = await createEmptyLorebook(tavern, name: '雨港');
    final raw = (await tavern.lorebook(book.id))!;
    (raw['entries']! as Map<String, Object?>)['0'] = {
      'uid': 0,
      'key': ['码头'],
      'content': '潮水一天两次，第一次来的人总会被困住。',
      'comment': '码头',
      'constant': false,
      'disable': false,
      'order': 100,
      'position': 0,
    };
    await tavern.putLorebook(book.id, raw);

    final after = await tavern.listLorebooks();
    expect(after.firstWhere((b) => b.id == book.id).entryCount, 1);

    // 再读一次，条目还在（不是写进了缓存）。
    final again = (await tavern.lorebook(book.id))!;
    expect((again['entries']! as Map).length, 1);
  });

  test('两本书互不影响，删一本另一本还在', () async {
    final a = await createEmptyLorebook(tavern, name: 'A');
    final b = await createEmptyLorebook(tavern, name: 'B');
    expect(a.id, isNot(b.id));
    await tavern.deleteLorebook(a.id);
    final left = await tavern.listLorebooks();
    expect(left.map((x) => x.id), isNot(contains(a.id)));
    expect(left.map((x) => x.id), contains(b.id));
  });
}
