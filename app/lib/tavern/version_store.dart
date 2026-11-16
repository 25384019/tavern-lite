// 资产的历史快照：世界书、预设这类"整份 JSON"的东西，存一份、列出来、回滚。
//
// 放本地（`<support>/versions/<kind>/<id>/`），一个版本一个文件，外加一份索引。
// 不碰引擎的存储格式：回滚 = 把那份 JSON 原样写回去（putLorebook / updatePreset 都行）。
//
// 每份资产最多留 [maxVersions] 份，超了丢最旧的。

import 'dart:convert';
import 'dart:io';

/// 一份快照：什么时候、叫什么、多大。
class SavedVersion {
  SavedVersion({
    required this.id,
    required this.at,
    required this.label,
    required this.bytes,
  });

  final String id;
  final DateTime at;
  final String label;

  /// 这份 JSON 有多少字节（列表上给人一个体量感）。
  final int bytes;

  Map<String, Object?> toJson() => {
    'id': id,
    'at': at.millisecondsSinceEpoch ~/ 1000,
    'label': label,
    'bytes': bytes,
  };

  factory SavedVersion.fromJson(Map<String, Object?> json) => SavedVersion(
    id: json['id'] is String ? json['id']! as String : '',
    at: DateTime.fromMillisecondsSinceEpoch(
      (json['at'] is int ? json['at']! as int : 0) * 1000,
    ),
    label: json['label'] is String ? json['label']! as String : '',
    bytes: json['bytes'] is int ? json['bytes']! as int : 0,
  );
}

/// 每份资产最多留几份。
const versionLimit = 20;

class VersionStore {
  VersionStore(this.directory);

  /// 应用支持目录下的 `versions`。
  final Directory directory;

  Directory _dirOf(String kind, String id) => Directory(
    '${directory.path}${Platform.pathSeparator}$kind'
    '${Platform.pathSeparator}$id',
  );

  File _indexOf(String kind, String id) =>
      File('${_dirOf(kind, id).path}${Platform.pathSeparator}index.json');

  File _fileOf(String kind, String id, String versionId) =>
      File('${_dirOf(kind, id).path}${Platform.pathSeparator}$versionId.json');

  /// 存一份。返回它的 id；写不进去就抛。
  Future<String> save(
    String kind,
    String id,
    Map<String, Object?> json, {
    String label = '',
    DateTime? at,
  }) async {
    final when = at ?? DateTime.now();
    final versionId = _newId(when);
    final dir = _dirOf(kind, id);
    await dir.create(recursive: true);
    final body = jsonEncode(json);
    await _fileOf(kind, id, versionId).writeAsString(body, flush: true);

    final versions = await list(kind, id);
    final entry = SavedVersion(
      id: versionId,
      at: when,
      label: label,
      bytes: body.length,
    );
    final next = [entry, ...versions.where((v) => v.id != versionId)];
    await _writeIndex(kind, id, next);
    // 超出上限就把最旧的丢掉（索引和文件一起）。
    for (final stale in next.skip(versionLimit)) {
      await _fileOf(kind, id, stale.id).delete().catchError((_) => File(''));
    }
    if (next.length > versionLimit) {
      await _writeIndex(kind, id, next.take(versionLimit).toList());
    }
    return versionId;
  }

  /// 新的在前。
  Future<List<SavedVersion>> list(String kind, String id) async {
    try {
      final file = _indexOf(kind, id);
      if (!await file.exists()) return const [];
      final json = jsonDecode(await file.readAsString());
      if (json is! List) return const [];
      final versions = [
        for (final item in json)
          if (item is Map) SavedVersion.fromJson(item.cast<String, Object?>()),
      ]..sort((a, b) => b.at.compareTo(a.at));
      return versions;
    } on Object {
      // 索引坏了当没有，不影响正本。
      return const [];
    }
  }

  /// 读出某一版的内容。
  Future<Map<String, Object?>?> read(
    String kind,
    String id,
    String versionId,
  ) async {
    try {
      final file = _fileOf(kind, id, versionId);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      return json is Map<String, Object?> ? json : null;
    } on Object {
      return null;
    }
  }

  Future<void> delete(String kind, String id, String versionId) async {
    try {
      await _fileOf(kind, id, versionId).delete();
    } on Object {
      // 文件没了就算了。
    }
    final left = await list(kind, id);
    await _writeIndex(kind, id, [
      for (final version in left)
        if (version.id != versionId) version,
    ]);
  }

  Future<void> _writeIndex(
    String kind,
    String id,
    List<SavedVersion> versions,
  ) async {
    await _dirOf(kind, id).create(recursive: true);
    await _indexOf(kind, id).writeAsString(
      jsonEncode([for (final version in versions) version.toJson()]),
      flush: true,
    );
  }

  static String _newId(DateTime at) =>
      'v${at.millisecondsSinceEpoch.toRadixString(36)}';
}
