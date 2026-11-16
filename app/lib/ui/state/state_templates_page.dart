// 状态模板：一套状态项存下来，反复用到不同的卡上。
//
// 两页：列表（新建 / 编辑 / 删除 / 应用到角色）和编辑器（模板名 + 状态项增删改）。
// 「应用」= 把模板折成 `extensions.dshgo.state` 写进那张卡，舞台立刻能显示；
// 卡里已经有状态时会先问一句，不静默覆盖。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../tavern/state_templates.dart';
import '../../tavern/tavern_provider.dart';
import '../common/app_dialog.dart';
import '../common/app_sheet.dart';
import '../common/brief_notice.dart';
import '../common/sheet_title_bar.dart';
import '../features/feature_kit.dart' show QuietSpinner;
import '../providers/provider_widgets.dart';
import '../settings/settings_widgets.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../tavern/tavern_widgets.dart' show showTavernActions;
import '../theme/theme.dart';
import 'state_template_edit_page.dart';

/// 模板列表。改完就 invalidate 它。
final stateTemplatesProvider = FutureProvider.autoDispose<List<StateTemplate>>((
  ref,
) async {
  final store = await ref.watch(stateTemplateStoreProvider.future);
  return store.read();
});

class StateTemplatesPage extends ConsumerStatefulWidget {
  const StateTemplatesPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const StateTemplatesPage());

  @override
  ConsumerState<StateTemplatesPage> createState() => _StateTemplatesPageState();
}

class _StateTemplatesPageState extends ConsumerState<StateTemplatesPage> {
  var _busy = false;

  Future<void> _save(List<StateTemplate> templates) async {
    final store = await ref.read(stateTemplateStoreProvider.future);
    await store.write(templates);
    ref.invalidate(stateTemplatesProvider);
  }

  Future<void> _newTemplate() async {
    final template = await Navigator.of(context)
        .push(StateTemplateEditPage.route(null));
    if (!mounted || template == null) return;
    final templates = <StateTemplate>[
      ...?ref.read(stateTemplatesProvider).value,
      template,
    ];
    await _save(templates);
  }

  Future<void> _edit(StateTemplate template) async {
    final next = await Navigator.of(context)
        .push(StateTemplateEditPage.route(template));
    if (!mounted || next == null) return;
    final templates = [
      for (final item
          in ref.read(stateTemplatesProvider).value ?? const <StateTemplate>[])
        if (item.id == next.id) next else item,
    ];
    await _save(templates);
  }

  Future<void> _delete(StateTemplate template) async {
    final l10n = context.l10n;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.stateTemplateDeleteTitle(template.name)),
        content: Text(l10n.stateTemplateDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('state-template-delete-ok'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _save([
      for (final item
          in ref.read(stateTemplatesProvider).value ?? const <StateTemplate>[])
        if (item.id != template.id) item,
    ]);
  }

  /// 应用到哪张卡：先把书架列出来让人挑。
  Future<void> _apply(StateTemplate template) async {
    final l10n = context.l10n;
    final characters = await ref.read(tavernProvider).watchCharacters().first;
    if (!mounted) return;
    if (characters.isEmpty) {
      _say(l10n.stateTemplateNoCharacters);
      return;
    }
    final picked = await showAppSheet<String>(
      context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(l10n.stateTemplateApplyTitle(template.name)),
            Flexible(
              child: SingleChildScrollView(
                child: SheetGroup(
                  margin: const EdgeInsets.fromLTRB(
                    SheetTitleBar.inset,
                    0,
                    SheetTitleBar.inset,
                    12,
                  ),
                  children: [
                    for (final character in characters)
                      SettingsTile(
                        key: ValueKey('state-template-target-${character.id}'),
                        icon: AppIcons.tavern,
                        tinted: false,
                        title: character.name,
                        chevron: false,
                        onTap: () => Navigator.of(sheet).pop(character.id),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;

    // 卡里已经有状态：先问，别把人家写好的冲掉。
    final fields = await ref.read(tavernProvider).characterFields(picked);
    final existing = (fields?['extensions'] as Map?)?['dshgo'];
    final hasState = existing is Map && existing['state'] is Map;
    if (!mounted) return;
    if (hasState) {
      final ok = await showAppDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(l10n.stateTemplateOverwriteTitle),
          content: Text(l10n.stateTemplateOverwriteMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              key: const ValueKey('state-template-overwrite-ok'),
              onPressed: () => Navigator.of(dialog).pop(true),
              child: Text(l10n.stateTemplateOverwriteAction),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(tavernProvider).updateCharacterData(picked, {
        'extensions': {
          'dshgo': {'state': template.toState()},
        },
      });
      if (!mounted) return;
      final name = characters.firstWhere((c) => c.id == picked).name;
      _say(l10n.stateTemplateApplied(name));
    } on Object {
      if (mounted) _say(l10n.stateTemplateApplyFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String text) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(briefNoticeBar(text));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final templates = ref.watch(stateTemplatesProvider).value;
    return AppPage.list(
      title: l10n.stateTemplates,
      subtitle: Text(l10n.stateTemplatesSubtitle),
      actions: [
        GlassIconButton(
          key: const ValueKey('state-template-new'),
          icon: AppIcons.add,
          tooltip: l10n.stateTemplateNew,
          onPressed: _busy ? null : () => unawaited(_newTemplate()),
        ),
      ],
      children: [
        if (templates == null)
          const QuietSpinner()
        else if (templates.isEmpty)
          Padding(
            key: const ValueKey('state-templates-empty'),
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
            child: Text(
              l10n.stateTemplateNoTemplates,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: DshColors.of(context).textTertiary,
                height: 1.5,
              ),
            ),
          )
        else
          for (final template in templates)
            SettingsSection(
              children: [
                SettingsTile(
                  key: ValueKey('state-template-${template.id}'),
                  icon: AppIcons.chart,
                  tinted: false,
                  title: template.name,
                  subtitle: l10n.stateTemplateFieldCount(
                    template.fields.length,
                  ),
                  onTap: () => unawaited(
                    showTavernActions(context, [
                      (
                        AppIcons.done,
                        l10n.stateTemplateApply,
                        () => unawaited(_apply(template)),
                      ),
                      (
                        AppIcons.edit,
                        l10n.commonEdit,
                        () => unawaited(_edit(template)),
                      ),
                      (
                        AppIcons.delete,
                        l10n.commonDelete,
                        () => unawaited(_delete(template)),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Text(
            l10n.stateTemplatesNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: DshColors.of(context).textTertiary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// 「存成模板」用得上：把一张卡现在的状态读成模板。
Future<StateTemplate?> stateTemplateFromCard(
  WidgetRef ref,
  String characterId, {
  required String name,
}) async {
  final fields = await ref.read(tavernProvider).characterFields(characterId);
  final state = (fields?['extensions'] as Map?)?['dshgo'];
  return StateTemplate.fromState(
    state is Map ? state['state'] as Map<String, Object?>? : null,
    id: newStateTemplateId(),
    name: name,
  );
}
