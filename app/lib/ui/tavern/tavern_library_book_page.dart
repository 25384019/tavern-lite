// 资源库 › 世界书 › one book (docs/design/roleplay-ui.md §9): its entries by
// order, a switch each, one opened in the same editor a card's book uses, a
// new one added, an old one deleted. The book is read whole (lorebook) and
// written whole (putLorebook); a book kept in ST's own world-info shape is
// turned into the editor's field names and back (tavern_book_entry.dart).

import 'dart:async';
import 'dart:convert';

import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../tavern/tavern_book_entry.dart';
import '../../tavern/tavern_provider.dart';
import '../../tavern/version_store.dart';
import '../common/app_dialog.dart';
import '../common/app_sheet.dart';
import '../common/brief_notice.dart';
import '../common/sheet_title_bar.dart';
import '../bots/bot_format.dart' show shortTime;
import '../features/feature_kit.dart';
import '../providers/provider_widgets.dart';
import '../settings/settings_widgets.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'tavern_lorebook_page.dart';
import 'tavern_lorebooks_page.dart';
import 'tavern_widgets.dart';

/// A library book as the page shows it: its name, whether it is kept in ST's
/// own shape, and its entries (in the card's field names) highest order first.
typedef TavernLibraryBook = ({
  String name,
  bool native,
  List<TavernBookEntry> entries,
});

/// [raw]'s entries where they are kept: ST's own map by uid, or a list.
Object? _entriesOf(Map<String, Object?> raw) => raw['entries'];

final tavernLibraryBookProvider = FutureProvider.autoDispose
    .family<TavernLibraryBook?, String>((ref, id) async {
      ref.watch(tavernLorebooksProvider);
      final tavern = ref.watch(tavernProvider);
      final raw = await tavern.lorebook(id);
      if (raw == null) return null;
      final summaries = (await tavern.listLorebooks()).where((b) => b.id == id);
      final entries = _entriesOf(raw);
      final native = entries is Map;
      final List<TavernBookEntry> list = switch (entries) {
        final Map<String, Object?> byUid => [
          for (final (i, e) in byUid.values.indexed)
            if (e is Map<String, Object?>)
              (index: i, entry: tavernNativeToCard(e)),
        ],
        final List<Object?> items => [
          for (final (i, e) in items.indexed)
            if (e is Map<String, Object?>) (index: i, entry: e),
        ],
        _ => [],
      };
      num order(TavernBookEntry e) => switch (e.entry['insertion_order']) {
        final num n => n,
        _ => 0,
      };
      // Stable: equal orders keep the book's own order.
      final sorted = [...list]..sort((a, b) => order(b).compareTo(order(a)));
      final name =
          summaries.firstOrNull?.name ??
          (raw['name'] is String ? raw['name']! as String : id);
      return (name: name, native: native, entries: sorted);
    });

/// A library book: each edit reads the whole book, changes the one entry (in
/// its own shape) and writes the whole book back.
class TavernLibraryBookHome implements TavernEntryHome {
  const TavernLibraryBookHome(this.bookId);

  final String bookId;

  Future<void> _edit(
    Tavern tavern,
    void Function(Map<String, Object?> raw) change,
  ) async {
    final stored = await tavern.lorebook(bookId);
    if (stored == null) throw StateError('The lorebook is gone.');
    // A copy to change: what the engine handed out stays as it was.
    final raw = jsonDecode(jsonEncode(stored)) as Map<String, Object?>;
    change(raw);
    await tavern.putLorebook(bookId, raw);
  }

  @override
  Future<void> add(Tavern tavern, Map<String, Object?> entry) =>
      _edit(tavern, (raw) {
        switch (_entriesOf(raw)) {
          case final Map<String, Object?> byUid:
            // The next free uid, as ST numbers them.
            final used = [
              for (final e in byUid.values)
                if (e case {'uid': final int uid}) uid,
            ];
            final uid =
                [
                  ...used,
                  ...byUid.keys.map(int.tryParse).nonNulls,
                ].fold(-1, (a, b) => a > b ? a : b) +
                1;
            byUid['$uid'] = {
              'uid': uid,
              ...tavernCardToNative(entry),
              'displayIndex': byUid.length,
            };
          case final List<Object?> items:
            items.add(entry);
          default:
            raw['entries'] = {
              '0': {'uid': 0, ...tavernCardToNative(entry), 'displayIndex': 0},
            };
        }
      });

  @override
  Future<void> update(Tavern tavern, int index, Map<String, Object?> changes) =>
      _edit(tavern, (raw) {
        switch (_entriesOf(raw)) {
          case final Map<String, Object?> byUid:
            final key = byUid.keys.elementAt(index);
            byUid[key] = tavernMergeEntry(
              byUid[key]! as Map<String, Object?>,
              tavernCardToNative(changes),
            );
          case final List<Object?> items:
            items[index] = tavernMergeEntry(
              items[index]! as Map<String, Object?>,
              changes,
            );
          default:
            throw RangeError.index(index, const [], 'index');
        }
      });

  @override
  Future<void> delete(Tavern tavern, int index) => _edit(tavern, (raw) {
    switch (_entriesOf(raw)) {
      case final Map<String, Object?> byUid:
        byUid.remove(byUid.keys.elementAt(index));
      case final List<Object?> items:
        items.removeAt(index);
      default:
        throw RangeError.index(index, const [], 'index');
    }
  });

  @override
  void refresh(WidgetRef ref) => ref
    ..invalidate(tavernLorebooksProvider)
    ..invalidate(tavernLibraryBookProvider(bookId));
}

class TavernLibraryBookPage extends ConsumerStatefulWidget {
  const TavernLibraryBookPage({super.key, required this.bookId});

  final String bookId;

  static Route<void> route(String bookId) => MaterialPageRoute<void>(
    builder: (_) => TavernLibraryBookPage(bookId: bookId),
  );

  @override
  ConsumerState<TavernLibraryBookPage> createState() =>
      _TavernLibraryBookPageState();
}

class _TavernLibraryBookPageState extends ConsumerState<TavernLibraryBookPage> {
  final _search = TextEditingController();
  final _selected = <int>{};
  var _selecting = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Map<String, Object?> entry, String query) {
    if (query.trim().isEmpty) return true;
    final needle = query.trim().toLowerCase();
    final keys = entry['keys'];
    final haystack = [
      entry['comment'],
      entry['content'],
      if (keys is List) ...keys,
    ].whereType<String>().join('\n').toLowerCase();
    return haystack.contains(needle);
  }

  /// 版本快照：存一份现在的样子，或者回到某一版。
  Future<void> _showHistory() async {
    final l10n = context.l10n;
    final tavern = ref.read(tavernProvider);
    final store = await ref.read(versionStoreProvider.future);
    if (!mounted) return;

    Future<List<SavedVersion>> reload() =>
        store.list('lorebook', widget.bookId);

    await showAppSheet<void>(
      context,
      heightFactor: 0.8,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheetState) {
          Future<void> refresh() async => setSheetState(() {});
          return SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetTitleBar(l10n.tavernBookHistory),
                Flexible(
                  child: SingleChildScrollView(
                    child: FutureBuilder<List<SavedVersion>>(
                      future: reload(),
                      builder: (_, snapshot) {
                        final versions =
                            snapshot.data ?? const <SavedVersion>[];
                        return SheetGroup(
                          margin: const EdgeInsets.fromLTRB(
                            SheetTitleBar.inset,
                            0,
                            SheetTitleBar.inset,
                            12,
                          ),
                          children: [
                            SettingsTile(
                              key: const ValueKey('tavern-book-snapshot'),
                              icon: AppIcons.save,
                              tinted: false,
                              title: l10n.tavernBookSnapshot,
                              subtitle: l10n.tavernBookSnapshotHint(
                                versionLimit,
                              ),
                              chevron: false,
                              onTap: () async {
                                final raw = await tavern.lorebook(
                                  widget.bookId,
                                );
                                if (raw == null || !context.mounted) return;
                                await store.save(
                                  'lorebook',
                                  widget.bookId,
                                  raw,
                                  label: l10n.tavernBookSnapshotLabel,
                                );
                                await refresh();
                                if (context.mounted) {
                                  Navigator.of(sheet).pop();
                                  ScaffoldMessenger.maybeOf(
                                    context,
                                  )?.showSnackBar(
                                    briefNoticeBar(l10n.tavernBookSnapshotted),
                                  );
                                }
                              },
                            ),
                            if (versions.isEmpty)
                              Padding(
                                key: const ValueKey(
                                  'tavern-book-history-empty',
                                ),
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  8,
                                ),
                                child: Text(
                                  l10n.tavernBookHistoryEmpty,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: DshColors.of(context)
                                            .textTertiary,
                                      ),
                                ),
                              ),
                            for (final version in versions)
                              SettingsTile(
                                key: ValueKey(
                                  'tavern-book-version-${version.id}',
                                ),
                                icon: AppIcons.history,
                                tinted: false,
                                title: shortTime(version.at),
                                subtitle: l10n.tavernBookVersionSize(
                                  (version.bytes / 1024).toStringAsFixed(1),
                                ),
                                trailing: IconButton(
                                  key: ValueKey(
                                    'tavern-book-version-delete-${version.id}',
                                  ),
                                  icon: const Icon(AppIcons.delete, size: 18),
                                  onPressed: () async {
                                    await store.delete(
                                      'lorebook',
                                      widget.bookId,
                                      version.id,
                                    );
                                    await refresh();
                                  },
                                ),
                                onTap: () async {
                                  final ok = await showAppDialog<bool>(
                                    context: context,
                                    builder: (dialog) => AlertDialog(
                                      title: Text(l10n.tavernBookRestoreTitle),
                                      content: Text(l10n.tavernBookRestoreBody),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(dialog).pop(false),
                                          child: Text(l10n.commonCancel),
                                        ),
                                        FilledButton(
                                          key: const ValueKey(
                                            'tavern-book-restore-ok',
                                          ),
                                          onPressed: () =>
                                              Navigator.of(dialog).pop(true),
                                          child: Text(l10n.tavernBookRestore),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok != true || !context.mounted) return;
                                  final json = await store.read(
                                    'lorebook',
                                    widget.bookId,
                                    version.id,
                                  );
                                  if (json == null) return;
                                  await tavern.putLorebook(widget.bookId, json);
                                  ref.invalidate(
                                    tavernLibraryBookProvider(widget.bookId),
                                  );
                                  ref.invalidate(tavernLorebooksProvider);
                                  if (context.mounted) {
                                    Navigator.of(sheet).pop();
                                    ScaffoldMessenger.maybeOf(
                                      context,
                                    )?.showSnackBar(
                                      briefNoticeBar(l10n.tavernBookRestored),
                                    );
                                  }
                                },
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _batch(
    TavernLibraryBookHome home,
    List<int> indices,
    Map<String, Object?> patch,
  ) async {
    final tavern = ref.read(tavernProvider);
    for (final index in indices) {
      await home.update(tavern, index, patch);
    }
    home.refresh(ref);
  }

  Future<void> _batchDelete(
    TavernLibraryBookHome home,
    List<int> indices,
  ) async {
    final l10n = context.l10n;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.tavernBookDeleteConfirm(indices.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('tavern-library-delete-ok'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final tavern = ref.read(tavernProvider);
    // ????????????? index ?????
    for (final index in [...indices]..sort((a, b) => b.compareTo(a))) {
      await home.delete(tavern, index);
    }
    home.refresh(ref);
    setState(() {
      _selected.clear();
      _selecting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final home = TavernLibraryBookHome(widget.bookId);
    final book = ref.watch(tavernLibraryBookProvider(widget.bookId)).value;
    void open(TavernBookEntry? entry) => unawaited(
      Navigator.of(context)
          .push(TavernLorebookEntryPage.routeIn(home, entry: entry)),
    );

    Future<void> setEnabled(int index, bool on) async {
      await home.update(ref.read(tavernProvider), index, {'enabled': on});
      home.refresh(ref);
    }

    final shown = [
      for (final entry in book?.entries ?? const <TavernBookEntry>[])
        if (_matches(entry.entry, _search.text)) entry,
    ];

    return AppPage.list(
      title: book?.name ?? l10n.tavernLorebook,
      actions: [
        if ((book?.entries.length ?? 0) > 1)
          GlassIconButton(
            key: const ValueKey('tavern-library-book-select'),
            icon: _selecting ? AppIcons.close : AppIcons.selected,
            tooltip: _selecting ? l10n.commonCancel : l10n.tavernBookSelect,
            onPressed: () => setState(() {
              _selecting = !_selecting;
              _selected.clear();
            }),
          ),
        GlassIconButton(
          key: const ValueKey('tavern-library-book-history'),
          icon: AppIcons.history,
          tooltip: l10n.tavernBookHistory,
          onPressed: () => unawaited(_showHistory()),
        ),
        GlassIconButton(
          key: const ValueKey('tavern-library-book-add'),
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
            key: const ValueKey('tavern-library-book-empty'),
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
            child: Text(
              l10n.tavernLibraryBookStart,
              style: theme.textTheme.bodySmall?.copyWith(
                color: DshColors.of(context).textTertiary,
                height: 1.5,
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: FormFieldBlock(
              key: const ValueKey('tavern-library-book-search'),
              label: l10n.tavernBookSearch,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: l10n.tavernBookSearchHint,
                  prefixIcon: const Icon(AppIcons.search, size: 18),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(AppIcons.close, size: 18),
                          onPressed: () => setState(_search.clear),
                        ),
                ),
              ),
            ),
          ),
          if (shown.isEmpty)
            Padding(
              key: const ValueKey('tavern-library-book-nomatch'),
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
              child: Text(
                l10n.tavernBookNoMatch,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: DshColors.of(context).textTertiary,
                ),
              ),
            )
          else
            SettingsSection(
              key: const ValueKey('tavern-library-book'),
              title: l10n.tavernLorebookEntries(shown.length),
              footer: Text(l10n.tavernLibraryBookNote),
              children: [
                for (final entry in shown)
                  TavernBookEntryRow(
                    key: ValueKey('tavern-library-entry-${entry.index}'),
                    entry: entry.entry,
                    selected: _selected.contains(entry.index),
                    onSelect: _selecting
                        ? () => setState(() {
                            if (!_selected.remove(entry.index)) {
                              _selected.add(entry.index);
                            }
                          })
                        : null,
                    onOpen: () => open(entry),
                    onEnabled: (on) => unawaited(setEnabled(entry.index, on)),
                  ),
              ],
            ),
          if (_selecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const ValueKey('tavern-library-select-all'),
                          onPressed: () => setState(() {
                            if (_selected.length == shown.length) {
                              _selected.clear();
                            } else {
                              _selected
                                ..clear()
                                ..addAll(shown.map((e) => e.index));
                            }
                          }),
                          child: Text(
                            _selected.length == shown.length
                                ? l10n.tavernBookSelectNone
                                : l10n.tavernBookSelectAll,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.tavernBookSelected(_selected.length),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const ValueKey('tavern-library-enable'),
                          onPressed: _selected.isEmpty
                              ? null
                              : () => unawaited(
                                  _batch(home, _selected.toList(), {
                                    'enabled': true,
                                  }),
                                ),
                          child: Text(l10n.tavernBookEnable),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          key: const ValueKey('tavern-library-disable'),
                          onPressed: _selected.isEmpty
                              ? null
                              : () => unawaited(
                                  _batch(home, _selected.toList(), {
                                    'enabled': false,
                                  }),
                                ),
                          child: Text(l10n.tavernBookDisable),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          key: const ValueKey('tavern-library-delete-selected'),
                          onPressed: _selected.isEmpty
                              ? null
                              : () => unawaited(
                                  _batchDelete(home, _selected.toList()),
                                ),
                          child: Text(
                            l10n.tavernBookDeleteSelected(_selected.length),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
