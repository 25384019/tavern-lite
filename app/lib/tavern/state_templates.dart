// 状态模板：一套「状态项」的定义，可以存下来反复用到不同的卡上。
//
// 形状直接对齐卡片里的 `extensions.dshgo.state`（schema + init），所以
// 「应用模板」= 把模板折成那个形状写进卡，舞台上立刻能显示和使用；
// 反过来也能从一张已有的卡里把状态读出来存成模板。
//
// 纯数据 + 纯转换，能单测；存哪儿由 [StateTemplateStore] 管。

import 'dart:convert';
import 'dart:io';

/// 一个状态项是什么类型。数字 / 文本 / 布尔 / 枚举 / 列表。
enum StateFieldType { number, text, boolean, choice, list }

StateFieldType stateFieldTypeOf(Object? value) => switch (value) {
  bool _ => StateFieldType.boolean,
  num _ => StateFieldType.number,
  List _ => StateFieldType.list,
  _ => StateFieldType.text,
};

class StateField {
  StateField({
    required this.key,
    required this.title,
    required this.type,
    this.initial,
    this.min,
    this.max,
    List<String>? options,
    this.hidden = false,
  }) : options = List.of(options ?? const []);

  /// 内部键：卡片里的 JSON 用它，改中文名不影响它。
  final String key;
  final String title;
  final StateFieldType type;

  /// 新开一段对话时的初始值。
  final Object? initial;
  final num? min;
  final num? max;

  /// 枚举的选项。
  final List<String> options;

  /// 藏起来：不显示具体值（剧透类数值）。
  final bool hidden;

  StateField copy() => StateField(
    key: key,
    title: title,
    type: type,
    initial: initial,
    min: min,
    max: max,
    options: options,
    hidden: hidden,
  );

  /// JSON Schema 的那一小块。
  Map<String, Object?> toSchema() => {
    'title': title,
    if (hidden) 'x-dsh-hidden': true,
    ...switch (type) {
      StateFieldType.number => {
        'type': 'integer',
        if (min != null) 'minimum': min,
        if (max != null) 'maximum': max,
        'default': initial ?? min ?? 0,
      },
      StateFieldType.boolean => {
        'type': 'boolean',
        'default': initial ?? false,
      },
      StateFieldType.choice => {
        'type': 'string',
        'enum': options.isEmpty ? ['是', '否'] : options,
        'default': initial ?? (options.isEmpty ? '是' : options.first),
      },
      StateFieldType.list => {
        'type': 'array',
        'items': {'type': 'string'},
        'default': initial ?? const <String>[],
      },
      StateFieldType.text => {'type': 'string', 'default': initial ?? ''},
    },
  };

  /// JSON 里的初始值：跟类型对齐，非法就退回默认。
  Object? toInitial() => switch (type) {
    StateFieldType.number => switch (initial) {
      final num n => n,
      final String s => num.tryParse(s) ?? min ?? 0,
      _ => min ?? 0,
    },
    StateFieldType.boolean => initial is bool ? initial : false,
    StateFieldType.choice => switch (initial) {
      final String s when options.isEmpty || options.contains(s) => s,
      _ => options.isEmpty ? '' : options.first,
    },
    StateFieldType.list => stateListInitial(initial),
    StateFieldType.text => initial is String ? initial : '',
  };

  Map<String, Object?> toJson() => {
    'key': key,
    'title': title,
    'type': type.name,
    if (initial != null) 'initial': initial,
    if (min != null) 'min': min,
    if (max != null) 'max': max,
    if (options.isNotEmpty) 'options': options,
    if (hidden) 'hidden': true,
  };

  factory StateField.fromJson(Map<String, Object?> json) => StateField(
    key: json['key'] is String ? json['key']! as String : '',
    title: json['title'] is String ? json['title']! as String : '',
    type: StateFieldType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => StateFieldType.text,
    ),
    initial: json['initial'],
    min: json['min'] is num ? json['min']! as num : null,
    max: json['max'] is num ? json['max']! as num : null,
    options: [
      for (final option
          in (json['options'] is List ? json['options']! as List : const []))
        if (option is String && option.trim().isNotEmpty) option.trim(),
    ],
    hidden: json['hidden'] == true,
  );

  /// 从卡片 schema 的一块读回来（导入老卡用）。
  factory StateField.fromSchema(
    String key,
    Map<String, Object?> node,
    Object? initial,
  ) {
    final enumOptions = [
      for (final option
          in (node['enum'] is List ? node['enum']! as List : const []))
        if (option is String) option,
    ];
    final type = switch (node['type']) {
      'integer' || 'number' => StateFieldType.number,
      'boolean' => StateFieldType.boolean,
      'array' => StateFieldType.list,
      _ => enumOptions.isNotEmpty ? StateFieldType.choice : StateFieldType.text,
    };
    return StateField(
      key: key,
      title:
          node['title'] is String &&
              (node['title']! as String).trim().isNotEmpty
          ? (node['title']! as String).trim()
          : key,
      type: type,
      initial: initial,
      min: node['minimum'] is num ? node['minimum']! as num : null,
      max: node['maximum'] is num ? node['maximum']! as num : null,
      options: enumOptions,
      hidden: node['x-dsh-hidden'] == true,
    );
  }
}

class StateTemplate {
  StateTemplate({
    required this.id,
    required this.name,
    List<StateField>? fields,
  }) : fields = List.of(fields ?? const []);

  final String id;
  final String name;

  /// 顺序就是舞台上的显示顺序。
  final List<StateField> fields;

  StateTemplate copy() => StateTemplate(
    id: id,
    name: name,
    fields: fields.map((f) => f.copy()).toList(),
  );

  /// 折成卡片里的 `extensions.dshgo.state`。
  Map<String, Object?> toState() => {
    'schema': {
      'type': 'object',
      'properties': {for (final field in fields) field.key: field.toSchema()},
    },
    'init': {for (final field in fields) field.key: field.toInitial()},
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'fields': [for (final field in fields) field.toJson()],
  };

  factory StateTemplate.fromJson(Map<String, Object?> json) => StateTemplate(
    id: json['id'] is String ? json['id']! as String : '',
    name: json['name'] is String ? json['name']! as String : '',
    fields: [
      for (final field
          in (json['fields'] is List ? json['fields']! as List : const []))
        if (field is Map) StateField.fromJson(field.cast<String, Object?>()),
    ],
  );

  /// 从一张卡的 `extensions.dshgo.state` 读成模板（老卡兼容）。
  static StateTemplate? fromState(
    Map<String, Object?>? state, {
    required String id,
    required String name,
  }) {
    if (state == null) return null;
    final schema = state['schema'];
    final properties = schema is Map ? schema['properties'] : null;
    if (properties is! Map) return null;
    final init = state['init'] is Map ? state['init']! as Map : const {};
    final fields = <StateField>[];
    for (final entry in properties.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      fields.add(
        StateField.fromSchema(
          entry.key as String,
          entry.value as Map<String, Object?>,
          init[entry.key],
        ),
      );
    }
    if (fields.isEmpty) return null;
    return StateTemplate(id: id, name: name, fields: fields);
  }
}

/// 模板的自检：键不能空、不能重、类型和初始值要对得上。
List<String> stateTemplateIssues(StateTemplate template) {
  final issues = <String>[];
  final seen = <String>{};
  for (final field in template.fields) {
    final key = field.key.trim();
    if (key.isEmpty) {
      issues.add('有一项没有内部键');
      continue;
    }
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) {
      issues.add('「$key」只能有字母、数字、下划线，而且不能以数字开头');
    }
    if (!seen.add(key)) issues.add('「$key」重复了');
    if (field.min != null && field.max != null && field.min! > field.max!) {
      issues.add('「${field.title}」的最小值比最大值大');
    }
    if (field.type == StateFieldType.number && field.initial is String) {
      if (num.tryParse(field.initial! as String) == null) {
        issues.add('「${field.title}」的初始值不是数字');
      }
    }
    if (field.type == StateFieldType.choice && field.options.isEmpty) {
      issues.add('「${field.title}」是枚举，但没有选项');
    }
  }
  return issues;
}

/// 列表型初始值：给数组就用数组，给字符串就按标点拆开。
List<String> stateListInitial(Object? value) {
  if (value is List) {
    return [
      for (final item in value)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
  }
  if (value is String) {
    return [
      for (final item in value.split(RegExp(r'[,，、\n]')))
        if (item.trim().isNotEmpty) item.trim(),
    ];
  }
  return const [];
}

/// 新建一个空模板时的 id：够随机就行，不用加密强。
String newStateTemplateId([int? seed]) {
  final base = seed ?? DateTime.now().microsecondsSinceEpoch;
  return 'tpl-${base.toRadixString(36)}';
}

/// 模板列表的存取：一个 JSON 文件，先写临时文件再改名。
class StateTemplateStore {
  StateTemplateStore(this.directory);

  /// 应用支持目录下的一个子目录（测试给临时目录）。
  final Directory directory;

  File get _file =>
      File('${directory.path}${Platform.pathSeparator}state_templates.json');

  Future<List<StateTemplate>> read() async {
    try {
      if (!await _file.exists()) return const [];
      return decodeStateTemplates(await _file.readAsString());
    } on Object {
      // 坏文件当没有，不让模板页打不开。
      return const [];
    }
  }

  Future<void> write(List<StateTemplate> templates) async {
    await directory.create(recursive: true);
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(
      jsonEncode([for (final template in templates) template.toJson()]),
      flush: true,
    );
    await temp.rename(_file.path);
  }
}

/// 纯解析：给测试和读文件共用。
List<StateTemplate> decodeStateTemplates(String text) {
  try {
    final json = jsonDecode(text);
    if (json is! List) return const [];
    return [
      for (final item in json)
        if (item is Map) StateTemplate.fromJson(item.cast<String, Object?>()),
    ];
  } on Object {
    return const [];
  }
}
