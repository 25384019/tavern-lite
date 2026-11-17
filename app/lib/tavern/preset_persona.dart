// 生成前的一层「人格」：从用户自己的预设里取出系统提示，垫在任务提示前面。
//
// 只取真有人写内容的系统提示（main / nsfw / 越狱 / 文风这类），跳过 marker
// （对话示例、世界书前后、聊天历史这些占位），顺序照预设自己的 prompt_order。
// 一个都取不到就返回 null，调用方照原样发——不因为选了个空预设就发不出去。
//
// 两个坑（2026-11-17 对着 15 本真实世界书和 ST 预设的结构核过）：
//   1. 预设里的 `{{char}}` / `{{user}}` / `{{original}}` 是聊天时的宏，写卡请求里没有值，
//      原样发过去模型会以为自己在扮演（而不是在写卡）。要换成中性说法，或直接删。
//   2. 破甲/文风类预设动辄几千字，全塞进去会把 token 预算吃光，JSON 直接被挤掉。
//      所以有长度上限，超了从末尾裁，优先保留前面（授权、口吻通常在最前）。

/// 内置人格层的两个 id（存进设置里的字符串，不是预设 id，所以带前缀）。
const builtinCardPersonaId = 'builtin:card';
const builtinBookPersonaId = 'builtin:book';

/// 拼出来的人格层最多这么多字；超了从末尾裁。
const personaTextLimit = 3000;

/// 内置的「写卡」人格：授权说得清楚，但不逼着写——卡本身不是成人向就不硬加。
const _builtinCardZh = '''
你是一位角色设定作者，专门把一句灵感写成能直接用的酒馆角色卡。
1. 内容尺度：这张卡允许限制级——性、身体、欲望都可以直白写，露骨用词不用回避，别用隐喻把话说软。但如果这张卡本身不是成人向，就不要硬加性内容，顺着它自己的方向写。
2. 每一格都要具体到能看见：外貌写体型、皮肤、气味、穿衣；性格写到能预测这个人在什么场合会怎么反应；场景写到温度、声音、光线。
3. 台词要有辨识度：口头禅、句子长短、语气词。示例对话要真像这个人在说话，不是把旁白改成对话。
4. 允许写复杂的欲望和边缘关系，但角色必须自洽：欲望有来处，不能只剩器官。
5. 你只写这张卡：不替玩家说话，不写正文剧情，不解释你在做什么，除了要求的 JSON 不输出别的东西。''';

const _builtinCardEn = '''
You write character cards for a role-play app. Take one line of inspiration and turn it into a card someone can use as-is.
1. Rating: this card may be explicit — sex, bodies and desire can be written plainly, with the words readers actually use. But if the card itself is not adult, do not force it; follow where it points.
2. Every field must be concrete: bodies you can see (build, skin, smell, clothes), a personality you can predict a reaction from, a scene with temperature, sound and light.
3. Dialogue must be recognisable: catchphrases, sentence length, particles. Example dialogue has to sound like that person, not narration turned into speech.
4. Complex desire and messy relationships are fine, but the character has to hold together: desire has a history, not just organs.
5. Write the card only: never speak for the player, no story prose, no explanation — nothing but the requested JSON.''';

/// 内置的「写世界书」人格：按类型分写法，允许成人向，但每条要能触发、要自足。
const _builtinBookZh = '''
你是一位设定集作者，专门把设定写成「聊到就会触发」的世界书条目。
1. 内容尺度：允许直白写性、身体、体液与欲望，用读者会用的词，不要用隐喻绕开。但这个世界观本身不是成人向时，不要硬塞。
2. 每条自足：不看别的条目也能读懂；写清「是什么 / 谁在用 / 怎么表现出来」，不写空话。
3. 按类型写：文风类写「怎么写」（视角、句子、节奏、感官、衣物与肉体一起描），不写「发生了什么」；破甲类写成命令（不许干什么 + 该干什么），短而硬；描写词条写具体情境和身体反应，不写概括。
4. 常驻只留给每回合都必须在场的东西；其余靠关键词触发，关键词要覆盖别称、俗称、玩家真会打出来的词。
5. 你只写这本世界书的条目：不写正文，不扮演任何角色，不解释。''';

const _builtinBookEn = '''
You write world book entries — the lore a chat pulls in when it touches on something.
1. Rating: sex, bodies, fluids and desire may be written plainly, in the words readers use, with no metaphor to soften it. But if this world is not adult, do not force it in.
2. Every entry stands alone: readable without the others, saying what it is, who uses it, and how it shows up.
3. Write by kind: style entries say how to write (POV, sentences, rhythm, senses, clothes and flesh together) rather than what happens; guardrail entries are short orders (what never to do, what to do instead); lexicon entries describe concrete scenes and body reactions, never summaries.
4. Constant is only for what must be present every turn; everything else triggers on keys that cover nicknames, slang and the words a player would actually type.
5. Write the entries only: no prose, no role-play, no explanation.''';

/// 内置人格：按 id 和语言给一段可用的文本；不是内置 id 就 null。
String? builtinPersona(String id, bool english) => switch (id) {
  builtinCardPersonaId => clipPersona(english ? _builtinCardEn : _builtinCardZh),
  builtinBookPersonaId => clipPersona(english ? _builtinBookEn : _builtinBookZh),
  _ => null,
};

/// 这串 id 是不是内置人格。
bool isBuiltinPersona(String? id) =>
    id == builtinCardPersonaId || id == builtinBookPersonaId;

/// 被丢掉的一条，以及为什么丢（界面上要明示，不许静默）。
class PersonaDropped {
  const PersonaDropped(this.label, this.reason);

  /// 条目的 identifier，没有就用它的名字。
  final String label;

  /// 人话理由，直接给用户看。
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is PersonaDropped && other.label == label && other.reason == reason;

  @override
  int get hashCode => Object.hash(label, reason);

  @override
  String toString() => '$label（$reason）';
}

/// 一层拼好的「人格」：能用的那段文本，和这次被筛掉的条目。
class PersonaLayer {
  const PersonaLayer({this.text, this.dropped = const <PersonaDropped>[]});

  /// 拼好、净化过、裁过长度的人格文本；一条都没剩就是 null。
  final String? text;
  final List<PersonaDropped> dropped;

  bool get isEmpty => (text ?? '').trim().isEmpty;

  static const empty = PersonaLayer();
}

/// 预设里能当人格层的那几条，按预设的顺序拼成一段；没有就 null。
String? presetPersonaText(Map<String, Object?> raw) => presetPersona(raw).text;

/// 从预设里筛出人格层：**按内容筛，不按槽位名筛**。
///
/// 聊天预设的 `main` 通常是「以角色身份回下一句、别写玩家的台词」——这跟写卡/写书
/// 是正面对撞的，留着只会让模型开演。但也不能看见 `main` 就一刀切：有的预设把
/// 「你是一位角色卡设计师」这种写作身份也写在 main 里，那种必须留。
///
/// 判据：命中聊天运行时特征、且没有任何写作身份特征 → 丢；其余全留。
/// 丢掉的进 [PersonaLayer.dropped]，由界面明示。
PersonaLayer presetPersona(Map<String, Object?> raw) {
  final parts = <String>[];
  final dropped = <PersonaDropped>[];
  for (final prompt in _orderedPrompts(raw)) {
    if (prompt['marker'] == true) continue;
    final role = prompt['role'];
    if (role != 'system' && prompt['system_prompt'] != true) continue;
    final content = prompt['content'];
    if (content is! String) continue;
    final text = content.trim();
    if (text.isEmpty || parts.contains(text)) continue;
    final label = _label(prompt);
    if (isChatRuntimePrompt(text)) {
      dropped.add(PersonaDropped(label, '聊天指令，和写作任务冲突'));
      continue;
    }
    parts.add(text);
  }
  if (parts.isEmpty && dropped.isEmpty) {
    // 老预设：三条单独字段。
    for (final key in const ['main_prompt', 'nsfw_prompt', 'jailbreak_prompt']) {
      final value = raw[key];
      if (value is! String) continue;
      final text = value.trim();
      if (text.isEmpty || parts.contains(text)) continue;
      if (isChatRuntimePrompt(text)) {
        dropped.add(PersonaDropped(key, '聊天指令，和写作任务冲突'));
        continue;
      }
      parts.add(text);
    }
  }
  return PersonaLayer(
    text: parts.isEmpty
        ? null
        : clipPersona(sanitizePersona(parts.join('\n\n'))),
    dropped: List.unmodifiable(dropped),
  );
}

String _label(Map<String, Object?> prompt) {
  for (final key in const ['identifier', 'name']) {
    final value = prompt[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return '未命名';
}

/// 聊天运行时指令的特征（命中「回下一句 / 保持角色 / 别替玩家说话」这类）。
final _chatRuntime = <RegExp>[
  RegExp(r'\bnext (reply|message|response)\b', caseSensitive: false),
  RegExp(r'\b(stay|remain) in character\b', caseSensitive: false),
  RegExp(r'\brespond as\b|\breply as\b|\bcontinue the (chat|conversation)\b',
      caseSensitive: false),
  RegExp(r'\bnever (write|speak)\b[^.\n]{0,30}\b(lines?|dialogue)\b',
      caseSensitive: false),
  RegExp(r'替.{0,4}(角色|用户|玩家).{0,6}(回话|说话|发言)'),
  RegExp(r'以.{0,4}角色.{0,4}身份'),
  RegExp(r'不要.{0,6}(玩家|用户).{0,6}(台词|发言|说话)'),
  RegExp(r'(继续|接着).{0,4}(对话|回复|聊天)'),
  RegExp(r'下一句|下一段回复'),
];

/// 写作身份的特征：只要有这些，就说明这条是写作向的，哪怕顺带提了角色也不行。
final _writingHints = <RegExp>[
  RegExp(r'写卡|角色卡|世界书|条目|人设|设定集|卡片'),
  RegExp(
    r'\b(card|world ?book|character (card|sheet)|writer|author|editor)\b',
    caseSensitive: false,
  ),
];

/// 这条内容是不是「聊天运行时指令」。
///
/// 命中聊天特征、且没有写作身份特征 → true。带写作身份的一律 false：
/// 「你是一位角色卡设计师，别替玩家说话」要留，那是写作纪律，不是出戏判断。
bool isChatRuntimePrompt(String content) {
  final text = content.trim();
  if (text.isEmpty) return false;
  if (_writingHints.any((pattern) => pattern.hasMatch(text))) return false;
  return _chatRuntime.any((pattern) => pattern.hasMatch(text));
}

/// 把聊天用的宏换成写卡/写书时讲得通的说法。
///
/// `{{char}}` → 「角色」、`{{user}}` → 「玩家」，`{{original}}` / `{{persona}}` 删掉；
/// 其余不认识的 `{{...}}` 一并删——留一个没值的占位符，模型就会原样抄进卡里，
/// 或者干脆开始扮演（真机踩过）。
String sanitizePersona(String text) {
  var out = text;
  out = out.replaceAll(RegExp(r'\{\{\s*char\s*\}\}', caseSensitive: false), '角色');
  out = out.replaceAll(RegExp(r'\{\{\s*user\s*\}\}', caseSensitive: false), '玩家');
  out = out.replaceAll(
    RegExp(r'\{\{\s*(original|persona)\s*\}\}', caseSensitive: false),
    '',
  );
  out = out.replaceAll(RegExp(r'\{\{[\s\S]{0,80}?\}\}'), '');
  out = out.replaceAll(RegExp(r'\{%[\s\S]{0,80}?%\}'), '');
  // 删完可能留下连续空行/行尾空格。
  out = out
      .split('\n')
      .map((line) => line.trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return out.trim();
}

/// 太长就从末尾裁：授权、口吻通常在最前面，先保它们。
String clipPersona(String text) {
  if (text.length <= personaTextLimit) return text;
  var cut = text.substring(0, personaTextLimit);
  final lastBreak = cut.lastIndexOf('\n');
  if (lastBreak > personaTextLimit ~/ 2) cut = cut.substring(0, lastBreak);
  return '${cut.trimRight()}\n…（人格层过长，后面截掉了）';
}

/// 预设的提示顺序：主聊天那组（character_id 100001）优先，其次第一组，
/// 都没有就按 prompts 数组自己的顺序。
List<Map<String, Object?>> _orderedPrompts(Map<String, Object?> raw) {
  final listed = <Map<String, Object?>>[];
  final prompts = raw['prompts'];
  if (prompts is List) {
    for (final item in prompts) {
      if (item is Map) listed.add(item.cast<String, Object?>());
    }
  }
  if (listed.isEmpty) return listed;
  final byIdentifier = <String, Map<String, Object?>>{};
  for (final prompt in listed) {
    final identifier = prompt['identifier'];
    if (identifier is String && byIdentifier[identifier] == null) {
      byIdentifier[identifier] = prompt;
    }
  }
  final ordered = <Map<String, Object?>>[];
  for (final identifier in _orderIdentifiers(raw)) {
    final prompt = byIdentifier[identifier];
    if (prompt != null && !ordered.contains(prompt)) ordered.add(prompt);
  }
  // 顺序表里没列到的（新加的、手加的）接在后面，别丢。
  for (final prompt in listed) {
    if (!ordered.contains(prompt)) ordered.add(prompt);
  }
  return ordered;
}

List<String> _orderIdentifiers(Map<String, Object?> raw) {
  final orders = raw['prompt_order'];
  if (orders is! List) return const [];
  List<Object?>? picked;
  for (final group in orders) {
    if (group is! Map) continue;
    final id = group['character_id'];
    if (id == 100001 || id == '100001') {
      picked = group['order'] as List<Object?>?;
      break;
    }
  }
  if (picked == null) {
    for (final group in orders) {
      if (group is! Map) continue;
      picked = group['order'] as List<Object?>?;
      break;
    }
  }
  if (picked == null) return const [];
  return [
    for (final item in picked)
      if (item is Map && item['enabled'] != false && item['identifier'] is String)
        item['identifier']! as String,
  ];
}

/// 把人格垫成第一条 system；空的就是原样。
List<Map<String, Object?>> withPersona(
  List<Map<String, Object?>> messages,
  String? persona,
) {
  final text = (persona ?? '').trim();
  if (text.isEmpty) return messages;
  return [
    {'role': 'system', 'content': text},
    ...messages,
  ];
}
