// 创作层 → 卡片层：把九个模块的文字折算成一张能用的卡。
//
// 纯函数，不碰网络、不碰引擎、不碰界面，所以能整套单测——这块最值得测，
// 因为它决定了"写了很多字"最后是变成一张好卡，还是一团每回合都重发两万字的垃圾。
//
// 去向（规格 §11）：
//   card —— 进 description / personality / scenario / first_mes / mes_example / 提示词；
//   book —— 变成 character_book 条目，关键词触发；
//   meta —— 只进 extensions，聊天时由剧本按需取。
//
// 裁剪顺序（规格 §11.2）是硬约定：先砍最不痛的，砍完还超就拒绝保存，
// 绝不静默截断（截断会写出半句话的卡）。

import 'tavern_studio_draft.dart';

/// description 的上限（字）。各段预算加起来约 980，所以写得满的草稿一定会被裁，
/// 裁剪顺序才有意义；实卡里 900 字描述大约 600 token，够用又不至于每回合心疼。
const studioDescriptionCap = 900;

/// 一张卡最多带多少条世界书条目；多了每回合扫描也贵。
const studioBookLimit = 24;

/// 存卡失败的原因：写得太多，压不到预算里。
class StudioBuildError implements Exception {
  StudioBuildError(this.descriptionChars, this.cap);
  final int descriptionChars;
  final int cap;

  @override
  String toString() => 'StudioBuildError($descriptionChars > $cap)';
}

/// 条目想成为世界书条目时，用 `关键词|正文` 的写法（中英文竖线都认）。
/// 没有竖线时取开头几个字当关键词——这是 P0 的兜底，P2 由 AI 给正式关键词。
const _keySplit = ['|', '｜'];

/// 世界书条目：哪些字段会生成，是否常驻。
const _bookFields =
    <({String module, String field, String comment, bool constant})>[
      (module: 'world', field: 'worldRules', comment: '世界规则', constant: true),
      (module: 'world', field: 'places', comment: '地点', constant: false),
      (module: 'world', field: 'factions', comment: '势力', constant: false),
      (module: 'history', field: 'secret', comment: '秘密', constant: false),
      (module: 'history', field: 'timeline', comment: '经历', constant: false),
      (module: 'bond', field: 'growth', comment: '关系规则', constant: false),
      (module: 'bond', field: 'intimacy', comment: '边界', constant: false),
      (module: 'scene', field: 'direction', comment: '剧情方向', constant: false),
      (module: 'mind', field: 'trigger', comment: '情绪触发', constant: false),
      (module: 'profile', field: 'ability', comment: '能力', constant: false),
      (module: 'profile', field: 'weakness', comment: '弱点', constant: false),
    ];

/// 生成卡片 JSON（chara_card_v2 + data.character_book，和示例卡一个形状）。
///
/// [creator] 是这张卡署的"作者"，一般是 app 名；[fallbackName] 在草稿没写名字时用。
Map<String, Object?> buildStudioCard(
  StudioDraft draft, {
  required String creator,
  String fallbackName = '',
  int descriptionCap = studioDescriptionCap,
}) {
  final name = _text(draft, 'profile', 'name').trim();
  final description = _description(draft, cap: descriptionCap);
  final cards = _cards(draft, name: name.isEmpty ? fallbackName : name);

  return {
    'spec': 'chara_card_v2',
    'spec_version': '2.0',
    'data': {
      'name': name.isEmpty ? fallbackName : name,
      'nickname': _text(draft, 'profile', 'nickname'),
      'description': description,
      'personality': _personality(draft),
      'scenario': _scenario(draft),
      'first_mes': cards.first,
      'mes_example': _examples(draft),
      'creator_notes': _notes(draft),
      'system_prompt': _rules(draft),
      'post_history_instructions': _instructions(draft),
      'alternate_greetings': cards.alternate,
      'tags': _tags(draft),
      'creator': creator,
      'character_version': '1.0',
      'extensions': {
        'dshgo': {
          'studio': draft.toJson(),
          // 状态定义跟着卡走：模板折出来的，或者 AI 给的一版。
          if (draft.state case final state?) 'state': state,
        },
      },
      if (_book(draft, name: name).isNotEmpty)
        'character_book': {'entries': _book(draft, name: name)},
    },
  };
}

// ── 各段 ────────────────────────────────────────────────────────────────────

String _text(StudioDraft draft, String module, String field) =>
    draft.text(module, field);

List<String> _items(StudioDraft draft, String module, String field) => [
  for (final item in draft.items(module, field))
    if (item.trim().isNotEmpty) item.trim(),
];

/// 一行的"身份"：二十四岁 · 女 · 医师。
String _identityLine(StudioDraft draft) {
  final parts = [
    _text(draft, 'profile', 'age').trim(),
    _text(draft, 'profile', 'gender').trim(),
    _text(draft, 'profile', 'species').trim(),
    _text(draft, 'profile', 'identity').trim(),
  ].where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  // 年龄后面跟"岁"更像人话；写了"24"或"二十四"都行。
  final age = parts.first;
  final withAge = RegExp(r'[0-9]').hasMatch(age) && !age.endsWith('岁')
      ? '$age 岁'
      : age;
  return [withAge, ...parts.skip(1)].join(' · ');
}

String _description(StudioDraft draft, {required int cap}) {
  final sections = <String>[
    _cut(_text(draft, 'profile', 'appearance'), 160),
    _identityLine(draft),
    _cut(_text(draft, 'profile', 'body'), 120),
    _cut(_text(draft, 'mind', 'inner'), 160),
    _joinPair(
      _text(draft, 'bond', 'initial'),
      _text(draft, 'bond', 'impression'),
      140,
    ),
    _cut(_text(draft, 'history', 'family'), 140),
    _cut(_text(draft, 'history', 'upbringing'), 140),
    _cut(_text(draft, 'mind', 'flaw'), 80),
  ];
  return _fitDescription(sections, cap);
}

/// 按 §11.2 的顺序往下砍，砍到 [cap] 以内。
String _fitDescription(List<String> sections, int cap) {
  final kept = [...sections];
  var text = _joinSections(kept);
  if (text.length <= cap) return text;

  // 1. 经历压到 40 字
  for (final index in [5, 6]) {
    if (index < kept.length) kept[index] = _cut(kept[index], 40);
  }
  text = _joinSections(kept);
  if (text.length <= cap) return text;

  // 2. 内在性格只留一句
  kept[3] = _firstSentence(kept[3]);
  text = _joinSections(kept);
  if (text.length <= cap) return text;

  // 3. 印象整段移除
  kept[4] = '';
  text = _joinSections(kept);
  if (text.length <= cap) return text;

  // 4. 体态整段移除
  kept[2] = '';
  text = _joinSections(kept);
  if (text.length <= cap) return text;

  // 5. 还超：不截断，交给调用方拒绝保存
  throw StudioBuildError(text.length, cap);
}

String _joinSections(List<String> sections) =>
    sections.where((section) => section.trim().isNotEmpty).join('\n\n');

String _joinPair(String a, String b, int budget) {
  final parts = [a.trim(), b.trim()].where((part) => part.isNotEmpty);
  return _cut(parts.join('；'), budget);
}

String _personality(StudioDraft draft) {
  final parts = [
    _items(draft, 'mind', 'surface').join('、'),
    _items(draft, 'voice', 'tone').join('、'),
    _text(draft, 'profile', 'habits').trim(),
    _text(draft, 'voice', 'wording').trim(),
    _text(draft, 'voice', 'emotion').trim(),
  ].where((part) => part.isNotEmpty);
  return _cut(parts.join('；'), 240);
}

String _scenario(StudioDraft draft) {
  final parts = [
    _text(draft, 'scene', 'meeting').trim(),
    _text(draft, 'scene', 'backdrop').trim(),
    _text(draft, 'scene', 'tension').trim(),
  ].where((part) => part.isNotEmpty);
  return _cut(parts.join('\n'), 220);
}

/// 开场白：`voice.firstMes` 优先，否则用第一个开场。
({String first, List<String> alternate}) _cards(
  StudioDraft draft, {
  required String name,
}) {
  final openings = _items(draft, 'scene', 'openings');
  final explicit = _text(draft, 'voice', 'firstMes').trim();
  final first = explicit.isNotEmpty
      ? explicit
      : (openings.isEmpty ? '' : openings.first);
  final alternate = [
    if (explicit.isEmpty && openings.length > 1) ...openings.skip(1),
    if (explicit.isNotEmpty) ...openings,
  ].where((line) => line.trim().isNotEmpty).take(4).toList();
  return (
    first: _cut(first, 320),
    alternate: [for (final line in alternate) _cut(line, 320)],
  );
}

String _examples(StudioDraft draft) {
  final samples = _items(draft, 'voice', 'samples').take(2).toList();
  if (samples.isEmpty) return '';
  return [
    for (final sample in samples)
      sample.contains('<START>') ? sample : '<START>\n$sample',
  ].join('\n\n');
}

String _notes(StudioDraft draft) {
  final parts = [
    if (_text(draft, 'soul', 'motive').trim().isNotEmpty)
      '动机：${_text(draft, 'soul', 'motive').trim()}',
    if (_text(draft, 'history', 'goal').trim().isNotEmpty)
      '目标：${_text(draft, 'history', 'goal').trim()}',
  ];
  return _cut(parts.join('\n'), 240);
}

String _rules(StudioDraft draft) {
  final parts = [
    if (_items(draft, 'rules', 'autonomy').isNotEmpty)
      '自主性：${_items(draft, 'rules', 'autonomy').join('、')}',
    if (_text(draft, 'rules', 'knowledge').trim().isNotEmpty)
      _text(draft, 'rules', 'knowledge').trim(),
    ..._items(draft, 'rules', 'principles').map((line) => '· $line'),
  ];
  return _cut(parts.join('\n'), 600);
}

String _instructions(StudioDraft draft) {
  final parts = [
    ..._items(draft, 'rules', 'interaction').map((line) => '· $line'),
    ..._items(draft, 'rules', 'consistency').map((line) => '· $line'),
  ];
  return _cut(parts.join('\n'), 400);
}

List<String> _tags(StudioDraft draft) {
  final tags = [
    ..._items(draft, 'mind', 'surface'),
    ..._items(draft, 'voice', 'tone'),
  ];
  final seen = <String>{};
  return [
    for (final tag in tags)
      if (seen.add(tag)) tag,
  ].take(6).toList();
}

// ── 世界书 ──────────────────────────────────────────────────────────────────

/// 草稿自己攒的条目（AI 生成或手写）排在前面，其次是列表字段里写的
/// `关键词|正文`。整段文字的字段（能力/弱点/秘密）没有关键词就不收——
/// 没关键词的条目等于常驻，那是每回合都烧钱。
List<Map<String, Object?>> _book(StudioDraft draft, {required String name}) {
  final entries = <Map<String, Object?>>[];
  var id = 0;
  for (final entry in draft.book) {
    if (entry.isEmpty) continue;
    final content = entry.content.trim();
    final keys = entry.keys.isEmpty ? [_leadingKey(content)] : entry.keys;
    entries.add({
      'id': id++,
      'keys': keys,
      'secondary_keys': <String>[],
      'comment': entry.title.trim().isEmpty
          ? _leadingKey(content)
          : entry.title.trim(),
      'content': content,
      'constant': entry.constant,
      'selective': false,
      'insertion_order': 100,
      'enabled': true,
      'position': entry.constant ? 'before_char' : 'after_char',
      'use_regex': false,
      'extensions': <String, Object?>{},
    });
    if (entries.length >= studioBookLimit) return entries;
  }
  for (final spec in _bookFields) {
    for (final raw in _items(draft, spec.module, spec.field)) {
      final (keys, content) = _splitEntry(raw);
      if (content.isEmpty) continue;
      entries.add({
        'id': id++,
        'keys': keys.isEmpty ? [_leadingKey(content)] : keys,
        'secondary_keys': <String>[],
        'comment': '${spec.comment}${name.isEmpty ? '' : ' · $name'}',
        'content': content,
        'constant': spec.constant,
        'selective': false,
        'insertion_order': 100,
        'enabled': true,
        'position': spec.constant ? 'before_char' : 'after_char',
        'use_regex': false,
        'extensions': <String, Object?>{},
      });
      if (entries.length >= studioBookLimit) return entries;
    }
  }
  return entries;
}

/// `关键词|正文` → ([关键词…], 正文)。中英文竖线都认，关键词可以用逗号分多个。
(List<String>, String) _splitEntry(String raw) {
  for (final split in _keySplit) {
    final at = raw.indexOf(split);
    if (at > 0) {
      final keys = [
        for (final key in raw.substring(0, at).split(RegExp('[,，、]')))
          if (key.trim().isNotEmpty) key.trim(),
      ];
      return (keys, raw.substring(at + 1).trim());
    }
  }
  return (const [], raw.trim());
}

/// 没写关键词时，用正文开头的名词性短语兜底（去标点，最多 6 字）。
String _leadingKey(String content) {
  final head = content.split(RegExp('[，。；、,.;\\n]')).first.trim();
  return head.length <= 6 ? head : head.substring(0, 6);
}

// ── 小工具 ──────────────────────────────────────────────────────────────────

/// 截到 [budget] 字以内，尽量在句号/逗号/换行处断，不留半句话。
String _cut(String text, int budget) {
  final value = text.trim();
  if (value.length <= budget) return value;
  final head = value.substring(0, budget);
  final at = head.lastIndexOf(RegExp('[。！？；，、\\n]'));
  if (at > budget * 0.5) return head.substring(0, at + 1);
  return head;
}

String _firstSentence(String text) {
  final value = text.trim();
  if (value.isEmpty) return '';
  final at = value.indexOf(RegExp('[。！？\\n]'));
  return at < 0 ? value : value.substring(0, at + 1);
}
