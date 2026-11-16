// 创作层：一份草稿，九个模块，每个字段都有锁定和撤销。
//
// 这不是卡片。卡片（description / personality / …）由 [buildStudioCard] 从草稿
// 折算出来，草稿本身存进卡片的 `extensions.dshgo.studio`，导出导入都跟着走。
// 纯数据 + 纯函数，能在宿主上单测；不 import Flutter。
//
// 字段的控件类型不在这里（它属于界面），这里只认两件事：一段文字，或者一串条目。
// 所以 line / block 用 `text`，tags / list 用 `items`，互不干扰。

/// JSON 结构版本。改结构要加这个数字，旧的草稿按旧规则读。
const studioDraftVersion = 1;

/// 一个字段从哪来的：人写的、AI 写的、AI 写完人又改过。
abstract final class StudioSource {
  static const manual = 'manual';
  static const ai = 'ai';
  static const aiEdited = 'ai-edited';
}

/// 撤销栈的深度：够退回十步，再多就不是"撤销"而是"考古"了。
const studioHistoryDepth = 10;

class StudioField {
  StudioField({
    this.text = '',
    List<String>? items,
    this.locked = false,
    this.source = StudioSource.manual,
    List<String>? history,
    this.updatedAt = 0,
  }) : items = List.of(items ?? const []),
       history = List.of(history ?? const []);

  /// line / block 的内容。
  String text;

  /// tags / list 的条目。
  List<String> items;

  /// 锁上以后，任何 AI 动作都只能读它，不能写它。
  bool locked;
  String source;

  /// 最近十次改之前的模样，最新的在最后。只存字符串，靠字段的控件类型还原。
  List<String> history;
  int updatedAt;

  bool get isEmpty =>
      text.trim().isEmpty && items.every((item) => item.trim().isEmpty);

  String get _snapshot => items.isEmpty ? text : items.join('\n');

  void _remember() {
    history.add(_snapshot);
    if (history.length > studioHistoryDepth) {
      history.removeRange(0, history.length - studioHistoryDepth);
    }
  }

  Map<String, Object?> toJson() => {
    'text': text,
    if (items.isNotEmpty) 'items': items,
    'locked': locked,
    'source': source,
    if (history.isNotEmpty) 'history': history,
    'updatedAt': updatedAt,
  };

  factory StudioField.fromJson(Map<String, Object?> json) => StudioField(
    text: json['text'] is String ? json['text']! as String : '',
    items: [
      for (final item
          in (json['items'] is List ? json['items']! as List : const []))
        if (item is String) item,
    ],
    locked: json['locked'] == true,
    source: json['source'] is String
        ? json['source']! as String
        : StudioSource.manual,
    history: [
      for (final item
          in (json['history'] is List ? json['history']! as List : const []))
        if (item is String) item,
    ],
    updatedAt: json['updatedAt'] is int ? json['updatedAt']! as int : 0,
  );

  StudioField copy() => StudioField(
    text: text,
    items: items,
    locked: locked,
    source: source,
    history: history,
    updatedAt: updatedAt,
  );
}

/// 一条世界书条目：草稿里自己攒的，转换器会写进卡片的 character_book。
///
/// 和「字段里写 `关键词|正文`」不是一回事：那些是顺手写的，这里是显式的一条，
/// 带自己的关键词、是否常驻、放哪。AI 生成的就是这种。
class StudioBookEntry {
  StudioBookEntry({
    required this.title,
    required this.content,
    List<String>? keys,
    this.constant = false,
  }) : keys = List.of(keys ?? const []);

  final String title;
  final String content;
  final List<String> keys;

  /// 常驻：每回合都注入。默认关——没关键词的条目本来就不该常驻。
  final bool constant;

  bool get isEmpty => content.trim().isEmpty;

  StudioBookEntry copy() => StudioBookEntry(
    title: title,
    content: content,
    keys: keys,
    constant: constant,
  );

  Map<String, Object?> toJson() => {
    'title': title,
    'content': content,
    if (keys.isNotEmpty) 'keys': keys,
    if (constant) 'constant': true,
  };

  factory StudioBookEntry.fromJson(Map<String, Object?> json) =>
      StudioBookEntry(
        title: json['title'] is String ? json['title']! as String : '',
        content: json['content'] is String ? json['content']! as String : '',
        keys: [
          for (final key
              in (json['keys'] is List ? json['keys']! as List : const []))
            if (key is String && key.trim().isNotEmpty) key.trim(),
        ],
        constant: json['constant'] == true,
      );
}

/// 整份草稿：模块 → 字段 → 值。
class StudioDraft {
  StudioDraft({
    this.version = studioDraftVersion,
    this.updatedAt = 0,
    this.idea = '',
    Map<String, Map<String, StudioField>>? modules,
    List<StudioBookEntry>? book,
    Map<String, Object?>? state,
    Map<String, Object?>? engineering,
  }) : modules = {
         for (final entry
             in (modules ?? const <String, Map<String, StudioField>>{}).entries)
           entry.key: {
             for (final field in entry.value.entries)
               field.key: field.value.copy(),
           },
       },
       book = [
         for (final entry in book ?? const <StudioBookEntry>[]) entry.copy(),
       ],
       state = state == null ? null : Map<String, Object?>.of(state),
       engineering = {...?engineering};

  final int version;
  int updatedAt;
  String idea;
  final Map<String, Map<String, StudioField>> modules;

  /// 自己攒的世界书条目（AI 生成或手写），转换器写进卡片的 character_book。
  final List<StudioBookEntry> book;

  /// 状态定义（模板折出来的 `{schema, init}`，或者 AI 给的一版）。
  /// 有它，转换器就把它写进卡片的 `extensions.dshgo.state`。
  Map<String, Object?>? state;

  /// 工程页的设定：token 预算、格式、绑定。
  final Map<String, Object?> engineering;

  /// 全是空格/空列表时算空。
  bool get isEmpty =>
      idea.trim().isEmpty &&
      modules.values.every(
        (fields) => fields.values.every((field) => field.isEmpty),
      ) &&
      book.every((entry) => entry.isEmpty) &&
      (state?.isEmpty ?? true);

  /// 有多少个字段写了东西（工程页和模块列表用来显示进度）。
  int get filledCount => modules.values.fold(
    0,
    (total, fields) =>
        total + fields.values.where((field) => !field.isEmpty).length,
  );

  StudioField? peek(String module, String field) => modules[module]?[field];

  /// 读一个字段，没有就建一个空的（并挂到草稿上，方便直接改）。
  StudioField ensure(String module, String field) =>
      modules.putIfAbsent(module, () => {}).putIfAbsent(field, StudioField.new);

  String text(String module, String field) => peek(module, field)?.text ?? '';

  List<String> items(String module, String field) =>
      peek(module, field)?.items ?? const [];

  /// 加一条世界书条目。空的（没正文）不收。
  void addBookEntry(StudioBookEntry entry) {
    if (entry.isEmpty) return;
    book.add(entry.copy());
    updatedAt = _now();
  }

  void removeBookEntry(int index) {
    if (index < 0 || index >= book.length) return;
    book.removeAt(index);
    updatedAt = _now();
  }

  /// 写一段文字。值没变就不记撤销栈；原来就是空的也不记——撤销一步回到
  /// 「什么都没写」没有意义，用户要的是退回上一版内容。
  void setText(
    String module,
    String field,
    String value, {
    String source = StudioSource.manual,
  }) {
    final target = ensure(module, field);
    if (target.text == value) return;
    if (!target.isEmpty) target._remember();
    target.text = value;
    target.items = [];
    target.source = source;
    target.updatedAt = _now();
    updatedAt = target.updatedAt;
  }

  /// 写一串条目。空条目会被丢掉，免得存一堆空气。
  void setItems(
    String module,
    String field,
    List<String> value, {
    String source = StudioSource.manual,
  }) {
    final target = ensure(module, field);
    final cleaned = [
      for (final item in value)
        if (item.trim().isNotEmpty) item,
    ];
    if (_sameList(target.items, cleaned)) return;
    if (!target.isEmpty) target._remember();
    target.items = cleaned;
    target.source = source;
    target.updatedAt = _now();
    updatedAt = target.updatedAt;
  }

  /// 锁 / 解锁。锁不是内容，不进撤销栈。
  bool toggleLock(String module, String field) {
    final target = ensure(module, field);
    target.locked = !target.locked;
    return target.locked;
  }

  /// 退回上一版。条目字段按行还原——这也是 [StudioField._snapshot] 的约定。
  bool undo(String module, String field) {
    final target = peek(module, field);
    if (target == null || target.history.isEmpty) return false;
    final previous = target.history.removeLast();
    if (target.items.isEmpty) {
      target.text = previous;
    } else {
      target.items = previous.isEmpty ? [] : previous.split('\n');
      target.text = '';
    }
    target.source = StudioSource.manual;
    target.updatedAt = _now();
    updatedAt = target.updatedAt;
    return true;
  }

  bool canUndo(String module, String field) =>
      peek(module, field)?.history.isNotEmpty ?? false;

  /// 锁定字段的文字，喂给 AI 当约束用。
  Map<String, String> lockedValues(String module) => {
    for (final entry
        in (modules[module] ?? const <String, StudioField>{}).entries)
      if (entry.value.locked && !entry.value.isEmpty)
        entry.key: entry.value.items.isEmpty
            ? entry.value.text
            : entry.value.items.join('\n'),
  };

  Map<String, Object?> toJson() => {
    'v': version,
    'updatedAt': updatedAt,
    if (idea.trim().isNotEmpty) 'idea': idea,
    'modules': {
      for (final entry in modules.entries)
        if (entry.value.isNotEmpty)
          entry.key: {
            for (final field in entry.value.entries)
              if (!field.value.isEmpty || field.value.locked)
                field.key: field.value.toJson(),
          },
    },
    if (book.isNotEmpty)
      'book': [
        for (final entry in book)
          if (!entry.isEmpty) entry.toJson(),
      ],
    if (state != null && state!.isNotEmpty) 'state': state,
    if (engineering.isNotEmpty) 'engineering': engineering,
  };

  factory StudioDraft.fromJson(Object? json) {
    if (json is! Map) return StudioDraft();
    final modules = <String, Map<String, StudioField>>{};
    final raw = json['modules'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final fields = <String, StudioField>{};
        for (final field in (entry.value as Map).entries) {
          if (field.key is! String || field.value is! Map) continue;
          fields[field.key as String] = StudioField.fromJson(
            field.value as Map<String, Object?>,
          );
        }
        if (fields.isNotEmpty) modules[entry.key as String] = fields;
      }
    }
    return StudioDraft(
      version: json['v'] is int ? json['v']! as int : studioDraftVersion,
      updatedAt: json['updatedAt'] is int ? json['updatedAt']! as int : 0,
      idea: json['idea'] is String ? json['idea']! as String : '',
      modules: modules,
      book: [
        if (json['book'] is List)
          for (final entry in json['book']! as List)
            if (entry is Map)
              StudioBookEntry.fromJson(entry.cast<String, Object?>()),
      ],
      state: json['state'] is Map
          ? (json['state']! as Map).cast<String, Object?>()
          : null,
      engineering: json['engineering'] is Map
          ? {...(json['engineering']! as Map).cast<String, Object?>()}
          : null,
    );
  }

  StudioDraft copy() => StudioDraft(
    version: version,
    updatedAt: updatedAt,
    idea: idea,
    modules: modules,
    book: book,
    state: state,
    engineering: engineering,
  );

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
