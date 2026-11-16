// 世界书: the entries a card carries in its own V3 character_book (engine
// T16), listed by order with a switch each; one opens to edit, a new one is
// added, an old one deleted. Each edit goes to the card by the entry's place
// in the book (its index), so entries keep their identity.

import 'dart:async';

import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../tavern/lorebook_ai.dart';
import '../../tavern/tavern_book_entry.dart';
import '../../tavern/tavern_provider.dart';
import '../common/app_dialog.dart';
import '../common/app_sheet.dart';
import '../common/sheet_title_bar.dart';
import '../common/brief_notice.dart';
import '../common/discard_guard.dart';
import '../common/smooth_size.dart';
import '../features/feature_kit.dart';
import '../providers/provider_widgets.dart';
import '../settings/settings_widgets.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'tavern_lorebook_test_page.dart';
import 'tavern_stepper.dart';
import 'tavern_library_book_page.dart';
import 'tavern_widgets.dart';

/// One entry of the book, at [index] in its entries array.
typedef TavernBookEntry = ({int index, Map<String, Object?> entry});

/// A card's own book as stored: its name, and its entries highest order
/// first, as ST lists them. Read again whenever the library changes.
final tavernCardBookProvider = FutureProvider.autoDispose
    .family<({String? name, List<TavernBookEntry> entries}), String>((
      ref,
      characterId,
    ) async {
      ref.watch(tavernCharactersProvider);
      final fields = await ref
          .watch(tavernProvider)
          .characterFields(characterId);
      final book = fields?['character_book'];
      final entries = <TavernBookEntry>[
        if (book is Map && book['entries'] is List)
          for (final (i, e) in (book['entries'] as List).indexed)
            if (e is Map<String, Object?>) (index: i, entry: e),
      ];
      // Stable: equal orders keep the book's own order.
      final sorted = [...entries]
        ..sort((a, b) => _order(b.entry).compareTo(_order(a.entry)));
      final name =
          book is Map &&
              book['name'] is String &&
              (book['name'] as String).isNotEmpty
          ? book['name'] as String
          : null;
      return (name: name, entries: sorted);
    });

num _order(Map<String, Object?> e) => switch (e['insertion_order']) {
  final num n => n,
  _ => 0,
};

List<String> _strings(Object? v) => [
  if (v is List)
    for (final s in v)
      if (s is String && s.isNotEmpty) s,
];

/// What a list row calls an entry: its name, else its first key.
String tavernBookEntryTitle(Map<String, Object?> e) {
  final comment = e['comment'] is String ? (e['comment'] as String).trim() : '';
  if (comment.isNotEmpty) return comment;
  final keys = _strings(e['keys']);
  return keys.isNotEmpty ? keys.first : '—';
}

class TavernLorebookPage extends ConsumerWidget {
  const TavernLorebookPage({super.key, required this.characterId});

  final String characterId;

  static Route<void> route(String characterId) => MaterialPageRoute<void>(
    builder: (_) => TavernLorebookPage(characterId: characterId),
  );

  Future<void> _setEnabled(WidgetRef ref, int index, bool on) async {
    await ref.read(tavernProvider).updateCharacterBookEntry(
      characterId,
      index,
      {'enabled': on},
    );
    ref.invalidate(tavernCardBookProvider(characterId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final book = ref.watch(tavernCardBookProvider(characterId)).value;
    void open(TavernBookEntry? entry) => unawaited(
      Navigator.of(context).push(
        TavernLorebookEntryPage.route(characterId: characterId, entry: entry),
      ),
    );
    return AppPage.list(
      title: book?.name ?? l10n.tavernLorebook,
      actions: [
        if (book != null && book.entries.isNotEmpty)
          GlassIconButton(
            key: const ValueKey('tavern-lore-test'),
            icon: AppIcons.play,
            tooltip: l10n.tavernLoreTest,
            onPressed: () => unawaited(
              Navigator.of(context)
                  .push(TavernLorebookTestPage.route(characterId)),
            ),
          ),
        GlassIconButton(
          key: const ValueKey('tavern-lore-add'),
          icon: AppIcons.add,
          tooltip: l10n.tavernLorebookAdd,
          onPressed: () => open(null),
        ),
      ],
      children: [
        if (book == null)
          const QuietSpinner()
        else if (book.entries.isEmpty)
          Padding(
            key: const ValueKey('tavern-lore-empty'),
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
            child: Text(
              l10n.tavernLorebookStart,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: DshColors.of(context).textTertiary,
                height: 1.5,
              ),
            ),
          )
        else
          SettingsSection(
            title: l10n.tavernLorebookEntries(book.entries.length),
            footer: Text(l10n.tavernLorebookNote),
            children: [
              for (final (i, e) in book.entries.indexed)
                TavernBookEntryRow(
                  key: ValueKey('tavern-lore-$i'),
                  entry: e.entry,
                  onOpen: () => open(e),
                  onEnabled: (on) => unawaited(_setEnabled(ref, e.index, on)),
                ),
            ],
          ),
      ],
    );
  }
}

/// An entry in the list: its name, its keys, 常驻 if always on, and a switch.
/// [entry] in the card's field names.
  /// 批量选择时：选中了没有，点一下切不切。
Future<String?> showLoreAiInstruction(BuildContext context) =>
    showAppDialog<String>(
      context: context,
      builder: (_) => const _LoreAiInstructionDialog(),
    );

class _LoreAiInstructionDialog extends StatefulWidget {
  const _LoreAiInstructionDialog();

  @override
  State<_LoreAiInstructionDialog> createState() =>
      _LoreAiInstructionDialogState();
}

class _LoreAiInstructionDialogState extends State<_LoreAiInstructionDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.tavernLoreAiAsk),
      content: TextField(
        key: const ValueKey('tavern-lore-ai-instruction'),
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        decoration: InputDecoration(hintText: l10n.tavernLoreAiAskHint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('tavern-lore-ai-go'),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.commonDone),
        ),
      ],
    );
  }
}

class TavernBookEntryRow extends StatelessWidget {
  const TavernBookEntryRow({
    super.key,
    required this.entry,
    required this.onOpen,
    required this.onEnabled,
    this.selected = false,
    this.onSelect,
  });

  final Map<String, Object?> entry;
  final VoidCallback onOpen;
  final ValueChanged<bool> onEnabled;

  /// 条目编辑器里的 AI：先给候选，采用才改这一格。
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final keys = _strings(entry['keys']);
    final on = entry['enabled'] != false;
    return InkWell(
      onTap: onSelect ?? onOpen,
      splashFactory: rowSplash(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SettingsMetrics.inset, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Opacity(
                opacity: on ? 1 : 0.5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            tavernBookEntryTitle(entry),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        if (entry['constant'] == true)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              l10n.tavernLorebookConstant,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (keys.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          l10n.tavernLorebookKeys(keys.join('、')),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: dsh.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Switch(value: on, onChanged: onEnabled),
          ],
        ),
      ),
    );
  }
}

/// Where an entry is kept — a card's own book, or a book in the library — and
/// how an edit reaches it there. Entries go in and out in the card's field
/// names (tavern_book_entry.dart turns a library book's own into them).
abstract class TavernEntryHome {
  Future<void> add(Tavern tavern, Map<String, Object?> entry);
  Future<void> update(Tavern tavern, int index, Map<String, Object?> changes);
  Future<void> delete(Tavern tavern, int index);

  /// The list behind the page, read again.
  void refresh(WidgetRef ref);
}

/// A card's own book: each edit goes to the card by the entry's index.
class TavernCardBookHome implements TavernEntryHome {
  const TavernCardBookHome(this.characterId);

  final String characterId;

  @override
  Future<void> add(Tavern tavern, Map<String, Object?> entry) =>
      tavern.addCharacterBookEntry(characterId, entry);

  @override
  Future<void> update(Tavern tavern, int index, Map<String, Object?> changes) =>
      tavern.updateCharacterBookEntry(characterId, index, changes);

  @override
  Future<void> delete(Tavern tavern, int index) =>
      tavern.deleteCharacterBookEntry(characterId, index);

  @override
  void refresh(WidgetRef ref) =>
      ref.invalidate(tavernCardBookProvider(characterId));
}

/// One entry, edited; [entry] null for a new one, added on save.
class TavernLorebookEntryPage extends ConsumerStatefulWidget {
  const TavernLorebookEntryPage({super.key, required this.home, this.entry});

  final TavernEntryHome home;
  final TavernBookEntry? entry;

  static Route<void> route({
    required String characterId,
    TavernBookEntry? entry,
  }) => routeIn(TavernCardBookHome(characterId), entry: entry);

  static Route<void> routeIn(TavernEntryHome home, {TavernBookEntry? entry}) =>
      MaterialPageRoute<void>(
        builder: (_) => TavernLorebookEntryPage(home: home, entry: entry),
      );

  @override
  ConsumerState<TavernLorebookEntryPage> createState() =>
      _TavernLorebookEntryPageState();
}

class _TavernLorebookEntryPageState
    extends ConsumerState<TavernLorebookEntryPage> {
  Map<String, Object?> get _old => widget.entry?.entry ?? const {};

  late final _name = TextEditingController(
    text: _old['comment'] is String ? _old['comment'] as String : '',
  );
  late final _keys = TextEditingController(
    text: _strings(_old['keys']).join('，'),
  );
  late final _secondary = TextEditingController(
    text: _strings(_old['secondary_keys']).join('，'),
  );
  late final _content = TextEditingController(
    text: _old['content'] is String ? _old['content'] as String : '',
  );
  late final _order = TextEditingController(
    text: '${_old['insertion_order'] is num ? _old['insertion_order'] : 100}',
  );
  late bool _constant = _old['constant'] == true;
  late bool _enabled = _old['enabled'] != false;

  /// ST's own fields, kept in the entry's extensions (as ST writes a card's
  /// book): where it goes and, at a depth, how deep and as whom; how the
  /// secondary keys count; its chance; case and whole words (null: ST's own
  /// default for the chat).
  Map<String, Object?> get _ext => switch (_old['extensions']) {
    final Map<String, Object?> ext => ext,
    _ => const {},
  };
  late int _position = switch (_ext['position']) {
    final int p when p >= 0 && p <= 7 => p,
    _ => _old['position'] == 'after_char' ? 1 : 0,
  };
  late int _depth = _int(_ext['depth'], 4, max: 1000);
  late int _role = _int(_ext['role'], 0, max: 2);
  late int _logic = _int(_ext['selectiveLogic'], 0, max: 3);
  late int _chance = _ext['useProbability'] == false
      ? 100
      : _int(_ext['probability'], 100, max: 100);
  late bool? _case = _ext['case_sensitive'] is bool
      ? _ext['case_sensitive'] as bool
      : null;
  late bool? _whole = _ext['match_whole_words'] is bool
      ? _ext['match_whole_words'] as bool
      : null;

  /// 专业的触发规则（默认折叠）：递归、分组、扫描深度、冷却、正则。
  /// 这些是 CC v3 条目 extensions 里的名字，写进原生书时由
  /// tavern_book_entry.dart 搬到顶层（excludeRecursion / group / sticky …）。
  late bool _useRegex = _ext['use_regex'] == true;
  late bool _excludeRecursion = _ext['exclude_recursion'] == true;
  late bool _preventRecursion = _ext['prevent_recursion'] == true;

  /// 递归层级：0 = 不开，1 起是层级。引擎里 `delayUntilRecursion` 本来就是数字，
  /// 老卡片写 true 的按 1 读（见 tavern_book_entry.dart 的 tavernBookRecursionLevel）。
  late int _delayLevel = tavernBookRecursionLevel(
    _ext['delay_until_recursion'],
  );
  late final _group = TextEditingController(
    text: _ext['group'] is String ? _ext['group']! as String : '',
  );
  late bool _groupOverride = _ext['group_override'] == true;
  late int _groupWeight = _int(_ext['group_weight'], 100, max: 100);
  late int _scanDepth = _int(_ext['scan_depth'], 0, max: 10);
  late int _sticky = _int(_ext['sticky'], 0, max: 100);
  late int _cooldown = _int(_ext['cooldown'], 0, max: 100);
  late int _delay = _int(_ext['delay'], 0, max: 100);
  var _advanced = false;

  /// 这些字段的"没设过"的样子。等于默认值且原来就没有的，不写回，
  /// 免得给每一条都塞一堆 false / 0。
  static const _extraDefaults = <String, Object?>{
    'use_regex': false,
    'exclude_recursion': false,
    'prevent_recursion': false,
    'delay_until_recursion': 0,
    'group': '',
    'group_override': false,
    'group_weight': 100,
    'scan_depth': 0,
    'sticky': 0,
    'cooldown': 0,
    'delay': 0,
  };

  /// 只在"改过"或"原来就有"时出现。
  /// 这本书的名字（拿不到就空着，提示里那一行会省掉）。
  String _bookName(BuildContext context) => switch (widget.home) {
    TavernCardBookHome(:final characterId) =>
      ref.read(tavernCardBookProvider(characterId)).value?.name ?? '',
    TavernLibraryBookHome(:final bookId) =>
      ref.read(tavernLibraryBookProvider(bookId)).value?.name ?? '',
    _ => '',
  };

  /// 让 AI 写这一条：先给候选，采用才改这一格。
  Future<void> _aiContent() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final action = await showAppSheet<LorebookEntryAiAction>(
      context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(l10n.tavernLoreAi),
            SheetGroup(
              margin: const EdgeInsets.fromLTRB(
                SheetTitleBar.inset,
                0,
                SheetTitleBar.inset,
                12,
              ),
              children: [
                for (final (value, label) in [
                  (LorebookEntryAiAction.expand, l10n.tavernLoreAiExpand),
                  (LorebookEntryAiAction.trim, l10n.tavernLoreAiTrim),
                  (LorebookEntryAiAction.rewrite, l10n.tavernLoreAiRewrite),
                  (LorebookEntryAiAction.keywords, l10n.tavernLoreAiKeys),
                ])
                  SettingsTile(
                    key: ValueKey('tavern-lore-ai-${value.name}'),
                    icon: AppIcons.generateMedia,
                    tinted: false,
                    title: label,
                    chevron: false,
                    onTap: () => Navigator.of(sheet).pop(value),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final instruction = await showLoreAiInstruction(context);
    if (instruction == null || !mounted) return;

    final client = ref.read(tavernModelClientProvider);
    final config = ref.read(tavernModelConfigProvider);
    final buffer = StringBuffer();
    Object? failure;
    try {
      await for (final delta in client.generate(
        config: config,
        body: lorebookBody(
          lorebookEntryAiMessages(
  // 世界名拿这本书的；entry 页只拿到 home，所以从 provider 兜底。
            worldName: _bookName(context),
            title: _name.text,
            keys: _split(_keys.text),
            current: _content.text,
            action: action,
            instruction: instruction,
            english: AppLocale.isEnglish,
          ),
        ),
        cancellation: ModelCancellation(),
      )) {
        if (delta is ModelText) buffer.write(delta.text);
      }
    } on Object catch (e) {
      failure = e;
    }
    if (!mounted) return;
    if (failure != null) {
      messenger?.showBriefNotice(l10n.studioAiFailed);
      return;
    }
    final reply = buffer.toString();
    if (action == LorebookEntryAiAction.keywords) {
      final keys = aiKeysParse(reply);
      if (keys.isEmpty) {
        messenger?.showBriefNotice(l10n.studioAiNothing);
        return;
      }
      setState(() => _keys.text = keys.join('?'));
      return;
    }
    final next = aiProseParse(reply);
    if (next == null) {
      messenger?.showBriefNotice(l10n.studioAiNothing);
      return;
    }
    final adopt = await showAppSheet<bool>(
      context,
      heightFactor: 0.75,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(l10n.tavernLoreAi),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      next,
                      key: const ValueKey('tavern-lore-ai-preview'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('tavern-lore-ai-discard'),
                      onPressed: () => Navigator.of(sheet).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                      child: Text(l10n.studioAiDiscard),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('tavern-lore-ai-adopt'),
                      onPressed: () => Navigator.of(sheet).pop(true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                      child: Text(l10n.studioAiAdopt),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (adopt != true || !mounted) return;
    setState(() => _content.text = next);
  }

  Map<String, Object?> _extras() {
    final out = <String, Object?>{};
    void put(String key, Object? value) {
      if (_ext.containsKey(key) || value != _extraDefaults[key]) {
        out[key] = value;
      }
    }

    put('use_regex', _useRegex);
    put('exclude_recursion', _excludeRecursion);
    put('prevent_recursion', _preventRecursion);
    put(
      'delay_until_recursion',
      tavernBookRecursionValue(_delayLevel, _ext['delay_until_recursion']),
    );
    put('group', _group.text.trim());
    put('group_override', _groupOverride);
    put('group_weight', _groupWeight);
    put('scan_depth', _scanDepth);
    put('sticky', _sticky);
    put('cooldown', _cooldown);
    put('delay', _delay);
    return out;
  }

  late final _edits = Listenable.merge([
    _name,
    _keys,
    _secondary,
    _content,
    _order,
    _group,
  ]);

  /// [value] as a whole number from 0 to [max], or [fallback].
  static int _int(Object? value, int fallback, {required int max}) =>
      switch (value) {
        final num n when n.isFinite && n >= 0 && n <= max => n.round(),
        _ => fallback,
      };

  /// Each ST position, by its number, as a reader would call it.
  String _positionName(int position, L10n l10n) => switch (position) {
    0 => l10n.tavernLorebookBeforeChar,
    1 => l10n.tavernLorebookAfterChar,
    2 => l10n.tavernLorePosAnTop,
    3 => l10n.tavernLorePosAnBottom,
    4 => l10n.tavernLorePosDepth,
    5 => l10n.tavernLorePosExampleTop,
    6 => l10n.tavernLorePosExampleBottom,
    _ => l10n.tavernLorePosOutlet,
  };

  late final Map<String, Object?> _start = _fields();
  bool _saving = false;
  bool _leaving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _keys, _secondary, _content, _order]) {
      c.dispose();
    }
    super.dispose();
  }

  static List<String> _split(String text) => [
    for (final part in text.split(RegExp(r'[,，、\n]')))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  /// The entry as the form now has it, in the card's own field names.
  Map<String, Object?> _fields() {
    final secondary = _split(_secondary.text);
    return {
      'comment': _name.text.trim(),
      'keys': _split(_keys.text),
      'secondary_keys': secondary,
      'selective': secondary.isNotEmpty,
      'content': _content.text,
      'constant': _constant,
      'enabled': _enabled,
      // The card's own field, as ST writes it (only 角色前 is before_char);
      // the engine goes by extensions.position, so that is written too.
      'position': _position == 0 ? 'before_char' : 'after_char',
      'insertion_order': int.tryParse(_order.text.trim()) ?? 100,
      'extensions': <String, Object?>{
        'position': _position,
        'depth': _depth,
        'role': _role,
        'selectiveLogic': _logic,
        'useProbability': true,
        'probability': _chance,
        'case_sensitive': _case,
        'match_whole_words': _whole,
        ..._extras(),
      },
    };
  }

  /// What changed since the page opened: only that is written — within the
  /// extensions too, so what the card had there and nobody touched stays.
  Map<String, Object?> _changes() {
    final now = _fields();
    final ext = now['extensions']! as Map<String, Object?>;
    final was = _start['extensions']! as Map<String, Object?>;
    final extChanges = {
      for (final MapEntry(:key, :value) in ext.entries)
        if ('$value' != '${was[key]}') key: value,
    };
    // A chance only counts with useProbability on: it goes with it.
    if (extChanges.containsKey('probability')) {
      extChanges['useProbability'] = true;
    }
    return {
      for (final MapEntry(:key, :value) in now.entries)
        if (key != 'extensions' && '$value' != '${_start[key]}') key: value,
      if (extChanges.isNotEmpty) 'extensions': extChanges,
    };
  }

  bool _dirty() => !_leaving && _changes().isNotEmpty;

  Future<void> _save() async {
    if (_saving) return;
    final navigator = Navigator.of(context);
    final tavern = ref.read(tavernProvider);
    final l10n = context.l10n;
    final changes = _changes();
    final entry = widget.entry;
    if (entry != null && changes.isEmpty) {
      _leaving = true;
      navigator.pop();
      return;
    }
    // 递归那两项一起开 = 永远不激活（引擎语义），留住一个再存。
    if (tavernRecursionConflict(
      excludeRecursion: _excludeRecursion,
      delayUntilRecursion: _delayLevel > 0,
    )) {
      final message = l10n.tavernLoreRecursionConflict;
      setState(() => _error = message);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (entry == null) {
        await widget.home.add(tavern, _fields());
      } else {
        await widget.home.update(tavern, entry.index, changes);
      }
      if (!mounted) return;
      widget.home.refresh(ref);
      _leaving = true;
      navigator.pop();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is ArgumentError || e is TavernImportError
              ? '${l10n.commonSaveFailed}：$e'
              : l10n.commonSaveFailed;
        });
      }
    }
  }

  Future<void> _delete() async {
    final entry = widget.entry!;
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await confirmTavernDelete(
      context,
      title: l10n.tavernLorebookEntryDeleteTitle(
        tavernBookEntryTitle(entry.entry),
      ),
      message: l10n.tavernLorebookEntryDeleteMessage,
    );
    if (!ok || !mounted) return;
    try {
      await widget.home.delete(ref.read(tavernProvider), entry.index);
    } on Object {
      messenger?.showBriefNotice(l10n.commonSaveFailed);
      return;
    }
    if (!mounted) return;
    widget.home.refresh(ref);
    _leaving = true;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enabled = !_saving;
    TextField field(
      TextEditingController controller, {
      int? maxLines = 1,
      int? minLines,
      TextInputType? keyboard,
    }) => TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      minLines: minLines,
      keyboardType: keyboard,
    );
    final body = <Widget>[
      SettingsSection(
        key: const ValueKey('tavern-lore-common'),
        title: l10n.tavernLoreCommon,
        children: [
          FormFieldGroup(
            children: [
              FormFieldBlock(
                key: const ValueKey('tavern-lore-name'),
                label: l10n.tavernLorebookFieldName,
                helper: l10n.tavernLorebookFieldNameHelp,
                child: field(_name),
              ),
              FormFieldBlock(
                key: const ValueKey('tavern-lore-keys'),
                label: l10n.tavernLorebookFieldKeys,
                helper: l10n.tavernLorebookFieldKeysHelp,
                child: field(_keys),
              ),
              FormFieldBlock(
                key: const ValueKey('tavern-lore-content'),
                label: l10n.tavernLorebookFieldContent,
                trailing: IconButton(
                  key: const ValueKey('tavern-lore-ai'),
                  icon: const Icon(AppIcons.generateMedia, size: 18),
                  tooltip: l10n.tavernLoreAi,
                  onPressed: () => unawaited(_aiContent()),
                ),
                child: field(
                  _content,
                  maxLines: 16,
                  minLines: 5,
                  keyboard: TextInputType.multiline,
                ),
              ),
            ],
          ),
        ],
      ),
      SettingsSection(
        children: [
          SettingsSwitchTile(
            key: const ValueKey('tavern-lore-enabled'),
            title: l10n.tavernLorebookFieldEnabled,
            value: _enabled,
            onChanged: enabled ? (on) => setState(() => _enabled = on) : null,
          ),
          SettingsSwitchTile(
            key: const ValueKey('tavern-lore-constant'),
            title: l10n.tavernLorebookConstant,
            subtitle: l10n.tavernLorebookFieldConstantSubtitle,
            value: _constant,
            onChanged: enabled ? (on) => setState(() => _constant = on) : null,
          ),
          SettingsSegmentTile<int>(
            key: const ValueKey('tavern-lore-position'),
            title: l10n.tavernLorebookFieldPosition,
            segments: [
              for (final p in [0, 1, 4]) PillSegment(p, _positionName(p, l10n)),
              // One of ST's other places, as the card has it: kept, shown.
              if (!const [0, 1, 4].contains(_position))
                PillSegment(_position, _positionName(_position, l10n)),
            ],
            selected: _position,
            onChanged: enabled ? (p) => setState(() => _position = p) : (_) {},
          ),
          // At a depth: how far up the chat, and as whom.
          if (_position == 4) ...[
            SettingsTile(
              key: const ValueKey('tavern-lore-depth'),
              title: l10n.tavernPromptDepth,
              value: TavernStepper(
                keyName: 'tavern-lore-depth',
                value: _depth,
                max: 100,
                onChanged: (d) => setState(() => _depth = d),
              ),
              chevron: false,
            ),
            SettingsSegmentTile<int>(
              key: const ValueKey('tavern-lore-role'),
              title: l10n.tavernPromptRole,
              segments: [
                PillSegment(0, l10n.tavernPromptRoleSystem),
                PillSegment(1, l10n.tavernPromptRoleUser),
                PillSegment(2, l10n.tavernPromptRoleAssistant),
              ],
              selected: _role,
              onChanged: (r) => setState(() => _role = r),
            ),
          ],
        ],
      ),
      // 更多 (docs/design/roleplay-ui.md §9): the rest of ST's entry, as it
      // counts the keys and how often it fires.
      SettingsSection(
        key: const ValueKey('tavern-lore-more'),
        title: l10n.tavernLoreMore,
        children: [
          FormFieldGroup(
            children: [
              FormFieldBlock(
                key: const ValueKey('tavern-lore-secondary'),
                label: l10n.tavernLorebookFieldSecondary,
                helper: l10n.tavernLorebookFieldSecondaryHelp,
                child: field(_secondary),
              ),
            ],
          ),
          SettingsSegmentTile<int>(
            key: const ValueKey('tavern-lore-logic'),
            title: l10n.tavernLoreLogic,
            segments: [
              PillSegment(0, l10n.tavernLoreLogicAndAny),
              PillSegment(3, l10n.tavernLoreLogicAndAll),
              PillSegment(2, l10n.tavernLoreLogicNotAny),
              PillSegment(1, l10n.tavernLoreLogicNotAll),
            ],
            selected: _logic,
            onChanged: (l) => setState(() => _logic = l),
          ),
          FormFieldGroup(
            children: [
              FormFieldBlock(
                key: const ValueKey('tavern-lore-order'),
                label: l10n.tavernLorebookFieldOrder,
                helper: l10n.tavernLorebookFieldOrderHelp,
                child: field(_order, keyboard: TextInputType.number),
              ),
            ],
          ),
          SettingsTile(
            key: const ValueKey('tavern-lore-chance'),
            title: l10n.tavernLoreProbability,
            value: TavernStepper(
              keyName: 'tavern-lore-chance',
              value: _chance,
              max: 100,
              step: 5,
              suffix: '%',
              onChanged: (c) => setState(() => _chance = c),
            ),
            chevron: false,
          ),
          for (final (key, title, value, set) in [
            (
              'tavern-lore-case',
              l10n.tavernLoreCase,
              _case,
              (bool? v) => _case = v,
            ),
            (
              'tavern-lore-whole',
              l10n.tavernLoreWhole,
              _whole,
              (bool? v) => _whole = v,
            ),
          ])
            SettingsSegmentTile<bool?>(
              key: ValueKey(key),
              title: title,
              segments: [
                PillSegment(null, l10n.tavernLoreDefault),
                PillSegment(true, l10n.tavernLoreYes),
                PillSegment(false, l10n.tavernLoreNo),
              ],
              selected: value,
              onChanged: (v) => setState(() => set(v)),
            ),
        ],
      ),
      // 专业的触发规则（规格 §3.4）：默认折叠，别把常用三组淹了。
      SettingsSection(
        key: const ValueKey('tavern-lore-advanced'),
        children: [
          SettingsTile(
            key: const ValueKey('tavern-lore-advanced-toggle'),
            title: l10n.tavernLoreAdvanced,
            subtitle: l10n.tavernLoreAdvancedSubtitle,
            chevron: false,
            trailing: AnimatedRotation(
              turns: _advanced ? 0.5 : 0,
              duration: AppMotion.of(context, AppMotion.standard),
              curve: AppMotion.std,
              child: Icon(
                AppIcons.expand,
                size: 18,
                color: DshColors.of(context).textTertiary,
              ),
            ),
            onTap: enabled
                ? () => setState(() => _advanced = !_advanced)
                : null,
          ),
        ],
      ),
      SmoothSize(
        duration: AppMotion.of(context, AppMotion.standard),
        curve: AppMotion.std,
        alignment: Alignment.topCenter,
        child: !_advanced
            ? const SizedBox(width: double.infinity)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsSection(
                    title: l10n.tavernLoreRecursion,
                    children: [
                      SettingsSwitchTile(
                        key: const ValueKey('tavern-lore-regex'),
                        title: l10n.tavernLoreRegex,
                        subtitle: l10n.tavernLoreRegexSubtitle,
                        value: _useRegex,
                        onChanged: (on) => setState(() => _useRegex = on),
                      ),
                      SettingsSwitchTile(
                        key: const ValueKey('tavern-lore-exclude-recursion'),
                        title: l10n.tavernLoreExclude,
                        subtitle: l10n.tavernLoreExcludeSubtitle,
                        value: _excludeRecursion,
                        onChanged: (on) =>
                            setState(() => _excludeRecursion = on),
                      ),
                      SettingsSwitchTile(
                        key: const ValueKey('tavern-lore-prevent-recursion'),
                        title: l10n.tavernLorePrevent,
                        subtitle: l10n.tavernLorePreventSubtitle,
                        value: _preventRecursion,
                        onChanged: (on) =>
                            setState(() => _preventRecursion = on),
                      ),
                      SettingsTile(
                        key: const ValueKey('tavern-lore-delay-recursion'),
                        title: l10n.tavernLoreDelayRecursion,
                        subtitle: l10n.tavernLoreDelayRecursionSubtitle,
                        value: TavernStepper(
                          keyName: 'tavern-lore-delay-recursion',
                          value: _delayLevel,
                          max: 10,
                          onChanged: (level) =>
                              setState(() => _delayLevel = level),
                        ),
                        chevron: false,
                      ),
                      SettingsTile(
                        key: const ValueKey('tavern-lore-scan-depth'),
                        title: l10n.tavernLoreScanDepth,
                        subtitle: l10n.tavernLoreScanDepthHelp,
                        value: TavernStepper(
                          keyName: 'tavern-lore-scan-depth',
                          value: _scanDepth,
                          max: 10,
                          onChanged: (v) => setState(() => _scanDepth = v),
                        ),
                        chevron: false,
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: l10n.tavernLoreGroup,
                    children: [
                      FormFieldGroup(
                        children: [
                          FormFieldBlock(
                            key: const ValueKey('tavern-lore-group'),
                            label: l10n.tavernLoreGroup,
                            helper: l10n.tavernLoreGroupHelp,
                            child: TextField(
                              controller: _group,
                              enabled: enabled,
                            ),
                          ),
                        ],
                      ),
                      SettingsSwitchTile(
                        key: const ValueKey('tavern-lore-group-override'),
                        title: l10n.tavernLoreGroupOverride,
                        value: _groupOverride,
                        onChanged: (on) => setState(() => _groupOverride = on),
                      ),
                      SettingsTile(
                        key: const ValueKey('tavern-lore-group-weight'),
                        title: l10n.tavernLoreGroupWeight,
                        value: TavernStepper(
                          keyName: 'tavern-lore-group-weight',
                          value: _groupWeight,
                          max: 100,
                          step: 5,
                          onChanged: (v) => setState(() => _groupWeight = v),
                        ),
                        chevron: false,
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: l10n.tavernLoreTiming,
                    children: [
                      for (final (key, title, value, set) in [
                        (
                          'tavern-lore-sticky',
                          l10n.tavernLoreSticky,
                          _sticky,
                          (int v) => _sticky = v,
                        ),
                        (
                          'tavern-lore-cooldown',
                          l10n.tavernLoreCooldown,
                          _cooldown,
                          (int v) => _cooldown = v,
                        ),
                        (
                          'tavern-lore-delay',
                          l10n.tavernLoreDelay,
                          _delay,
                          (int v) => _delay = v,
                        ),
                      ])
                        SettingsTile(
                          key: ValueKey(key),
                          title: title,
                          value: TavernStepper(
                            keyName: key,
                            value: value,
                            max: 100,
                            onChanged: (v) => setState(() => set(v)),
                          ),
                          chevron: false,
                        ),
                    ],
                  ),
                ],
              ),
      ),
      if (widget.entry != null)
        SettingsSection(
          children: [
            SettingsTile(
              key: const ValueKey('tavern-lore-delete'),
              icon: AppIcons.delete,
              danger: true,
              tinted: false,
              title: l10n.tavernLorebookEntryDelete,
              chevron: false,
              onTap: enabled ? () => unawaited(_delete()) : null,
            ),
          ],
        ),
      if (_error case final error?)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Text(
            error,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: DshColors.of(context).danger),
          ),
        ),
      const SizedBox(height: FormBottomBar.height),
    ];
    return DiscardGuard(
      listenable: _edits,
      isDirty: _dirty,
      child: Stack(
        children: [
          AppPage.list(
            title: widget.entry == null
                ? l10n.tavernLorebookEntryNew
                : l10n.tavernLorebookEntryEdit,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: body,
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.viewInsetsOf(context).bottom,
            child: FormBottomBar(
              child: FilledButton(
                key: const ValueKey('tavern-lore-save'),
                onPressed: enabled ? _save : null,
                child: Text(l10n.commonSave),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
