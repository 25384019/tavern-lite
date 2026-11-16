// 专业草稿的存放：本地未存草稿 + 卡片里那份。
//
// 两层：
//   · 本地 `<support>/studio/draft.json` —— 你正在写、还没存成卡的东西；
//     打开工作室会接上，存成卡之后清掉。
//   · 卡片里 `extensions.dshgo.studio` —— 存进卡之后就在卡里，导出导入都跟着走。
//     只有走 updateCharacterData 才写得进去（引擎的 updateCharacterFields 不收 extensions）。
//
// 纯 IO + 纯转换，界面只管调；测试用临时目录，不碰真机数据。

import 'dart:convert';
import 'dart:io';

import 'package:dsh_tavern/dsh_tavern.dart';

import 'tavern_studio_draft.dart';

/// 本地那份草稿：一个文件，读不到就当没有。
class StudioDraftStore {
  StudioDraftStore(this.directory);

  /// 工作室自己的目录（会和别的数据分开）。
  final Directory directory;

  File get _file =>
      File('${directory.path}${Platform.pathSeparator}draft.json');

  Future<StudioDraft?> read() async {
    try {
      if (!await _file.exists()) return null;
      final text = await _file.readAsString();
      if (text.trim().isEmpty) return null;
      final json = jsonDecode(text);
      final draft = StudioDraft.fromJson(json);
      return draft.isEmpty ? null : draft;
    } on Object {
      // 坏文件不该让工作室打不开：当他没有。
      return null;
    }
  }

  /// 写一份；空的就顺手清掉，免得留个空壳。
  Future<void> write(StudioDraft draft) async {
    if (draft.isEmpty) return clear();
    await directory.create(recursive: true);
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(jsonEncode(draft.toJson()), flush: true);
    // 先写临时文件再改名：写到一半断电也不会留下半份 JSON。
    await temp.rename(_file.path);
  }

  Future<void> clear() async {
    try {
      if (await _file.exists()) await _file.delete();
    } on Object {
      // 删不掉就算了，下次读到的还是旧草稿，不影响别的。
    }
  }
}

/// 卡片里那份草稿；这张卡没写过专业草稿就是空的。
Future<StudioDraft> loadStudioDraftFromCard(
  Tavern tavern,
  String characterId,
) async {
  final fields = await tavern.characterFields(characterId);
  return studioDraftFromFields(fields);
}

/// 从卡片的 data 里取那份草稿（没有就是空草稿）。
StudioDraft studioDraftFromFields(Map<String, Object?>? data) {
  final extensions = data?['extensions'];
  final dshgo = extensions is Map ? extensions['dshgo'] : null;
  final studio = dshgo is Map ? dshgo['studio'] : null;
  return StudioDraft.fromJson(studio);
}

/// 老卡没有草稿时，用它现有的内容起一份——别让用户对着空表单重打一遍。
///
/// 只做有把握的对应：名字、描述→外貌、性格→内在性格、场景→初遇、开场白、
/// 示例对话、标签→表层性格。别的字段留空，比瞎猜好。
StudioDraft studioDraftFromCardData(Map<String, Object?>? data) {
  final draft = StudioDraft();
  if (data == null) return draft;
  String text(String key) =>
      data[key] is String ? (data[key]! as String).trim() : '';
  final name = text('name');
  final description = text('description');
  final personality = text('personality');
  final scenario = text('scenario');
  final firstMes = text('first_mes');
  final examples = text('mes_example');
  final tags = [
    for (final tag in (data['tags'] is List ? data['tags']! as List : const []))
      if (tag is String && tag.trim().isNotEmpty) tag.trim(),
  ];
  if (name.isNotEmpty) draft.setText('profile', 'name', name);
  if (description.isNotEmpty) {
    draft.setText('profile', 'appearance', description);
  }
  if (personality.isNotEmpty) draft.setText('mind', 'inner', personality);
  if (scenario.isNotEmpty) draft.setText('scene', 'meeting', scenario);
  if (firstMes.isNotEmpty) draft.setText('voice', 'firstMes', firstMes);
  if (examples.isNotEmpty) draft.setText('voice', 'samples', examples);
  if (tags.isNotEmpty) draft.setItems('mind', 'surface', tags);
  return draft;
}

/// 把草稿写回卡片（只动 `extensions.dshgo.studio`，同一命名空间下的
/// `state` 之类由引擎两层合并保住）。
Future<void> saveStudioDraftToCard(
  Tavern tavern,
  String characterId,
  StudioDraft draft,
) => tavern.updateCharacterData(characterId, {
  'extensions': {
    'dshgo': {'studio': draft.toJson()},
  },
});

/// 卡片里还没有的条目：按标题判重，免得每存一次就多一批。
List<StudioBookEntry> studioEntriesMissingFrom(
  List<StudioBookEntry> wanted,
  List<Object?> existingTitles,
) {
  final seen = {
    for (final title in existingTitles)
      if (title is String) title.trim(),
  };
  return [
    for (final entry in wanted)
      if (entry.title.trim().isNotEmpty && !seen.contains(entry.title.trim()))
        entry,
  ];
}

/// 卡片当前的书里，每条叫什么（`comment` 优先，没有就用第一个关键词）。
List<String> studioBookTitles(Map<String, Object?>? fields) {
  final book = fields?['character_book'];
  final entries = book is Map ? book['entries'] : null;
  if (entries is! List) return const [];
  return [
    for (final entry in entries)
      if (entry is Map)
        switch (entry['comment']) {
          final String comment when comment.trim().isNotEmpty => comment.trim(),
          _ => switch (entry['keys']) {
            final List keys when keys.isNotEmpty && keys.first is String =>
              (keys.first! as String).trim(),
            _ => '',
          },
        },
  ];
}
