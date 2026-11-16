// 专业创作的 AI：一个字段一个字段地写，不是一次性把整张卡吐出来。
//
// 规格 §1.5 的 studioAsk，落在这里：
//   · 提示里带上"这个模块已经写了什么"和"锁定了什么"——锁定字段只能顺着写，不许改；
//   · 模型只回 JSON（`{"fields":{...}}` 或 `{"issues":[...]}`），围栏/散文都能救回来；
//   · 返回的键先过滤：不在本模块的丢掉，锁定的丢掉，空的丢掉——然后再交给界面预览。
// 网络那一段不在这里：调用方用 tavernModelClientProvider 走同一套传输。
//
// 纯函数，能在宿主上单测；只有 [studioAiMessages] / [studioAiParse] 这两个入口。

import 'dart:convert';

import 'state_templates.dart';
import 'tavern_studio_draft.dart';
import 'tavern_studio_schema.dart';

/// 五种字段动作，加三个整块动作：整模块生成、把这个模块变成世界书条目、三段试演。
enum StudioAiAction {
  fill,
  expand,
  trim,
  rewrite,
  check,
  wholeModule,
  book,
  simulate,
  state,
}

/// 检查出来的一个问题：指到具体字段，给出改法。
class StudioAiIssue {
  const StudioAiIssue({
    required this.field,
    required this.issue,
    this.suggest = '',
  });
  final String field;
  final String issue;
  final String suggest;
}

/// 模型这一次给了什么：要写的字段、查到的问题、要新建的世界书条目，或者试演的台词。
class StudioAiProposal {
  const StudioAiProposal({
    this.fields = const {},
    this.issues = const [],
    this.entries = const [],
    this.scenes = const [],
    this.stateTemplate,
  });
  final Map<String, String> fields;
  final List<StudioAiIssue> issues;
  final List<StudioBookEntry> entries;
  final List<StudioScene> scenes;

  /// AI ?????????????? draft.state?
  final StateTemplate? stateTemplate;

  bool get isEmpty =>
      fields.isEmpty &&
      issues.isEmpty &&
      entries.isEmpty &&
      scenes.isEmpty &&
      stateTemplate == null;
}

/// 一段试演：什么处境，角色说了什么。
class StudioScene {
  const StudioScene({required this.title, required this.reply});
  final String title;
  final String reply;
}

/// 每个动作要模型做什么，写清楚了才不会"扩写"成"重写"。
String _taskZh(
  StudioAiAction action,
  String label,
  int budget,
  String instruction,
) => switch (action) {
  StudioAiAction.fill => '补全「$label」，${budget} 字以内。',
  StudioAiAction.expand => '把「$label」写长一些，保留已有设定，不要推翻，${budget} 字以内。',
  StudioAiAction.trim => '精简「$label」，压到七成以内，只留能进卡的内容。',
  StudioAiAction.rewrite =>
    '重写「$label」${instruction.trim().isEmpty ? '' : '，要求：${instruction.trim()}'}，${budget} 字以内。',
  StudioAiAction.check => '检查这个模块，找出互相矛盾或空泛的地方。不要改文本。',
  StudioAiAction.wholeModule => '把这个模块里还没写、也没锁定的字段一次写完，每个字段 ${budget} 字以内。',
  StudioAiAction.book =>
    '把这个模块里的信息拆成 3 到 6 条世界书条目。每条要有：标题、2 到 6 个关键词（对话里提到就会触发）、'
        '80 到 200 字的正文。只有真正的设定才写成常驻（每回合都要注入）；没把握就别常驻。',
  StudioAiAction.simulate =>
    '用这张卡现在的设定，写三段不同处境下的台词：被搭话、被冒犯、独处。'
        '每段 3 到 6 句，第一人称，带动作和神态。只写角色会说的话和做的事，不要解释。',
  StudioAiAction.state =>
    '按这个角色设计 3 到 6 个状态项，用来在对话里跟踪他和 {{user}} 的关系与处境。'
        '每项要有：key（英文小写，字母开头，只用字母数字下划线）、title（中文名）、'
        'type（number / text / boolean / choice / list 之一）、initial（初始值）。'
        'number 给 min 和 max；choice 给 options（字符串数组）。'
        '挑真正会变、且值得给对方看到的，不要设计一大堆。',
};

String _taskEn(
  StudioAiAction action,
  String label,
  int budget,
  String instruction,
) => switch (action) {
  StudioAiAction.fill => 'Fill in "$label", up to $budget characters.',
  StudioAiAction.expand =>
    'Lengthen "$label", keep what is there, up to $budget characters.',
  StudioAiAction.trim =>
    'Tighten "$label" to about 70%, keeping only what belongs in a card.',
  StudioAiAction.rewrite =>
    'Rewrite "$label"${instruction.trim().isEmpty ? '' : ', as asked: ${instruction.trim()}'}, up to $budget characters.',
  StudioAiAction.check => 'Check this module for contradictions and vague lines. Do not rewrite anything.',
  StudioAiAction.wholeModule =>
    'Write every empty, unlocked field in this module at once, up to $budget characters each.',
  StudioAiAction.book =>
    'Split this module into 3 to 6 world book entries. Each one needs a title, 2 to 6 keys '
        '(a chat mentioning them triggers it) and 80 to 200 characters of content. Mark an entry '
        'constant only if it truly belongs in every prompt.',
  StudioAiAction.simulate =>
    'Using what this card has now, write three short scenes: being spoken to, being insulted, '
        'and being alone. Three to six lines each, first person, with action and expression. '
        'Only what the character says and does; no explanation.',
  StudioAiAction.state =>
    'Design three to six state fields for this character, to track the relationship and '
        'situation during a chat. Each one needs: key (lowercase English, letters first, '
        'letters/digits/underscore only), title, type (number, text, boolean, choice or list) '
        'and initial. Give min and max for numbers, options for choices. '
        'Only what actually changes and is worth showing to the player.',
};

/// 输出说明：字段动作要 fields（键就是上面那些英文键），检查要 issues，
/// 生成条目要 entries。
Map<String, Object?> _schema(StudioAiAction action, List<String> targets) =>
    switch (action) {
      StudioAiAction.check => {
        'issues': [
          {
            'field': 'this module\'s field key',
            'issue': 'what is wrong',
            'suggest': 'how to fix it',
          },
        ],
      },
      StudioAiAction.book => {
        'entries': [
          {
            'title': 'short title',
            'keys': ['2 to 6 keys'],
            'content': '80 to 200 characters',
            'constant': false,
          },
        ],
      },
      StudioAiAction.simulate => {
        'scenes': [
          {'title': 'being spoken to', 'reply': 'what they say and do'},
        ],
      },
      _ => {
        'fields': {
          for (final key in targets.isEmpty ? ['field key'] : targets)
            key: 'the text',
        },
      },
    };

/// 一个模块里已经写了的东西，给模型当上下文。
String _written(
  StudioDraft draft,
  String module,
  String Function(String key) label,
  bool english,
) {
  final spec = studioModule(module);
  if (spec == null) return '';
  final lines = <String>[];
  for (final field in spec.fields) {
    final value = draft.peek(module, field.key);
    if (value == null || value.isEmpty) continue;
    final text = value.items.isEmpty ? value.text : value.items.join(' / ');
    final locked = value.locked ? (english ? '[locked] ' : '【锁定】') : '';
    lines.add('- $locked${label(field.key)}：${_short(text, 200)}');
  }
  return lines.join('\n');
}

/// 灵魂档案：动机 / 不可改变 / 内在冲突 / 成长方向。有才写，没有就不占地方。
String _soul(StudioDraft draft, bool english) {
  final parts = <String>[];
  void add(String key, String zh, String en) {
    final text = draft.text('soul', key).trim();
    if (text.isNotEmpty)
      parts.add('- ${english ? en : zh}：${_short(text, 120)}');
  }

  add('motive', '核心动机', 'Motive');
  final constants = draft.items('soul', 'constants');
  if (constants.isNotEmpty) {
    parts.add(
      '- ${english ? 'Constants' : '不可改变'}：${constants.take(6).join('、')}',
    );
  }
  add('conflict', '内在冲突', 'Inner conflict');
  add('soulGrowth', '成长方向', 'Growth');
  return parts.join('\n');
}

/// 全局摘要：姓名 / 身份 / 时代 / 地理 / 地点，给模型一个"这个人在哪个世界"。
/// 只用 schema 里真有的字段（`world.era` / `geography` / `society` / `places`）。
String _summary(StudioDraft draft, bool english) {
  final parts = <String>[];
  final name = draft.text('profile', 'name').trim();
  final identity = draft.text('profile', 'identity').trim();
  if (name.isNotEmpty) parts.add('${english ? 'Name' : '姓名'}：$name');
  if (identity.isNotEmpty) parts.add('${english ? 'Role' : '身份'}：$identity');
  for (final (key, zh, en) in const [
    ('era', '时代', 'Era'),
    ('geography', '地理', 'Geography'),
    ('society', '社会制度', 'Society'),
  ]) {
    final text = draft.text('world', key).trim();
    if (text.isNotEmpty) parts.add('${english ? en : zh}：${_short(text, 80)}');
  }
  final places = draft.items('world', 'places');
  if (places.isNotEmpty) {
    parts.add(
      '${english ? 'Places' : '地点'}：${places.take(4).map((p) => _short(p, 20)).join('、')}',
    );
  }
  return parts.join('\n');
}

String _short(String text, int limit) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= limit ? flat : '${flat.substring(0, limit)}…';
}

/// 提示本体。[label] 把字段 key 变成人话（调用方给 l10n 的字段名）。
///
/// 关键一条：**提示里必须出现程序要的那个英文键**（`identity` 而不是只有「角色身份」），
/// 否则真实模型会照着中文名回，解析器只认键名，结果全被丢掉。
List<Map<String, Object?>> studioAiMessages({
  required StudioDraft draft,
  required String module,
  String? field,
  required StudioAiAction action,
  String instruction = '',
  bool english = false,
  required String Function(String key) label,
  int budget = 160,
}) {
  final moduleName = studioModuleLabelOf(module, english);
  final written = _written(draft, module, label, english);
  final spec = studioModule(module);
  // 这次要写的字段：单字段就一个；整模块只列「空着且没锁」的。
  final targets = field != null
      ? [field]
      : [
          for (final f in spec?.fields ?? const <StudioFieldSpec>[])
            if (draft.peek(module, f.key)?.isEmpty ?? true)
              if (draft.peek(module, f.key)?.locked != true) f.key,
        ];
  final system = english
      ? 'You help write one character card. Answer with one JSON object only — no prose, no markdown fence.\n'
            'The object is keyed by the exact field keys given below; never translate a key.\n'
            'Never rewrite a field marked [locked]: it is a constraint, not a target.\n'
            'Use {{user}} for the player and {{char}} for the character. Keep the language of the card.'
      : '你在帮用户写一张酒馆角色卡。只输出一个 JSON 对象，不要解释，不要 markdown 代码块。\n'
            '对象的键必须用下面给的英文键名，不要把键名翻译成中文。\n'
            '标了【锁定】的字段不许改，它是约束，不是目标。\n'
            '用 {{user}} 指代玩家、{{char}} 指代角色。保持卡片本身的语言。';

  final ask = StringBuffer();
  ask.writeln(english ? 'Module: $moduleName' : '模块：$moduleName');
  // 「我想要的角色」：进不了卡，但每一格都要照它写。制卡页那句创意、市场里抄来的
  // 一段设定都放在这里（`StudioDraft.idea`，随草稿存盘）。
  final wish = draft.idea.trim();
  if (wish.isNotEmpty) {
    ask.writeln(english ? '\nThe character I want:' : '\n我想要的角色：');
    ask.writeln(_short(wish, 800));
  }
  final summary = _summary(draft, english);
  if (summary.isNotEmpty) ask.writeln(summary);
  // 灵魂档案是约束：它不进卡，但每一格都得顺着它写。
  final soul = _soul(draft, english);
  if (soul.isNotEmpty) {
    ask.writeln(english ? '\nSoul (never change these):' : '\n灵魂（不许改，一切照它写）：');
    ask.writeln(soul);
  }
  if (written.isNotEmpty) {
    ask.writeln(english ? '\nAlready written:' : '\n已经写了：');
    ask.writeln(written);
  }
  ask.writeln('');
  if (targets.isNotEmpty) {
    ask.writeln(
      english ? 'Fields to write (use these keys):' : '要写的字段（键就用这些）：',
    );
    for (final key in targets) {
      ask.writeln('- $key（${label(key)}）');
    }
    ask.writeln('');
  }
  ask.writeln(
    _taskZhOrEn(
      action,
      field == null ? '' : label(field!),
      budget,
      instruction,
      english,
    ),
  );
  ask.writeln('');
  ask.writeln(
    english
        ? 'Reply as: ${jsonEncode(_schema(action, targets))}'
        : '按这个形状回答：${jsonEncode(_schema(action, targets))}',
  );
  return [
    {'role': 'system', 'content': system},
    {'role': 'user', 'content': ask.toString()},
  ];
}

String _taskZhOrEn(
  StudioAiAction action,
  String label,
  int budget,
  String instruction,
  bool english,
) => english
    ? _taskEn(action, label, budget, instruction)
    : _taskZh(action, label, budget, instruction);

/// 模块名（生成文件里那个依赖 l10n 的函数在这里用不上，给个中英对照兜底）。
String studioModuleLabelOf(String module, bool english) => switch (module) {
  'profile' => english ? 'Profile' : '人物档案',
  'mind' => english ? 'Depth' : '深度人格',
  'bond' => english ? 'Bonds' : '玩家关系',
  'history' => english ? 'History' : '人生经历',
  'world' => english ? 'World' : '世界与背景',
  'voice' => english ? 'Voice' : '对话与文风',
  'scene' => english ? 'Scenes' : '情节与场景',
  'rules' => english ? 'Rules' : '行为规则',
  'soul' => english ? 'Soul' : '灵魂档案',
  _ => module,
};

/// 请求体：不加历史、温度略高（写卡要点想象力），上限按字段预算留余地。
Map<String, Object?> studioAiBody({
  required StudioDraft draft,
  required String module,
  String? field,
  required StudioAiAction action,
  String instruction = '',
  bool english = false,
  required String Function(String key) label,
  int budget = 160,
}) => {
  'messages': studioAiMessages(
    draft: draft,
    module: module,
    field: field,
    action: action,
    instruction: instruction,
    english: english,
    label: label,
    budget: budget,
  ),
  'temperature': 0.9,
  'max_tokens': switch (action) {
    StudioAiAction.wholeModule => 2000,
    StudioAiAction.book => 1600,
    StudioAiAction.simulate => 1200,
    StudioAiAction.state => 900,
    _ => 700,
  },
};

/// 把模型的回答变成"可以采用的改动"。
///
/// 过滤规则（这里是护栏，别放松）：
///   · 只收本模块的字段；
///   · 字段动作只收目标字段，整模块只收还没锁的；
///   · 锁定字段一律丢弃——哪怕模型写了；
///   · 空白内容丢弃。
StudioAiProposal studioAiParse(
  String reply, {
  required StudioDraft draft,
  required String module,
  String? field,
  required StudioAiAction action,
  String Function(String key)? label,
}) {
  final json = _firstObject(reply);
  if (json == null) return const StudioAiProposal();
  final spec = studioModule(module);
  final allowed = {
    for (final f in spec?.fields ?? const <StudioFieldSpec>[]) f.key,
  };

  if (action == StudioAiAction.state) {
    final raw = json['fields'];
    final fields = <StateField>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final key = item['key'] is String
            ? (item['key']! as String).trim()
            : '';
        if (key.isEmpty) continue;
        final type = switch (item['type']) {
          'number' => StateFieldType.number,
          'boolean' => StateFieldType.boolean,
          'choice' => StateFieldType.choice,
          'list' => StateFieldType.list,
          _ => StateFieldType.text,
        };
        fields.add(
          StateField(
            key: key,
            title:
                item['title'] is String &&
                    (item['title']! as String).trim().isNotEmpty
                ? (item['title']! as String).trim()
                : key,
            type: type,
            initial: item['initial'],
            min: item['min'] is num ? item['min']! as num : null,
            max: item['max'] is num ? item['max']! as num : null,
            options: [
              for (final option
                  in (item['options'] is List
                      ? item['options']! as List
                      : const []))
                if (option is String && option.trim().isNotEmpty) option.trim(),
            ],
          ),
        );
      }
    }
    if (fields.isEmpty) return const StudioAiProposal();
    return StudioAiProposal(
      stateTemplate: StateTemplate(
        id: newStateTemplateId(),
        name: 'AI ??',
        fields: fields,
      ),
    );
  }

  if (action == StudioAiAction.simulate) {
    final raw = json['scenes'];
    return StudioAiProposal(
      scenes: [
        if (raw is List)
          for (final item in raw)
            if (item is Map)
              StudioScene(
                title: item['title'] is String ? item['title']! as String : '',
                reply: item['reply'] is String ? item['reply']! as String : '',
              ),
      ].where((scene) => scene.reply.trim().isNotEmpty).toList(),
    );
  }

  if (action == StudioAiAction.book) {
    final raw = json['entries'];
    return StudioAiProposal(
      entries: [
        if (raw is List)
          for (final item in raw)
            if (item is Map)
              StudioBookEntry(
                title: item['title'] is String ? item['title']! as String : '',
                content: item['content'] is String
                    ? item['content']! as String
                    : '',
                keys: [
                  if (item['keys'] is List)
                    for (final key in item['keys']! as List)
                      if (key is String && key.trim().isNotEmpty) key.trim(),
                ],
                constant: item['constant'] == true,
              ),
      ].where((entry) => !entry.isEmpty).toList(),
    );
  }

  if (action == StudioAiAction.check) {
    final raw = json['issues'];
    return StudioAiProposal(
      issues: [
        if (raw is List)
          for (final item in raw)
            if (item is Map)
              StudioAiIssue(
                field: item['field'] is String ? item['field']! as String : '',
                issue: item['issue'] is String ? item['issue']! as String : '',
                suggest: item['suggest'] is String
                    ? item['suggest']! as String
                    : '',
              ),
      ].where((issue) => issue.issue.trim().isNotEmpty).toList(),
    );
  }

  final raw = json['fields'];
  if (raw is! Map) return const StudioAiProposal();
  final fields = <String, String>{};
  for (final entry in raw.entries) {
    final rawKey = entry.key;
    if (rawKey is! String) continue;
    // 键名对不上就试一次中文名：真实模型经常照提示里的中文回。
    final key = allowed.contains(rawKey)
        ? rawKey
        : _keyForLabel(rawKey, allowed, label);
    if (key == null) continue;
    if (action != StudioAiAction.wholeModule && key != field) continue;
    final value = entry.value;
    final text = value is String
        ? value.trim()
        : value is List
        ? [
            for (final item in value)
              if (item is String && item.trim().isNotEmpty) item.trim(),
          ].join('\n')
        : '';
    if (text.isEmpty) continue;
    final current = draft.peek(module, key);
    if (current?.locked == true) continue;
    // 整模块只填空的：已经有内容（且没锁）的字段也不许被覆盖。
    if (action == StudioAiAction.wholeModule &&
        current != null &&
        !current.isEmpty) {
      continue;
    }
    fields[key] = text;
  }
  return StudioAiProposal(fields: fields);
}

/// 把模型回的中文名（或别的写法）对回字段键；对不上返回 null。
String? _keyForLabel(
  String rawKey,
  Set<String> allowed,
  String Function(String key)? label,
) {
  if (label == null) return null;
  final wanted = rawKey.trim();
  for (final key in allowed) {
    if (label(key).trim() == wanted) return key;
  }
  return null;
}

/// 模型爱把 JSON 包在 ```json 里、前面写句"好的"，或者干脆前后带话。
/// 这些都救回来；救不回来返回 null（调用方把原文摊出来，不猜）。
Map<String, Object?>? _firstObject(String reply) {
  var text = reply.trim();
  if (text.isEmpty) return null;
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
  if (fence != null) text = fence.group(1)!.trim();
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final decoded = jsonDecode(text.substring(start, end + 1));
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// 采用：把提议写进草稿（带来源），锁定的再过一遍闸。
///
/// [onlyEmpty] 给整模块用：已经有内容的字段不写——就算模型多回了也不覆盖。
void studioAiApply(
  StudioDraft draft,
  String module,
  StudioAiProposal proposal, {
  bool onlyEmpty = false,
}) {
  for (final entry in proposal.fields.entries) {
    final current = draft.peek(module, entry.key);
    if (current?.locked == true) continue;
    if (onlyEmpty && current != null && !current.isEmpty) continue;
    final spec = studioModule(module)?.field(entry.key);
    if (spec == null) continue;
    if (spec.isList) {
      draft.setItems(
        module,
        entry.key,
        entry.value
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList(),
        source: StudioSource.ai,
      );
    } else {
      draft.setText(module, entry.key, entry.value, source: StudioSource.ai);
    }
  }
  // 条目接在书里，不覆盖同名的——生成几次就是几批，用户自己删。
  for (final entry in proposal.entries) {
    draft.addBookEntry(entry);
  }
}
