// 世界书 AI 创作：蓝图 → 条目规划 → 分批生成 → 一致性审查。
//
// 四步各是一次独立的请求，每步的产物都能给人看、改、重跑；只有最后一步
// 把条目写进书。这样一批失败只重跑那一批，不会把前面推翻。
//
// 纯函数（提示与解析），网络那一段由页面用 tavernModelClientProvider 做。

import 'dart:convert';

import 'preset_persona.dart';
import 'tavern_card_studio.dart' show tavernCardEscapeQuotes, tavernCardRepair;

/// 第一步：世界蓝图。
class LorebookBlueprint {
  const LorebookBlueprint({
    required this.name,
    required this.overview,
    this.rules = const [],
    this.factions = const [],
    this.places = const [],
    this.conflicts = const [],
  });

  final String name;
  final String overview;
  final List<String> rules;
  final List<String> factions;
  final List<String> places;
  final List<String> conflicts;
}

/// 第二步：预计要生成的条目（只有标题和用途，正文留到第三步）。
class LorebookPlanEntry {
  const LorebookPlanEntry({required this.title, this.kind = '', this.why = ''});
  final String title;
  final String kind;
  final String why;
}

/// 第三步：一条真正的条目。
class LorebookDraftEntry {
  const LorebookDraftEntry({
    required this.title,
    required this.content,
    this.keys = const [],
    this.constant = false,
  });
  final String title;
  final String content;
  final List<String> keys;
  final bool constant;
}

/// 第四步：查出来的问题。
class LorebookIssue {
  const LorebookIssue({
    required this.title,
    required this.issue,
    this.suggest = '',
  });
  final String title;
  final String issue;
  final String suggest;
}

/// 一批最多几条：一次让模型写几十条，质量会掉、失败也难救。
const lorebookBatchLimit = 8;

/// 世界书的内容类型。
///
/// 真的在用的书根本不是一种东西：文风书写的是「怎么写」，破甲书写的是
/// 「不许干什么」，玩法书写的是状态与判定，描写补充是一堆关键词驱动的短词条，
/// 世界设定才是地点、势力、人物。提示词必须分开，不然生成出来永远是设定书。
enum LorebookKind { world, style, guardrail, mechanic, lexicon }

extension LorebookKindSpec on LorebookKind {
  /// 一次发几条：正文越长，一批越少（否则 batch 的 max_tokens 会把它截断）。
  int get batchSize => switch (this) {
    LorebookKind.world => 4,
    LorebookKind.style => 3,
    LorebookKind.guardrail => 3,
    LorebookKind.mechanic => 5,
    LorebookKind.lexicon => 6,
  };

  /// 这种书该有多少条。[target] 是篇幅档位给的数量，个别类型不看篇幅。
  int target(int target) => switch (this) {
    LorebookKind.style => 6,
    LorebookKind.guardrail => 3,
    _ => target,
  };

  /// 一批正文的 token 上限。
  int get batchTokens => switch (this) {
    LorebookKind.style => 3600,
    LorebookKind.lexicon => 3200,
    LorebookKind.mechanic => 3000,
    _ => 2400,
  };

  /// 这种书默认写不写卡（正文的长度和形状差太多，分批大小也跟着变）。
  String get hintZh => switch (this) {
    LorebookKind.world => '地点、势力、人物、规则——聊到才出现的设定',
    LorebookKind.style => '怎么写：视角、句子、节奏、感官；条目全部常驻',
    LorebookKind.guardrail => '不许干什么：代替玩家说话、出戏、硬拒；一两百字一条',
    LorebookKind.mechanic => '玩法怎么跑：状态、阶段、判定；总则常驻，其余触发',
    LorebookKind.lexicon => '一堆关键词驱动的短词条：情境、部位、场面',
  };

  String get hintEn => switch (this) {
    LorebookKind.world => 'Places, factions, people, rules — only what the chat needs',
    LorebookKind.style => 'How to write: POV, sentences, rhythm, senses; all constant',
    LorebookKind.guardrail => 'What the model must not do; 80-200 chars, all constant',
    LorebookKind.mechanic => 'How the system runs: state, stages, checks',
    LorebookKind.lexicon => 'Many short keyword-driven entries: scenes, body, moments',
  };
}

const _systemZh = '''
你在帮用户建一本 SillyTavern 兼容的世界书。只输出一个 JSON 对象，不要解释，不要 markdown 代码块。
用 {{user}} 指代玩家、{{char}} 指代角色。保持用户给的语言。''';

const _systemEn = '''
You build a SillyTavern-compatible world book. Answer with one JSON object only — no prose, no fence.
Use {{user}} for the player and {{char}} for the character. Keep the language the user writes in.''';

/// 每类书的 system：基底提示 + 一句「这本是什么书」。
String _system(LorebookKind kind, bool english) {
  final base = english ? _systemEn : _systemZh;
  final extra = switch (kind) {
    LorebookKind.world => '',
    LorebookKind.style => english
        ? 'This book records how to write, not what the world is: no invented places or people.'
        : '这本书记录的是「怎么写」，不是「世界是什么」：不要编地名和人物。',
    LorebookKind.guardrail => english
        ? 'This book lists orders the model must obey; write them as imperatives.'
        : '这本书记的是模型必须照做的命令，写成命令句。',
    LorebookKind.mechanic => english
        ? 'This book is a system: state, stages, checks. Every rule must be checkable in chat.'
        : '这是一套机制：状态、阶段、判定。每条都要能在对话里判定。',
    LorebookKind.lexicon => english
        ? 'This book is a lexicon: many short entries, each triggered by words a chat would say.'
        : '这是一本词条库：条目多、每条短，靠对话里会说到的词触发。',
  };
  return extra.isEmpty ? base : '$base\n$extra';
}

/// 蓝图的 JSON 形状：每类书要的东西不一样。
String _blueprintSpec(LorebookKind kind, bool english) => switch (kind) {
  LorebookKind.world => english
      ? 'Give one JSON object: {"name": "", "overview": "150-300 chars", '
            '"rules": [""], "factions": [""], "places": [""], "conflicts": [""]}. '
            'Rules are the hard facts; factions and places list only names; '
            'conflicts are what is already tense before the story starts.'
      : '给一个 JSON 对象：{"name": "", "overview": "150 到 300 字", '
            '"rules": [""], "factions": [""], "places": [""], "conflicts": [""]}。'
            'rules 是这个世界的硬设定；factions 和 places 只写名字；'
            'conflicts 是故事开始前就已经紧绷的矛盾。',
  LorebookKind.style => english
      ? 'Give one JSON object: {"name": "", "overview": "200-400 chars, a style guide you can paste '
            'straight into a prompt", "rules": ["5-8 hard rules about POV, sentence length, rhythm, '
            'sensory layers, words to avoid"]}. No places, no people.'
      : '给一个 JSON 对象：{"name": "", "overview": "200 到 400 字，写成一段直接能用的文风总则", '
            '"rules": ["5 到 8 条硬性写法：视角、句子长短、段落节奏、感官层次、要避开的词"]}。'
            '不要地名，不要人物。',
  LorebookKind.guardrail => english
      ? 'Give one JSON object: {"name": "", "overview": "100-200 chars on what must not happen", '
            '"rules": ["3-6 prohibitions, one line each"]}.'
      : '给一个 JSON 对象：{"name": "", "overview": "100 到 200 字，说清要防住什么", '
            '"rules": ["3 到 6 条禁令，一条一句"]}。',
  LorebookKind.mechanic => english
      ? 'Give one JSON object: {"name": "", "overview": "200-300 chars on how the system runs", '
            '"rules": ["4-8 rules with numbers and checks"]}.'
      : '给一个 JSON 对象：{"name": "", "overview": "200 到 300 字，玩法怎么跑", '
            '"rules": ["4 到 8 条带数值和判定的规则"]}。',
  LorebookKind.lexicon => english
      ? 'Give one JSON object: {"name": "", "overview": "100-200 chars on what it covers", '
            '"places": ["8-15 scene or body-part names"]}.'
      : '给一个 JSON 对象：{"name": "", "overview": "100 到 200 字，覆盖哪些情境", '
            '"places": ["8 到 15 个情境或部位的名字"]}。',
};

/// 第一步的提示：从一句创意到蓝图。
List<Map<String, Object?>> lorebookBlueprintMessages({
  required String idea,
  required String scale,
  LorebookKind kind = LorebookKind.world,
  String? persona,
  bool english = false,
}) => withPersona([
  {'role': 'system', 'content': _system(kind, english)},
  {
    'role': 'user',
    'content': [
      english ? 'The book:' : '这本世界书：',
      idea.trim(),
      '',
      english ? 'Scale: $scale.' : '规模：$scale。',
      '',
      _blueprintSpec(kind, english),
    ].join('\n'),
  },
], persona);

/// 规划的 JSON 形状：每类书规划的模块不一样。
String _planSpec(LorebookKind kind, int target, bool english) => switch (kind) {
  LorebookKind.world => english
      ? 'Plan about $target entries. One JSON object: '
            '{"entries": [{"title": "", "kind": "place|faction|person|rule|event|item", "why": ""}]}. '
            'Only plans, no content yet. Only what a chat would actually need.'
      : '规划大约 $target 条条目。一个 JSON 对象：'
            '{"entries": [{"title": "", "kind": "place|faction|person|rule|event|item", "why": ""}]}。'
            '只做规划，不写正文。只规划对话里真用得上的。',
  LorebookKind.style => english
      ? 'Plan 4-6 modules. One JSON object: '
            '{"entries": [{"title": "", "kind": "style", "why": ""}]}. '
            'Cover: overall guide / POV / sensory layers / dialogue and rhythm / forbidden clichés.'
      : '规划 4 到 6 个模块。一个 JSON 对象：'
            '{"entries": [{"title": "", "kind": "style", "why": ""}]}。'
            '覆盖：总则 / 叙述视角 / 感官层次 / 对话与节奏 / 禁忌套路。',
  LorebookKind.guardrail => english
      ? 'Plan 1-3 entries, one behaviour each. One JSON object: '
            '{"entries": [{"title": "", "kind": "rule", "why": ""}]}. '
            'Candidates: speaking for {{user}}, deciding for the player, stepping out of character, '
            'refusing the scene, summing up at the end.'
      : '规划 1 到 3 条，一条只管一件事。一个 JSON 对象：'
            '{"entries": [{"title": "", "kind": "rule", "why": ""}]}。'
            '候选：代替 {{user}} 说话 / 替玩家做决定 / 出戏解释 / 拒演 / 结尾总结。',
  LorebookKind.mechanic => english
      ? 'Plan a JSON object {"entries": [{"title": "", "kind": "rule|stage|table", "why": ""}]}: '
            'one overall rule (constant), 3-8 stages or states (keyword triggered), one check table.'
      : '规划一个 JSON 对象 {"entries": [{"title": "", "kind": "rule|stage|table", "why": ""}]}：'
            '1 条总则（常驻）、3 到 8 条状态或阶段（关键词触发）、1 张判定表。',
  LorebookKind.lexicon => english
      ? 'Plan $target entries, one scene or body part each, no duplicates. One JSON object: '
            '{"entries": [{"title": "", "kind": "scene|body|moment", "why": ""}]}.'
      : '规划 $target 条，每条一个情境或一个部位，不要重复。一个 JSON 对象：'
            '{"entries": [{"title": "", "kind": "scene|body|moment", "why": ""}]}。',
};

/// 第二步：按蓝图规划条目（只给标题/类型/为什么需要）。
List<Map<String, Object?>> lorebookPlanMessages({
  required LorebookBlueprint blueprint,
  required int target,
  LorebookKind kind = LorebookKind.world,
  String? persona,
  bool english = false,
}) => withPersona([
  {'role': 'system', 'content': _system(kind, english)},
  {
    'role': 'user',
    'content': [
      english ? 'Book: ${blueprint.name}' : '这本书：${blueprint.name}',
      blueprint.overview,
      if (blueprint.rules.isNotEmpty)
        '${english ? 'Rules' : '规则'}：${blueprint.rules.join('；')}',
      if (kind == LorebookKind.world && blueprint.factions.isNotEmpty)
        '${english ? 'Factions' : '势力'}：${blueprint.factions.join('、')}',
      if (blueprint.places.isNotEmpty)
        '${english ? 'Items' : '条目名'}：${blueprint.places.join('、')}',
      if (kind == LorebookKind.world && blueprint.conflicts.isNotEmpty)
        '${english ? 'Conflicts' : '矛盾'}：${blueprint.conflicts.join('；')}',
      '',
      _planSpec(kind, target, english),
    ].join('\n'),
  },
], persona);

/// 一批正文的形状：长度、关键词、常不常驻，每类书都不一样。
String _batchSpec(LorebookKind kind, bool english) => switch (kind) {
  LorebookKind.world => english
      ? 'One JSON object: {"entries": [{"title": "", "content": "300-600 chars", '
            '"keys": ["3-6 keys"], "constant": false}]}. '
            'Keys are what a chat says to trigger it: names, places, objects, nicknames. '
            'Write real detail, not a summary. At most one entry may be constant.'
      : '一个 JSON 对象：{"entries": [{"title": "", "content": "300 到 600 字", '
            '"keys": ["3 到 6 个关键词"], "constant": false}]}。'
            '关键词就是对话里会提到的名字、地点、东西、别称。'
            '要写具体，不要写成摘要。最多允许一条 constant: true。',
  LorebookKind.style => english
      ? 'One JSON object: {"entries": [{"title": "", "content": "400-900 chars", '
            '"keys": [], "constant": true}]}. Write rules for the writer, in the imperative. '
            'No story, no examples longer than one line.'
      : '一个 JSON 对象：{"entries": [{"title": "", "content": "400 到 900 字", '
            '"keys": [], "constant": true}]}。写的是给写作者的规矩，用命令句。'
            '不要讲故事，例子不超过一行。',
  LorebookKind.guardrail => english
      ? 'One JSON object: {"entries": [{"title": "", "content": "80-200 chars", '
            '"keys": [], "constant": true}]}. Short and absolute: say what must not happen '
            'and what to do instead.'
      : '一个 JSON 对象：{"entries": [{"title": "", "content": "80 到 200 字", '
            '"keys": [], "constant": true}]}。短、硬、没有余地：说清不许干什么，以及该干什么。',
  LorebookKind.mechanic => english
      ? 'One JSON object: {"entries": [{"title": "", "content": "200-500 chars", '
            '"keys": ["3-6 keys"], "constant": false}]}. Each entry must be checkable: '
            'state names, numbers, when it changes. Only the overall rule is constant.'
      : '一个 JSON 对象：{"entries": [{"title": "", "content": "200 到 500 字", '
            '"keys": ["3 到 6 个关键词"], "constant": false}]}。每条都要能判定：'
            '状态叫什么、数值多少、什么时候变。只有总则 constant: true。',
  LorebookKind.lexicon => english
      ? 'One JSON object: {"entries": [{"title": "", "content": "300-700 chars", '
            '"keys": ["4-8 keys"], "constant": false}]}. Body and senses only, in plain words; '
            'keys include slang and the words a player would actually type.'
      : '一个 JSON 对象：{"entries": [{"title": "", "content": "300 到 700 字", '
            '"keys": ["4 到 8 个关键词"], "constant": false}]}。只写身体和感官，用大白话；'
            '关键词要带上俗称和玩家真会打出来的词。',
};

/// 第三步：一批（≤ [LorebookKindSpec.batchSize] 条）的正文和关键词。
List<Map<String, Object?>> lorebookBatchMessages({
  required LorebookBlueprint blueprint,
  required List<LorebookPlanEntry> entries,
  LorebookKind kind = LorebookKind.world,
  String? persona,
  bool english = false,
}) => withPersona([
  {'role': 'system', 'content': _system(kind, english)},
  {
    'role': 'user',
    'content': [
      english ? 'Book: ${blueprint.name}' : '这本书：${blueprint.name}',
      blueprint.overview,
      if (blueprint.rules.isNotEmpty)
        '${english ? 'Rules' : '规则'}：${blueprint.rules.join('；')}',
      '',
      english ? 'Write these entries:' : '写这几条：',
      for (final entry in entries) '- ${entry.title}（${entry.kind}）',
      '',
      _batchSpec(kind, english),
    ].join('\n'),
  },
], persona);

/// 第四步：拿蓝图和已写的条目互相查。
List<Map<String, Object?>> lorebookCheckMessages({
  required LorebookBlueprint blueprint,
  required List<LorebookDraftEntry> entries,
  LorebookKind kind = LorebookKind.world,
  String? persona,
  bool english = false,
}) => withPersona([
  {'role': 'system', 'content': _system(kind, english)},
  {
    'role': 'user',
    'content': [
      english ? 'Book: ${blueprint.name}' : '这本书：${blueprint.name}',
      blueprint.overview,
      if (blueprint.rules.isNotEmpty)
        '${english ? 'Rules' : '规则'}：${blueprint.rules.join('；')}',
      '',
      english ? 'Entries written so far:' : '已经写好的条目：',
      for (final entry in entries)
        '- ${entry.title}：${_short(entry.content, 120)}',
      '',
      english
          ? 'Find contradictions with the brief or between entries, and entries that say nothing. '
                'One JSON object: {"issues": [{"title": "", "issue": "", "suggest": ""}]}. '
                'Say nothing if it is consistent.'
          : '找出和前面说的冲突、条目之间互相冲突、或者写了等于没写的地方。'
                '一个 JSON 对象：{"issues": [{"title": "", "issue": "", "suggest": ""}]}。'
                '没有就说没有，不要硬凑。',
    ].join('\n'),
  },
], persona);

String _short(String text, int limit) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= limit ? flat : '${flat.substring(0, limit)}…';
}

/// 请求体：温度比写卡低一点（设定要稳），上限按用途给。
Map<String, Object?> lorebookBody(
  List<Map<String, Object?>> messages, {
  int maxTokens = 1400,
  double temperature = 0.8,
}) => {
  'messages': messages,
  'temperature': temperature,
  'max_tokens': maxTokens,
};

/// 模型爱把 JSON 包在围栏里、前后带话；也会在正文里塞没转义的引号，
/// 或者被 max_tokens 截在半路。都救回来；救不回来返回 null。
///
/// 不拿 `lastIndexOf('}')` 当结尾：`{{user}}` 自己就带 `}`，截断也多的是
/// 这种情况——那正是制卡第一次失败的同一个坑。
Map<String, Object?>? lorebookJson(String reply) {
  var text = reply.trim();
  if (text.isEmpty) return null;
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
  if (fence != null) text = fence.group(1)!.trim();
  final repaired = tavernCardRepair(text);
  for (final candidate in [
    text,
    tavernCardEscapeQuotes(text),
    ?repaired,
    if (repaired != null) tavernCardEscapeQuotes(repaired),
  ]) {
    final decoded = _decodeFromFirstBrace(candidate);
    if (decoded != null) return decoded;
  }
  return null;
}

/// 从第一个 `{` 起，由后往前试几个 `}` 当结尾的 JSON。
Map<String, Object?>? _decodeFromFirstBrace(String text) {
  final start = text.indexOf('{');
  if (start < 0) return null;
  final ends = <int>[];
  for (var i = text.length - 1; i > start && ends.length < 6; i--) {
    if (text[i] == '}') ends.add(i);
  }
  for (final end in ends) {
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException {
      continue;
    }
  }
  return null;
}

List<String> _strings(Object? value) => [
  for (final item in (value is List ? value : const []))
    if (item is String && item.trim().isNotEmpty) item.trim(),
];

/// 蓝图：名字和概述都必须有，否则算失败。
LorebookBlueprint? lorebookBlueprintParse(String reply) {
  final json = lorebookJson(reply);
  if (json == null) return null;
  final name = json['name'] is String ? (json['name']! as String).trim() : '';
  final overview = json['overview'] is String
      ? (json['overview']! as String).trim()
      : '';
  if (name.isEmpty && overview.isEmpty) return null;
  return LorebookBlueprint(
    name: name.isEmpty ? '新的世界' : name,
    overview: overview,
    rules: _strings(json['rules']),
    factions: _strings(json['factions']),
    places: _strings(json['places']),
    conflicts: _strings(json['conflicts']),
  );
}

/// 规划：只要标题；同一个标题只留一次。
List<LorebookPlanEntry> lorebookPlanParse(String reply) {
  final json = lorebookJson(reply);
  if (json == null) return const [];
  final seen = <String>{};
  return [
    for (final item
        in (json['entries'] is List ? json['entries']! as List : const []))
      if (item is Map && item['title'] is String)
        if (seen.add((item['title']! as String).trim()) &&
            (item['title']! as String).trim().isNotEmpty)
          LorebookPlanEntry(
            title: (item['title']! as String).trim(),
            kind: item['kind'] is String
                ? (item['kind']! as String).trim()
                : '',
            why: item['why'] is String ? (item['why']! as String).trim() : '',
          ),
  ];
}

/// 一批条目：没有正文的丢掉；超过批上限的截掉（界面会提示）。
List<LorebookDraftEntry> lorebookBatchParse(String reply) {
  final json = lorebookJson(reply);
  if (json == null) return const [];
  return [
    for (final item
        in (json['entries'] is List ? json['entries']! as List : const []))
      if (item is Map &&
          item['content'] is String &&
          (item['content']! as String).trim().isNotEmpty)
        LorebookDraftEntry(
          title: item['title'] is String
              ? (item['title']! as String).trim()
              : '',
          content: (item['content']! as String).trim(),
          keys: _strings(item['keys']),
          constant: item['constant'] == true,
        ),
  ].take(lorebookBatchLimit).toList();
}

/// 审查：问题必须说清是哪儿。
List<LorebookIssue> lorebookCheckParse(String reply) {
  final json = lorebookJson(reply);
  if (json == null) return const [];
  return [
    for (final item
        in (json['issues'] is List ? json['issues']! as List : const []))
      if (item is Map &&
          item['issue'] is String &&
          (item['issue']! as String).trim().isNotEmpty)
        LorebookIssue(
          title: item['title'] is String
              ? (item['title']! as String).trim()
              : '',
          issue: (item['issue']! as String).trim(),
          suggest: item['suggest'] is String
              ? (item['suggest']! as String).trim()
              : '',
        ),
  ];
}

/// 把条目折成 ST 原生世界书的 `entries`（以 uid 为键），
/// 形状和 `putLorebook` 收到的完全一致。
Map<String, Object?> lorebookEntriesJson(List<LorebookDraftEntry> entries) => {
  for (final (index, entry) in entries.indexed)
    '$index': {
      'uid': index,
      'key': entry.keys,
      'keysecondary': <String>[],
      'comment': entry.title,
      'content': entry.content,
      'constant': entry.constant,
      'selective': false,
      'order': 100,
      'position': entry.constant ? 0 : 1,
      'disable': false,
      'use_regex': false,
      'probability': 100,
      'useProbability': false,
    },
};

// ── 单条条目的 AI ────────────────────────────────────────────────────────────

/// 一条条目可以做什么。
enum LorebookEntryAiAction { expand, trim, rewrite, keywords }

/// 单条条目的提示：按这本书的世界观和这条自己的设定来写。
List<Map<String, Object?>> lorebookEntryAiMessages({
  required String worldName,
  required String title,
  required List<String> keys,
  required String current,
  required LorebookEntryAiAction action,
  String instruction = '',
  bool english = false,
}) {
  final system = english
      ? 'You write one entry of a SillyTavern world book. Answer with the entry text only — '
            'no explanation, no fence, no quotes. Use {{user}} and {{char}}. Stay inside the world.'
      : '你在写一本酒馆世界书里的一条条目。只回条目正文，不要解释、不要代码块、不要加引号。'
            '用 {{user}} 指代玩家、{{char}} 指代角色。不要跑出这个世界。';
  final task = switch (action) {
    LorebookEntryAiAction.expand =>
      english ? 'Lengthen it; keep every fact.' : '写长一些，已有的事实一条都不要丢。',
    LorebookEntryAiAction.trim =>
      english
          ? 'Tighten it to about 70%; keep every fact.'
          : '压到七成左右，事实一条都不要丢。',
    LorebookEntryAiAction.rewrite =>
      english ? 'Rewrite it as asked, same facts.' : '按下面的要求重写，事实别变。',
    LorebookEntryAiAction.keywords =>
      english
          ? 'Answer with 2 to 6 trigger keys separated by commas, nothing else.'
          : '只回 2 到 6 个触发关键词，用逗号隔开，别的都不要。',
  };
  return [
    {'role': 'system', 'content': system},
    {
      'role': 'user',
      'content': [
        english ? 'World: $worldName' : '世界：$worldName',
        if (title.trim().isNotEmpty)
          '${english ? 'Entry' : '条目'}：${title.trim()}',
        if (keys.isNotEmpty) '${english ? 'Keys' : '关键词'}：${keys.join('、')}',
        if (current.trim().isNotEmpty) ...[
          '',
          english ? 'Now:' : '现在的内容：',
          current.trim(),
        ],
        if (instruction.trim().isNotEmpty) ...[
          '',
          english
              ? 'What I want: ${instruction.trim()}'
              : '我想要：${instruction.trim()}',
        ],
        '',
        task,
      ].join('\n'),
    },
  ];
}

/// 从回答里取出正文（JSON 的 content、围栏、或者整段散文都收）。
String? aiProseParse(String reply) {
  final text = reply.trim();
  if (text.isEmpty) return null;
  var inner = text;
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
  if (fence != null) inner = fence.group(1)!.trim();
  final start = inner.indexOf('{');
  final end = inner.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      final decoded = jsonDecode(inner.substring(start, end + 1));
      if (decoded is Map && decoded['content'] is String) {
        final content = (decoded['content']! as String).trim();
        return content.isEmpty ? null : content;
      }
    } on FormatException {
      // 不是 JSON，往下走
    }
  }
  final plain = text
      .replaceAll(RegExp(r'^```[a-zA-Z]*\s*'), '')
      .replaceAll(RegExp(r'```\s*$'), '')
      .trim();
  return plain.isEmpty ? null : plain;
}

/// 关键词那一种：把回答拆成几个关键词（太长的明显不是关键词）。
List<String> aiKeysParse(String reply) => [
  for (final part in reply.split(RegExp(r'[,，、\n]')))
    if (part.trim().isNotEmpty && part.trim().length <= 12) part.trim(),
];

// ── 制卡时顺手写一本卡内世界书 ───────────────────────────────────────────────

/// 一张刚写好的卡：给它写一本**自带**的世界书。
///
/// 进的是卡片的 `character_book`，跟着卡走——导入导出、换设备都在一起，
/// 不是资源库里另一本要对名字的书。[brief] 是用户自己写的一句方向（可空）。
List<Map<String, Object?>> cardBookMessages({
  required Map<String, Object?> card,
  String brief = '',
  String? persona,
  bool english = false,
  int count = 8,
}) {
  final data = switch (card['data']) {
    final Map<Object?, Object?> map => map.cast<String, Object?>(),
    _ => card,
  };
  String field(String key) => switch (data[key]) {
    final String text => text.trim(),
    _ => '',
  };
  final name = field('name');
  final description = _short(field('description'), 500);
  final personality = _short(field('personality'), 300);
  final scenario = _short(field('scenario'), 300);
  final want = brief.trim();
  final parts = <String>[
    if (english)
      'This world book belongs to one character card and must only hold true inside it. '
          'Never write generic setting the card does not need.'
    else
      '这本世界书跟着一张角色卡走，只在这张卡的世界里成立。'
          '不要写通用设定，也不要写和这张卡无关的地方。',
    '',
    english ? 'Card: $name' : '卡：$name',
    if (description.isNotEmpty) description,
    if (personality.isNotEmpty)
      '${english ? 'Personality' : '性格'}：$personality',
    if (scenario.isNotEmpty) '${english ? 'Scene' : '场景'}：$scenario',
    if (want.isNotEmpty) ...[
      '',
      english ? 'What I want in the book: $want' : '我要的世界书方向：$want',
    ],
    '',
    english
        ? 'Write about $count entries. One JSON object: '
              '{"entries": [{"title": "", "content": "300-600 chars", '
              '"keys": ["3-6 keys"], "constant": false}]}. '
              'Keys are the words a chat inside this card would actually say: names, places, '
              'objects, nicknames. At most one entry may be constant.'
        : '写 $count 条左右。一个 JSON 对象：'
              '{"entries": [{"title": "", "content": "300 到 600 字", '
              '"keys": ["3 到 6 个关键词"], "constant": false}]}。'
              '关键词就是这张卡的对话里真会出现的词：名字、地点、东西、别称。'
              '最多一条 constant: true。',
  ];
  return withPersona([
    {'role': 'system', 'content': _system(LorebookKind.world, english)},
    {'role': 'user', 'content': parts.join('\n')},
  ], persona);
}

/// 卡内世界书的回答：和一批条目同一个形状。
List<LorebookDraftEntry> cardBookParse(String reply) => lorebookBatchParse(reply);

/// 一条条目写成卡片 `character_book` 认的那套字段名
/// （和条目编辑页 `tavern_book_entry.dart` 用的是同一套）。
Map<String, Object?> cardBookEntryFields(LorebookDraftEntry entry) => {
  'comment': entry.title,
  'keys': entry.keys,
  'secondary_keys': const <String>[],
  'selective': false,
  'content': entry.content,
  'constant': entry.constant,
  'enabled': true,
  'insertion_order': 100,
  'position': entry.constant ? 'before_char' : 'after_char',
};
