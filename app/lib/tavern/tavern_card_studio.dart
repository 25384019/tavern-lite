// AI 制卡: one sentence in, a card out.
//
// The app has no card-writing wizard upstream, so this layer is ours: it turns
// the brief into a chat-completions request, and turns whatever the model says
// back into a V2 card the library can take in. Everything here is pure (no
// widgets, no engine, no network) so it can be tested on the host.

import 'dart:convert';

import 'preset_persona.dart';

/// How much card the brief asks for. The model is told, and [maxTokens] leaves
/// it room; the reply is cut off short rather than the request failing.
enum TavernCardLength {
  brief(maxTokens: 1200),
  standard(maxTokens: 2000),
  rich(maxTokens: 3000);

  const TavernCardLength({required this.maxTokens});
  final int maxTokens;

  /// What the prompt asks for, in the reply's language.
  String get ask => switch (this) {
    brief =>
      'Keep it short: description 120-200 characters, first_mes 120-200.',
    standard =>
      'Standard length: description 200-400 characters, first_mes 200-350.',
    rich => 'Rich: description 400-700 characters, first_mes 350-600.',
  };

  String get askZh => switch (this) {
    brief => '简短：description 120-200 字，first_mes 120-200 字。',
    standard => '标准：description 200-400 字，first_mes 200-350 字。',
    rich => '详细：description 400-700 字，first_mes 350-600 字。',
  };
}

/// The one JSON object the model must return, as a shape it can follow.
const tavernCardFields = [
  'name',
  'description',
  'personality',
  'scenario',
  'first_mes',
  'mes_example',
  'alternate_greetings',
  'tags',
  'creator_notes',
];

const _systemZh = '''
你在写一张可以直接用的酒馆角色卡。根据用户的一句话需求，把角色写完整。

只输出一个 JSON 对象，不要解释，不要 markdown 代码块，不要前后缀。字段：

- name：名字，2 到 8 个字，像真人名
- description：外貌与身份，写长相、穿着、年纪、身份、和 {{user}} 的关系。第三人称。
- personality：性格与说话方式，写清语气、口头禅、在意什么、嘴上怎么说心里怎么想
- scenario：开场时的处境，一句话交代时间地点和正在发生什么
- first_mes：角色说的第一段话。第一人称，带动作和神态，动作用 *星号* 括起来
- mes_example：两段对话示例，用 <START> 开头，写成 {{user}}: … / {{char}}: … 的格式
- alternate_greetings：1 到 2 条备选开场，字符串数组
- tags：3 到 6 个标签，字符串数组
- creator_notes：一句话说明这张卡适合怎么玩

用 {{user}} 指代用户，用 {{char}} 指代角色。全部写中文。不要写任何世界观之外的设定。''';

const _systemEn = '''
You write character cards for a tavern app. From one sentence, write the whole character.

Output one JSON object only. No explanation, no markdown fence, no preamble. Fields:

- name: a natural full name
- description: appearance and identity (looks, clothes, age, role, relation to {{user}}), third person
- personality: temperament and speech (tone, catchphrases, what they care about, what they would never say)
- scenario: where the scene opens, one sentence of time, place and what is happening
- first_mes: the character's opening line, first person, with action and expression in *asterisks*
- mes_example: two exchanges, each starting with <START>, written as {{user}}: … / {{char}}: …
- alternate_greetings: 1-2 alternate openings, array of strings
- tags: 3-6 tags, array of strings
- creator_notes: one line on how to play this card

Use {{user}} for the user and {{char}} for the character. Write in English.''';

/// What the writer already decided, as opposed to what the model invents.
///
/// 快速创作 fills only [idea]; 高级创作 fills any of the rest. Each non-empty
/// field becomes one line of the brief, so an empty field never reaches the
/// model and cannot be contradicted.
class TavernCardWish {
  const TavernCardWish({
    required this.idea,
    this.name = '',
    this.identity = '',
    this.world = '',
    this.relation = '',
    this.traits = const [],
    this.extra = '',
    this.length = TavernCardLength.standard,
    this.english = false,
  });

  /// 角色核心创意: the free-text brief, required.
  final String idea;

  /// 角色姓名; empty means the model names them.
  final String name;

  /// 角色身份, e.g. 医师.
  final String identity;

  /// 世界观, one of the offered backgrounds.
  final String world;

  /// 与玩家关系.
  final String relation;

  /// 性格标签, any number of them.
  final List<String> traits;

  /// 补充设定: experiences, secrets, rules the card must keep.
  final String extra;

  final TavernCardLength length;
  final bool english;

  /// True when nothing beyond the idea was chosen (快速创作 with defaults).
  bool get isQuick =>
      name.trim().isEmpty &&
      identity.trim().isEmpty &&
      world.trim().isEmpty &&
      relation.trim().isEmpty &&
      traits.isEmpty &&
      extra.trim().isEmpty;
}

/// The chat-completions messages for one wish.
///
/// [TavernCardWish.english] follows the app's language: the card is written in
/// the language the reader will read it in.
List<Map<String, Object?>> tavernCardMessages(
  TavernCardWish wish, {
  String? persona,
}) {
  final brief = wish.idea.trim();
  final ask = StringBuffer();
  final name = wish.name.trim();
  final identity = wish.identity.trim();
  final world = wish.world.trim();
  final relation = wish.relation.trim();
  final traits = [
    for (final trait in wish.traits)
      if (trait.trim().isNotEmpty) trait.trim(),
  ];
  final extra = wish.extra.trim();

  if (wish.english) {
    ask.write('The card:\n$brief');
    if (name.isNotEmpty) ask.write('\nName: $name exactly.');
    if (identity.isNotEmpty) ask.write('\nIdentity: $identity.');
    if (world.isNotEmpty) {
      ask.write('\nSetting: $world. Keep the whole card inside it.');
    }
    if (relation.isNotEmpty) ask.write('\nRelation to {{user}}: $relation.');
    if (traits.isNotEmpty) {
      ask.write('\nPersonality must include: ${traits.join(', ')}.');
    }
    if (extra.isNotEmpty) ask.write('\nAlso keep (do not rewrite):\n$extra');
    ask.write('\n${wish.length.ask}');
  } else {
    ask.write('这张卡：\n$brief');
    if (name.isNotEmpty) ask.write('\n名字必须叫「$name」，不要换。');
    if (identity.isNotEmpty) ask.write('\n身份：$identity。');
    if (world.isNotEmpty) ask.write('\n世界观：$world。整张卡都要落在这个世界观里。');
    if (relation.isNotEmpty) ask.write('\n和 {{user}} 的关系：$relation。');
    if (traits.isNotEmpty) ask.write('\n性格必须包含：${traits.join('、')}。');
    if (extra.isNotEmpty) ask.write('\n还要照这个写（不要改写、不要漏）：\n$extra');
    ask.write('\n${wish.length.askZh}');
  }
  return withPersona([
    {'role': 'system', 'content': wish.english ? _systemEn : _systemZh},
    {'role': 'user', 'content': ask.toString()},
  ], persona);
}

/// The request body: no history, no preset, a warm temperature (a card wants
/// some invention) and a hard ceiling so a runaway reply still ends.
///
/// [persona] is the user's own preset layer (越狱/文风), prepended as its own
/// system message; the task's system message stays last so the JSON shape wins.
Map<String, Object?> tavernCardRequestBody(
  TavernCardWish wish, {
  String? persona,
}) => {
  'messages': tavernCardMessages(wish, persona: persona),
  'temperature': 1.0,
  'max_tokens': wish.length.maxTokens,
};

/// 把字符串值里**没转义的引号**补成 `\"`。
///
/// 真实现场：模型写 `"personality":"习惯用"嗯"开头。"` —— 中间的引号没转义，
/// 整段 JSON 当场不合法。判据是「这个引号后面跟的字符」：
/// 紧跟 `, : } ]` 或到头 = 字符串真的结束；跟着别的（字） = 是内容里的引号。
String tavernCardEscapeQuotes(String body) {
  final out = StringBuffer();
  var inString = false;
  var escaped = false;
  for (var i = 0; i < body.length; i++) {
    final ch = body[i];
    if (!inString) {
      out.write(ch);
      if (ch == '"') inString = true;
      continue;
    }
    if (escaped) {
      out.write(ch);
      escaped = false;
      continue;
    }
    if (ch == r'\') {
      out.write(ch);
      escaped = true;
      continue;
    }
    if (ch != '"') {
      out.write(ch);
      continue;
    }
    var j = i + 1;
    while (j < body.length && ' \n\r\t'.contains(body[j])) {
      j++;
    }
    final next = j < body.length ? body[j] : '';
    if (next.isEmpty ||
        next == ',' ||
        next == ':' ||
        next == '}' ||
        next == ']') {
      out.write('"');
      inString = false;
    } else {
      out.write(r'\"');
    }
  }
  return out.toString();
}

/// 把一段被截断的 JSON 补成能解析的样子；补不了返回 null。
///
/// 真实模型写到一半撞上 token 上限时，尾巴会是「半个字符串」「悬空的逗号」
/// 或者「写到一半的 key」。这里从第一个 `{` 开始扫，记下括号栈，退到最后一个
/// 完整的值，再按栈把还开着的括号补上。只在确实缺尾巴时动手。
String? tavernCardRepair(String reply) {
  final start = reply.indexOf('{');
  if (start < 0) return null;
  final body = reply.substring(start);

  // 整段本来就能解析：没截断，别动手。
  try {
    jsonDecode(body);
    return null;
  } on FormatException {
    // 继续修
  }

  // 再试：砍到最后一个 `}`，万一后面只是些废话。
  final lastBrace = body.lastIndexOf('}');
  if (lastBrace > 0) {
    try {
      jsonDecode(body.substring(0, lastBrace + 1));
      return body.substring(0, lastBrace + 1);
    } on FormatException {
      // 继续修
    }
  }

  var inString = false;
  var escaped = false;
  final stack = <String>[];
  var lastValueEnd = -1; // 最后一个「不在字符串里、且栈非空」的分隔点
  for (var i = 0; i < body.length; i++) {
    final ch = body[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
        lastValueEnd = i;
      }
      continue;
    }
    switch (ch) {
      case '"':
        inString = true;
      case '{':
        stack.add('}');
      case '[':
        stack.add(']');
      case '}' || ']':
        if (stack.isNotEmpty) stack.removeLast();
      case ', ' || ',':
        if (stack.isNotEmpty) lastValueEnd = i;
    }
  }

  // 已经闭合了：说明不是截断，别乱修。
  if (stack.isEmpty) return null;

  String close(String half, {required bool openString}) {
    var out = half;
    if (openString) out = '$out"';
    // 悬空的逗号、冒号、顿号、句末标点都去掉。
    out = out.replaceFirst(RegExp(r'[\s,，:：、]+$'), '');
    return out + stack.reversed.join();
  }

  // 1) 就地补：把半个字符串收上，再补括号。
  final first = close(body, openString: inString);
  try {
    jsonDecode(first);
    return first;
  } on FormatException {
    // 继续
  }

  // 2) 退到最后一个完整的值再补（丢掉写到一半的那一项）。
  if (lastValueEnd > 0) {
    final cut = body.substring(0, lastValueEnd + 1);
    // 重算切点之后的栈
    final stack2 = <String>[];
    var inStr = false;
    var esc = false;
    for (final ch in cut.split('')) {
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (ch == r'\') {
          esc = true;
        } else if (ch == '"') {
          inStr = false;
        }
        continue;
      }
      if (ch == '"') {
        inStr = true;
      } else if (ch == '{') {
        stack2.add('}');
      } else if (ch == '[') {
        stack2.add(']');
      } else if ((ch == '}' || ch == ']') && stack2.isNotEmpty) {
        stack2.removeLast();
      }
    }
    var second = cut.replaceFirst(RegExp(r'[\s,，:：、]+$'), '');
    second = second + stack2.reversed.join();
    try {
      jsonDecode(second);
      return second;
    } on FormatException {
      return null;
    }
  }
  return null;
}

/// Strips a markdown fence and any prose around the object, then decodes it.
///
/// Models wrap JSON in ```json fences, prefix 「好的，这是你的卡：」, or emit
/// trailing text. All of that is recovered here; anything unrecoverable is null,
/// and the caller shows the raw reply instead of guessing.
Map<String, Object?>? tavernCardParse(String reply) {
  var text = reply.trim();
  if (text.isEmpty) return null;
  // ```json … ``` or ``` … ```
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
  if (fence != null) text = fence.group(1)!.trim();
  final start = text.indexOf('{');
  // 别盲目砍到最后一个 `}`：描述里常出现 `{{user}}`，那个 `}` 会把后面的字段
  // 整段切掉（真实现场：性格全丢）。留两份候选，先试原样。
  final end = text.lastIndexOf('}');
  final trimmed = start >= 0 && end > start
      ? text.substring(start, end + 1)
      : null;
  if (start > 0) text = text.substring(start);
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    // 真实模型的两个常见毛病，按顺序修：
    //  1. 字符串里的引号没转义（`口头禅是"灯亮着呢"`）——把内层引号补成 \"
    //  2. 写到一半撞上 max_tokens，JSON 缺个尾巴——退到最后一个完整的值再收尾
    for (final candidate in [
      if (trimmed != null) trimmed,
      tavernCardEscapeQuotes(text),
      if (tavernCardRepair(tavernCardEscapeQuotes(text)) case final fixed?)
        fixed,
      if (tavernCardRepair(text) case final fixed?) fixed,
    ]) {
      try {
        decoded = jsonDecode(candidate);
        break;
      } on FormatException {
        decoded = null;
      }
    }
    // ?????????????????
    if (decoded == null) return _salvage(text);
  }
  if (decoded is! Map<String, Object?>) {
    // 最后的兜底：JSON 修不好（内层引号 + 截断 + 缺括号同时出现），
    // 就按键名直接扫值。宁可少几点内容，也别让人白花一次 token。
    return _salvage(text);
  }
  // Some models wrap the card in CCv3's `data`.
  final data = decoded['data'];
  final parsed = _normalize(
    data is Map<String, Object?> && data['name'] is String ? data : decoded,
  );
  if (parsed == null) return _salvage(text);
  // 修 JSON 时可能把「写到一半的字段」整个丢掉（比如截断在 personality 里）：
  // 能扫回来的就补上，免得预览里少一整段却看不出来。
  final salvaged = _salvage(text);
  if (salvaged == null) return parsed;
  return {
    for (final entry in parsed.entries)
      entry.key: switch (entry.value) {
        final String s when s.trim().isEmpty =>
          salvaged[entry.key] ?? entry.value,
        final List<Object?> l when l.isEmpty =>
          salvaged[entry.key] ?? entry.value,
        _ => entry.value,
      },
  };
}

/// 字段的常见别名：模型（尤其是中文提示下）未必用我们给的键名。
///
/// 真实案例：提示里写的是 `name` / `description`，模型回了 `名字` / `描述`，
/// 解析出来没有 `name`，整张卡就被判失败——用户白花了 token。
const _fieldAliases = <String, List<String>>{
  'name': ['name', 'char_name', 'character_name', '名字', '姓名', '角色名', '名称'],
  'description': ['description', 'desc', '描述', '人设', '角色描述', '外貌描述'],
  'personality': ['personality', '性格', '个性'],
  'scenario': ['scenario', '场景', '背景', '情境'],
  'first_mes': [
    'first_mes',
    'first_message',
    'firstMessage',
    'greeting',
    '开场白',
    '问候语',
    '初始消息',
  ],
  'mes_example': ['mes_example', 'example_dialogue', '示例对话', '对话示例'],
  'creator_notes': ['creator_notes', 'creatorNotes', '作者说明', '备注'],
  'alternate_greetings': [
    'alternate_greetings',
    'alternateGreetings',
    '备用开场白',
    '其他开场白',
  ],
  'tags': ['tags', '标签'],
};

/// 按别名取值（先直接键，再别名，再大小写不敏感）。
Object? _field(Map<String, Object?> raw, String key) {
  if (raw.containsKey(key)) return raw[key];
  for (final alias in _fieldAliases[key] ?? const <String>[]) {
    if (raw.containsKey(alias)) return raw[alias];
  }
  final lowered = {for (final e in raw.entries) e.key.toLowerCase(): e.value};
  for (final alias in _fieldAliases[key] ?? const <String>[]) {
    final value = lowered[alias.toLowerCase()];
    if (value != null) return value;
  }
  return null;
}

/// 兜底：按键名从一段（可能根本不合法的）文本里把值抠出来。
///
/// 值的结束判据和转义规则一致：一个引号，后面（跳过空白）是 `,` `}` `]` 或者到头了。
/// 这样 `用"嗯"开头` 里的引号不会被当成结束符。抠不到任何东西就返回 null。
Map<String, Object?>? _salvage(String text) {
  String? grab(String key) {
    for (final alias in _fieldAliases[key] ?? [key]) {
      for (final name in {key, alias}) {
        final at = RegExp('"${RegExp.escape(name)}"\\s*:\\s*"')
            .firstMatch(text);
        if (at == null) continue;
        final out = StringBuffer();
        var i = at.end;
        var escaped = false;
        while (i < text.length) {
          final ch = text[i];
          if (escaped) {
            out.write(ch);
            escaped = false;
            i++;
            continue;
          }
          if (ch == r'\') {
            escaped = true;
            i++;
            continue;
          }
          if (ch == '"') {
            var j = i + 1;
            while (j < text.length && ' \n\r\t'.contains(text[j])) {
              j++;
            }
            final next = j < text.length ? text[j] : '';
            if (next.isEmpty || next == ',' || next == '}' || next == ']') {
              return out.toString();
            }
          }
          out.write(ch);
          i++;
        }
        // 没闭合（截断在字符串里）：到这儿为止都算值。
        final value = out.toString();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  final raw = <String, Object?>{
    'name': grab('name') ?? '',
    'description': grab('description') ?? '',
    'personality': grab('personality') ?? '',
    'scenario': grab('scenario') ?? '',
    'first_mes': grab('first_mes') ?? '',
    'mes_example': grab('mes_example') ?? '',
    'creator_notes': grab('creator_notes') ?? '',
  };
  if (_string(raw['name']).trim().isEmpty &&
      _string(raw['description']).trim().isEmpty &&
      _string(raw['first_mes']).trim().isEmpty) {
    return null;
  }
  return _normalize(raw);
}

/// The usable fields of whatever the model returned, or null when there is
/// nothing usable at all.
///
/// 名字缺失但别的字段有内容时，给一个占位名（预览里能看、能丢弃），
/// 比整份丢掉让人白花 token 强。
Map<String, Object?>? _normalize(Map<String, Object?> raw) {
  final name = _string(_field(raw, 'name')).trim();
  final description = _string(_field(raw, 'description'));
  final firstMes = _string(_field(raw, 'first_mes'));
  if (name.isEmpty && description.isEmpty && firstMes.isEmpty) return null;
  return {
    'name': name.isEmpty ? '未命名角色' : name,
    'description': description,
    'personality': _string(_field(raw, 'personality')),
    'scenario': _string(_field(raw, 'scenario')),
    'first_mes': firstMes,
    'mes_example': _string(_field(raw, 'mes_example')),
    'creator_notes': _string(_field(raw, 'creator_notes')),
    'alternate_greetings': _strings(_field(raw, 'alternate_greetings')),
    'tags': _strings(_field(raw, 'tags')),
  };
}

/// Strings, or a single string split on newlines/commas (models drift).
String _string(Object? value) => switch (value) {
  null => '',
  String s => s,
  num n => '$n',
  List l => [
    for (final item in l)
      if (item is String) item,
  ].join('\n'),
  _ => '',
};

/// String lists; a lone string becomes one entry per line.
List<String> _strings(Object? value) => switch (value) {
  null => const [],
  String s => [
    for (final line in s.split(RegExp(r'[\r\n,，、]+')).map((t) => t.trim()))
      if (line.isNotEmpty) line,
  ],
  List l => [
    for (final item in l)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ],
  _ => const [],
};

/// The V2 card the library takes in, from [data] ([tavernCardParse]'s result).
/// [creator] is the app's own name for this, in its language.
Map<String, Object?> tavernCardJson(
  Map<String, Object?> data, {
  required String creator,
}) => {
  'spec': 'chara_card_v2',
  'spec_version': '2.0',
  'data': {
    ...data,
    'mes_example': _string(data['mes_example']),
    'creator': creator,
    'character_version': '',
    'extensions': <String, Object?>{},
  },
};
