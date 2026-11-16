// 打进 APK 的内置内容：15 本世界书 + 3 张角色卡。
//
// 资源在 `assets/bundled/`，跟着包走；清单 `manifest.json` 记着每条的文件名和显示名
// （磁盘上用 wb01.json 这种安全名——原文件名带全角符号，Windows 上拷不动）。
//
// 装的时候按名字去重，点几次都不会重复；只读 AssetBundle，不联网。

import 'dart:convert';

import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/services.dart';

/// 一条随包内容。
class BundledItem {
  const BundledItem({
    required this.asset,
    required this.name,
    required this.isCard,
  });

  final String asset;
  final String name;
  final bool isCard;
}

/// 读清单。清单本身坏了就返回空（不崩，界面会显示 0）。
Future<({List<BundledItem> books, List<BundledItem> cards})>
bundledContent() async {
  try {
    final raw = await rootBundle.loadString('assets/bundled/manifest.json');
    final list = jsonDecode(raw);
    if (list is! List) {
      return (books: <BundledItem>[], cards: <BundledItem>[]);
    }
    final books = <BundledItem>[];
    final cards = <BundledItem>[];
    for (final item in list) {
      if (item is! Map) continue;
      final asset = item['asset'];
      final name = item['name'];
      if (asset is! String || name is! String) continue;
      final entry = BundledItem(
        asset: asset,
        name: name,
        isCard: item['kind'] == 'card',
      );
      (entry.isCard ? cards : books).add(entry);
    }
    books.sort((a, b) => a.name.compareTo(b.name));
    cards.sort((a, b) => a.name.compareTo(b.name));
    return (books: books, cards: cards);
  } on Object {
    return (books: <BundledItem>[], cards: <BundledItem>[]);
  }
}

/// 装一遍随包内容；同名跳过。失败不抛出，收进 [failed]。
Future<({int books, int cards, List<String> failed})> installBundledContent(
  Tavern tavern, {
  required Set<String> existingBooks,
  required Set<String> existingCards,
  void Function(int done, int total)? onProgress,
}) async {
  final manifest = await bundledContent();
  final total = manifest.books.length + manifest.cards.length;
  var done = 0;
  var books = 0;
  var cards = 0;
  final failed = <String>[];

  for (final item in manifest.books) {
    if (!existingBooks.contains(item.name)) {
      try {
        final text = await rootBundle.loadString(item.asset);
        await tavern.importLorebook(text, fileName: '${item.name}.json');
        books++;
      } on Object catch (e) {
        failed.add('${item.name}：$e');
      }
    }
    onProgress?.call(++done, total);
  }

  for (final item in manifest.cards) {
    if (!existingCards.contains(item.name)) {
      try {
        final bytes = (await rootBundle.load(item.asset)).buffer.asUint8List();
        await tavern.importCard(bytes, fileName: '${item.name}.png');
        cards++;
      } on Object catch (e) {
        failed.add('${item.name}：$e');
      }
    }
    onProgress?.call(++done, total);
  }

  return (books: books, cards: cards, failed: failed);
}
