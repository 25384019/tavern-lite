// 世界书 AI 创作：一句创意 → 蓝图 → 条目规划 → 分批写正文 → 一致性检查 → 存成一本。
//
// 每一步的产物都摆出来给人看、改、重跑；只有最后一步落盘。一批失败只重跑那一批。
// 生成完就是一本书，之后照常在条目页里改——不引入第二种世界书格式。

import 'dart:async';

import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../tavern/lorebook_ai.dart';
import '../../tavern/lorebook_new.dart';
import '../../tavern/preset_persona.dart';
import '../../tavern/tavern_provider.dart';
import '../../tavern/tavern_settings.dart';
import '../common/app_dialog.dart';
import '../common/app_sheet.dart';
import '../common/brief_notice.dart';
import '../common/sheet_title_bar.dart';
import '../features/feature_kit.dart' show QuietSpinner;
import '../providers/provider_widgets.dart';
import '../settings/settings_widgets.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'tavern_lorebooks_page.dart';
import 'tavern_presets_page.dart' show tavernPresetsProvider;

class TavernLorebookWizardPage extends ConsumerStatefulWidget {
  const TavernLorebookWizardPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const TavernLorebookWizardPage());

  @override
  ConsumerState<TavernLorebookWizardPage> createState() =>
      _TavernLorebookWizardPageState();
}

class _TavernLorebookWizardPageState
    extends ConsumerState<TavernLorebookWizardPage> {
  final _idea = TextEditingController();
  var _scale = 2; // 1 小 2 中 3 大
  var _kind = LorebookKind.world;
  var _busy = false;
  String? _error;

  /// 世界书这条线自己的人格层：和 AI 制卡那份分开记（tavern_settings）。
  /// build 里读它，选完立刻重画。
  String? get _personaId => ref.watch(tavernSettingsProvider).bookPersonaId;

  /// 生成时用：那会儿不在 build 里，不能 watch。
  String? get _personaIdNow => ref.read(tavernSettingsProvider).bookPersonaId;

  LorebookBlueprint? _blueprint;
  List<LorebookPlanEntry> _plan = const [];
  final _picked = <String>{};
  final _written = <LorebookDraftEntry>[];
  List<LorebookIssue> _issues = const [];

  @override
  void dispose() {
    _idea.dispose();
    super.dispose();
  }

  /// 篇幅给的条数；破甲、文风这两类不看篇幅，自己的数量说了算。
  int get _target => _kind.target(
    switch (_scale) {
      1 => 5,
      3 => 18,
      _ => 10,
    },
  );

  /// 跑一次请求，返回模型原文；失败返回 null 并摆出错误。
  ///
  /// 默认给 4000（和 AI 制卡同一个数）：这里没有「一次只写一小段」的步骤，
  /// 蓝图和规划都是整段 JSON，默认值给小了就会被截断（详见 [lorebookPlanTokens]）。
  Future<String?> _ask(
    List<Map<String, Object?>> messages, {
    int maxTokens = 4000,
  }) async {
    final client = ref.read(tavernModelClientProvider);
    final config = ref.read(tavernModelConfigProvider);
    final buffer = StringBuffer();
    try {
      await for (final delta in client.generate(
        config: config,
        body: lorebookBody(messages, maxTokens: maxTokens),
        cancellation: ModelCancellation(),
      )) {
        if (delta is ModelText) buffer.write(delta.text);
      }
    } on Object {
      if (mounted) setState(() => _error = context.l10n.studioAiFailed);
      return null;
    }
    return buffer.toString();
  }

  /// 选中的人格层：从资源库那本预设现取（预设改了，下次生成就跟着变）。
  /// 取不到就当没选，不拦着生成。
  Future<String?> _personaText() async {
    final id = _personaIdNow;
    if (id == null) return null;
    try {
      final preset = await ref.read(tavernProvider).preset(id);
      return preset == null ? null : presetPersonaText(preset.raw);
    } on Object {
      return null;
    }
  }

  /// 当前人格层的名字（没选、或那本预设被删了 = null）。
  String? get _personaName {
    final id = _personaId;
    if (id == null) return null;
    final presets = ref.watch(tavernPresetsProvider).value ?? const [];
    for (final preset in presets) {
      if (preset.id == id) return preset.name;
    }
    return null;
  }

  String _kindName(L10n l10n, LorebookKind kind) => switch (kind) {
    LorebookKind.world => l10n.lorebookKindWorld,
    LorebookKind.style => l10n.lorebookKindStyle,
    LorebookKind.guardrail => l10n.lorebookKindGuardrail,
    LorebookKind.mechanic => l10n.lorebookKindMechanic,
    LorebookKind.lexicon => l10n.lorebookKindLexicon,
  };

  Future<void> _pickKind() async {
    final l10n = context.l10n;
    final picked = await showAppSheet<LorebookKind>(
      context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(l10n.lorebookWizardKind),
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
                    for (final kind in LorebookKind.values)
                      SettingsTile(
                        key: ValueKey('lorebook-kind-${kind.name}'),
                        icon: AppIcons.article,
                        tinted: false,
                        title: _kindName(l10n, kind),
                        value: kind == _kind
                            ? Icon(
                                AppIcons.selected,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        chevron: false,
                        onTap: () => Navigator.of(sheet).pop(kind),
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
    setState(() {
      _kind = picked;
      // 换类型等于换一本书：前面生成的都清掉，免得拿设定书的蓝图去写文风书。
      _blueprint = null;
      _plan = const [];
      _picked.clear();
      _written.clear();
      _issues = const [];
    });
  }

  Future<void> _pickPersona() async {
    final l10n = context.l10n;
    final presets =
        ref.read(tavernPresetsProvider).value ?? const <TavernPresetSummary>[];
    final picked = await showAppSheet<String>(
      context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(l10n.lorebookWizardPersona),
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
                    SettingsTile(
                      key: const ValueKey('lorebook-persona-none'),
                      icon: AppIcons.dropdown,
                      tinted: false,
                      title: l10n.lorebookWizardPersonaNone,
                      value: _personaIdNow == null
                          ? Icon(
                              AppIcons.selected,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      chevron: false,
                      onTap: () => Navigator.of(sheet).pop(''),
                    ),
                    for (final preset in presets)
                      SettingsTile(
                        key: ValueKey('lorebook-persona-${preset.id}'),
                        icon: AppIcons.dropdown,
                        tinted: false,
                        title: preset.name,
                        value: preset.id == _personaIdNow
                            ? Icon(
                                AppIcons.selected,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        chevron: false,
                        onTap: () => Navigator.of(sheet).pop(preset.id),
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
    await ref
        .read(tavernSettingsProvider.notifier)
        .setBookPersona(picked.isEmpty ? null : picked);
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _makeBlueprint() async {
    final l10n = context.l10n;
    final idea = _idea.text.trim();
    if (idea.isEmpty) {
      setState(() => _error = l10n.lorebookWizardNeedIdea);
      return;
    }
    final scaleName = l10n.lorebookScaleName(switch (_scale) {
      1 => l10n.lorebookScaleSmall,
      3 => l10n.lorebookScaleLarge,
      _ => l10n.lorebookScaleMedium,
    });
    await _run(() async {
      final persona = await _personaText();
      final reply = await _ask(
        lorebookBlueprintMessages(
          idea: idea,
          kind: _kind,
          persona: persona,
          scale: scaleName,
        ),
        maxTokens: lorebookBlueprintTokens,
      );
      if (reply == null || !mounted) return;
      final blueprint = lorebookBlueprintParse(reply);
      if (blueprint == null) {
        setState(() => _error = context.l10n.studioAiNothing);
        return;
      }
      setState(() {
        _blueprint = blueprint;
        _plan = const [];
        _picked.clear();
        _written.clear();
        _issues = const [];
      });
    });
  }

  Future<void> _makePlan() async {
    final blueprint = _blueprint;
    if (blueprint == null) return;
    await _run(() async {
      final persona = await _personaText();
      final reply = await _ask(
        lorebookPlanMessages(
          blueprint: blueprint,
          target: _target,
          kind: _kind,
          persona: persona,
        ),
        maxTokens: lorebookPlanTokens(_target),
      );
      if (reply == null || !mounted) return;
      final plan = lorebookPlanParse(reply);
      if (plan.isEmpty) {
        // 到这一步还空，多半是请求层失败或者 JSON 真救不回来：说清楚，别只报「没生成」。
        setState(
          () => _error = reply.trim().isEmpty
              ? context.l10n.studioAiNothing
              : context.l10n.lorebookWizardPlanEmpty,
        );
        return;
      }
      setState(() {
        _plan = plan;
        _picked
          ..clear()
          ..addAll(plan.map((entry) => entry.title));
      });
    });
  }

  /// 分批写正文：一次最多 `_kind.batchSize` 条，一批一批来。
  Future<void> _writeEntries() async {
    final blueprint = _blueprint;
    if (blueprint == null) return;
    final targets = [
      for (final entry in _plan)
        if (_picked.contains(entry.title)) entry,
    ];
    if (targets.isEmpty) {
      setState(() => _error = context.l10n.lorebookWizardPickSome);
      return;
    }
    await _run(() async {
      final persona = await _personaText();
      final batchSize = _kind.batchSize;
      var missed = 0;
      for (var start = 0; start < targets.length; start += batchSize) {
        final batch = targets.skip(start).take(batchSize).toList();
        final reply = await _ask(
          lorebookBatchMessages(
            blueprint: blueprint,
            entries: batch,
            kind: _kind,
            persona: persona,
          ),
          maxTokens: _kind.batchTokens,
        );
        // 请求层自己就失败了（网络/额度）：_ask 已经摆了原因，整轮停。
        if (reply == null || !mounted) return;
        final written = lorebookBatchParse(reply);
        if (written.isEmpty) {
          // 这一批没写出来，后面的照写——不能因为第一批就交半本书。
          missed++;
          continue;
        }
        setState(() {
          for (final entry in written) {
            final title = entry.title.isEmpty ? batch.first.title : entry.title;
            _written.removeWhere((old) => old.title == title);
            _written.add(
              LorebookDraftEntry(
                title: title,
                content: entry.content,
                keys: entry.keys,
                constant: entry.constant,
              ),
            );
          }
        });
      }
      if (missed > 0 && mounted) {
        setState(() => _error = context.l10n.lorebookWizardBatchMissed(missed));
      }
    });
  }

  Future<void> _check() async {
    final blueprint = _blueprint;
    if (blueprint == null || _written.isEmpty) return;
    await _run(() async {
      final persona = await _personaText();
      final reply = await _ask(
        lorebookCheckMessages(
          blueprint: blueprint,
          entries: _written,
          kind: _kind,
          persona: persona,
        ),
        maxTokens: 900,
      );
      if (reply == null || !mounted) return;
      setState(() => _issues = lorebookCheckParse(reply));
    });
  }

  Future<void> _save() async {
    final blueprint = _blueprint;
    if (blueprint == null || _written.isEmpty) return;
    final l10n = context.l10n;
    await _run(() async {
      try {
        final id = newLorebookId();
        final json = {
          ...emptyLorebookJson(blueprint.name),
          'description': blueprint.overview,
          'entries': lorebookEntriesJson(_written),
        };
        await ref.read(tavernProvider).putLorebook(id, json);
        // 列表是另一个 provider：不一起刷新，回去会看到一本空列表。
        ref.invalidate(tavernLorebooksProvider);
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          briefNoticeBar(l10n.lorebookWizardSaved(blueprint.name)),
        );
        Navigator.of(context).pop();
      } on Object {
        if (mounted) setState(() => _error = l10n.lorebookWizardSaveFailed);
      }
    });
  }

  Future<void> _editEntry(int index) async {
    final entry = _written[index];
    final title = TextEditingController(text: entry.title);
    final keys = TextEditingController(text: entry.keys.join('，'));
    final content = TextEditingController(text: entry.content);
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.l10n.commonEdit),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('lorebook-wizard-entry-title'),
                controller: title,
                decoration: InputDecoration(
                  labelText: context.l10n.tavernLorebookFieldName,
                ),
              ),
              TextField(
                key: const ValueKey('lorebook-wizard-entry-keys'),
                controller: keys,
                decoration: InputDecoration(
                  labelText: context.l10n.tavernLorebookFieldKeys,
                ),
              ),
              TextField(
                key: const ValueKey('lorebook-wizard-entry-content'),
                controller: content,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: context.l10n.tavernLorebookFieldContent,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('lorebook-wizard-entry-ok'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(context.l10n.commonSave),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      title.dispose();
      keys.dispose();
      content.dispose();
      return;
    }
    setState(() {
      _written[index] = LorebookDraftEntry(
        title: title.text.trim().isEmpty ? entry.title : title.text.trim(),
        content: content.text.trim(),
        keys: [
          for (final key in keys.text.split(RegExp(r'[,，、]')))
            if (key.trim().isNotEmpty) key.trim(),
        ],
        constant: entry.constant,
      );
    });
    title.dispose();
    keys.dispose();
    content.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Stack(
      children: [
        AppPage.list(
          title: l10n.lorebookWizard,
          subtitle: Text(l10n.lorebookWizardSubtitle),
          children: [
            // 1. 创意
            SettingsSection(
              title: l10n.lorebookWizardStep1,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: FormFieldBlock(
                    key: const ValueKey('lorebook-wizard-idea'),
                    label: l10n.lorebookWizardIdea,
                    helper: l10n.lorebookWizardIdeaHelp,
                    child: TextField(
                      controller: _idea,
                      minLines: 2,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedPill<int>(
                      key: const ValueKey('lorebook-wizard-scale'),
                      expand: true,
                      segments: [
                        PillSegment(1, l10n.lorebookScaleSmall),
                        PillSegment(2, l10n.lorebookScaleMedium),
                        PillSegment(3, l10n.lorebookScaleLarge),
                      ],
                      selected: _scale,
                      onChanged: (scale) => setState(() => _scale = scale),
                    ),
                  ),
                ),
                SettingsTile(
                  key: const ValueKey('lorebook-wizard-kind'),
                  icon: AppIcons.article,
                  tinted: false,
                  title: l10n.lorebookWizardKind,
                  subtitle: _kindName(l10n, _kind),
                  onTap: _busy ? null : () => unawaited(_pickKind()),
                ),
                SettingsTile(
                  key: const ValueKey('lorebook-wizard-persona'),
                  icon: AppIcons.dropdown,
                  tinted: false,
                  title: l10n.lorebookWizardPersona,
                  subtitle: _personaName ?? l10n.lorebookWizardPersonaNone,
                  onTap: _busy ? null : () => unawaited(_pickPersona()),
                ),
                SettingsTile(
                  key: const ValueKey('lorebook-wizard-blueprint'),
                  icon: AppIcons.generateMedia,
                  tinted: false,
                  title: _blueprint == null
                      ? l10n.lorebookWizardMakeBlueprint
                      : l10n.lorebookWizardRemake,
                  chevron: false,
                  onTap: _busy ? null : () => unawaited(_makeBlueprint()),
                ),
              ],
            ),
            if (_blueprint case final blueprint?)
              SettingsSection(
                title: l10n.lorebookWizardStep2,
                children: [
                  SettingsTile(
                    key: const ValueKey('lorebook-wizard-blueprint-view'),
                    icon: AppIcons.article,
                    tinted: false,
                    title: blueprint.name,
                    subtitle: blueprint.overview,
                    chevron: false,
                  ),
                  for (final (label, items) in [
                    (l10n.lorebookWizardRules, blueprint.rules),
                    (l10n.lorebookWizardFactions, blueprint.factions),
                    (l10n.lorebookWizardPlaces, blueprint.places),
                    (l10n.lorebookWizardConflicts, blueprint.conflicts),
                  ])
                    if (items.isNotEmpty)
                      SettingsTile(
                        icon: AppIcons.info,
                        tinted: false,
                        title: label,
                        subtitle: items.join('、'),
                        chevron: false,
                      ),
                  SettingsTile(
                    key: const ValueKey('lorebook-wizard-plan'),
                    icon: AppIcons.article,
                    tinted: false,
                    title: _plan.isEmpty
                        ? l10n.lorebookWizardMakePlan
                        : l10n.lorebookWizardRemake,
                    subtitle: l10n.lorebookWizardPlanCount(_target),
                    chevron: false,
                    onTap: _busy ? null : () => unawaited(_makePlan()),
                  ),
                ],
              ),
            if (_plan.isNotEmpty)
              SettingsSection(
                title: l10n.lorebookWizardStep3,
                children: [
                  for (final entry in _plan)
                    SettingsTile(
                      key: ValueKey('lorebook-wizard-plan-${entry.title}'),
                      icon: AppIcons.selected,
                      tinted: false,
                      title: entry.title,
                      subtitle: entry.why.isEmpty ? entry.kind : entry.why,
                      trailing: Checkbox(
                        value: _picked.contains(entry.title),
                        onChanged: (on) => setState(() {
                          if (on == true) {
                            _picked.add(entry.title);
                          } else {
                            _picked.remove(entry.title);
                          }
                        }),
                      ),
                      onTap: () => setState(() {
                        if (!_picked.remove(entry.title)) {
                          _picked.add(entry.title);
                        }
                      }),
                    ),
                  SettingsTile(
                    key: const ValueKey('lorebook-wizard-write'),
                    icon: AppIcons.generateMedia,
                    tinted: false,
                    title: l10n.lorebookWizardWrite,
                    subtitle: l10n.lorebookWizardWriteHint(_kind.batchSize),
                    chevron: false,
                    onTap: _busy ? null : () => unawaited(_writeEntries()),
                  ),
                ],
              ),
            if (_written.isNotEmpty)
              SettingsSection(
                title: l10n.lorebookWizardStep4,
                children: [
                  for (final (index, entry) in _written.indexed)
                    SettingsTile(
                      key: ValueKey('lorebook-wizard-entry-${entry.title}'),
                      icon: AppIcons.lorebook,
                      tinted: false,
                      title: entry.title,
                      subtitle: entry.keys.join('、'),
                      onTap: _busy ? null : () => unawaited(_editEntry(index)),
                      trailing: IconButton(
                        key: ValueKey('lorebook-wizard-drop-${entry.title}'),
                        icon: const Icon(AppIcons.delete, size: 18),
                        onPressed: _busy
                            ? null
                            : () => setState(() => _written.removeAt(index)),
                      ),
                    ),
                  SettingsTile(
                    key: const ValueKey('lorebook-wizard-check'),
                    icon: AppIcons.info,
                    tinted: false,
                    title: l10n.lorebookWizardCheck,
                    chevron: false,
                    onTap: _busy ? null : () => unawaited(_check()),
                  ),
                  for (final issue in _issues)
                    SettingsTile(
                      icon: AppIcons.info,
                      tinted: false,
                      title: issue.title.isEmpty
                          ? l10n.lorebookWizardIssue
                          : issue.title,
                      subtitle: issue.suggest.isEmpty
                          ? issue.issue
                          : '${issue.issue}\n${issue.suggest}',
                      chevron: false,
                    ),
                  if (_issues.isEmpty)
                    SettingsTile(
                      icon: AppIcons.selected,
                      tinted: false,
                      title: l10n.lorebookWizardNoIssues,
                      chevron: false,
                    ),
                  SettingsTile(
                    key: const ValueKey('lorebook-wizard-save'),
                    icon: AppIcons.done,
                    tinted: false,
                    title: l10n.lorebookWizardSave(_written.length),
                    chevron: false,
                    onTap: _busy ? null : () => unawaited(_save()),
                  ),
                ],
              ),
            if (_error case final message?)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Text(
                  message,
                  key: const ValueKey('lorebook-wizard-error'),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: DshColors.of(context).danger),
                ),
              ),
            const SizedBox(height: FormBottomBar.height * 2),
          ],
        ),
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(color: Colors.black12, child: QuietSpinner()),
          ),
      ],
    );
  }
}
