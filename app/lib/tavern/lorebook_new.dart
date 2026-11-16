// 新建一本空白世界书。
//
// 引擎没有 create 接口，只有 putLorebook(id, json)；而 putLorebook 会先读、读到 null
// 也照写（engine.dart 2222：_readBookNow 返回 null 后直接 _writeBookNow），所以
// "新建" = 挑一个没被占用的 id，把一本空书写进去。
//
// 写进去的是 ST 原生形状（entries 以 uid 为键），不写 scan_depth / token_budget：
// 那两个缺省时按用户全局设置走，写死反而会把用户的偏好冲掉。

import 'dart:math';

import 'package:dsh_tavern/dsh_tavern.dart';

/// 一个文件名安全的随机 id：32 位十六进制，和引擎导入时自己生成的一样。
String newLorebookId([Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(32, (_) => source.nextInt(16).toRadixString(16)).join();
}

/// 一本空书的 ST 原生 JSON。[name] 会被列表当作显示名。
Map<String, Object?> emptyLorebookJson(String name) => {
  'name': name.trim().isEmpty ? '世界书' : name.trim(),
  'description': '',
  'entries': <String, Object?>{},
  'extensions': <String, Object?>{},
};

/// 新建并落盘，返回它（条目 0）。读写都走 Tavern，界面不用知道 id 规则。
Future<TavernLorebook> createEmptyLorebook(
  Tavern tavern, {
  required String name,
}) async {
  final id = newLorebookId();
  final json = emptyLorebookJson(name);
  await tavern.putLorebook(id, json);
  return TavernLorebook(
    id: id,
    name: json['name']! as String,
    entryCount: 0,
    raw: json,
  );
}
