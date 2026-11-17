// 专业创作：九个模块，逐字段写，写完由转换器折成一张卡。
//
// 字段级 AI 已接上（规格 §1.5）：每格右上角 ✨ 给五个动作（补全/扩写/精简/
// 重写/检查），模块页右上角是整模块生成。AI **永远先给候选**：旧的和新的并排，
// 采用才写；锁定字段在解析层就被过滤掉，进不了提议。
//
// 页面结构照规格：模块列表（进度）→ 模块子页（字段）→ 预览 → 存进书架。

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../tavern/studio_store.dart';
import '../../tavern/tavern_provider.dart';
import '../../tavern/tavern_session_usage.dart';
import '../../tavern/tavern_studio_ai.dart';
import '../../tavern/tavern_studio_build.dart';
import '../../tavern/tavern_studio_draft.dart';
import '../../tavern/tavern_studio_schema.dart';
import '../common/app_dialog.dart';
import '../common/app_sheet.dart';
import '../common/sheet_title_bar.dart';
import '../providers/provider_widgets.dart';
import '../settings/settings_widgets.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import '../state/state_templates_page.dart' show stateTemplatesProvider;
import 'tavern_character_page.dart';

class TavernStudioPage extends ConsumerStatefulWidget {
  const TavernStudioPage({
    super.key,
    this.initial,
    this.characterId,
    this.idea,
  });

  /// 一份现成的草稿；null 表示从本地未存草稿接上（或者空着开）。
  final StudioDraft? initial;

  /// 绑到一张已有的卡：草稿从卡里读，存回去也是这张卡。
  final String? characterId;
  final String? idea;

  static Route<void> route({
    StudioDraft? initial,
    String? characterId,
    String? idea,
  }) => MaterialPageRoute<void>(
    builder: (_) => TavernStudioPage(
      initial: initial,
      characterId: characterId,
      idea: idea,
    ),
  );

  @override
  ConsumerState<TavernStudioPage> createState() => _TavernStudioPageState();
}

class _TavernStudioPageState extends ConsumerState<TavernStudioPage> {
  late StudioDraft _draft = widget.initial?.copy() ?? StudioDraft();
  var _saving = false;
  var _loaded = false;

  /// 绑卡时读到的原卡字段：AI 生成时作为「原卡内容」整段给模型，防止写跑题。
  Map<String, Object?>? _cardData;

  /// 「我想要的角色」：进不了卡，但每次 AI 生成都跟着走（`StudioDraft.idea`）。
  final _ideaController = TextEditingController();

  /// 打字时别每按一个键就写一次盘：停手 800ms 再存。
  Timer? _ideaSave;

  @override
  void initState() {
    super.initState();
    _ideaController.text = _draft.idea;
    unawaited(_restore());
  }

  @override
  void dispose() {
    _ideaSave?.cancel();
    _ideaController.dispose();
    super.dispose();
  }

  bool get _bound => widget.characterId != null;

  /// 打开时把草稿接上：绑卡就从卡里读，没绑就读本地那份没存的。
  Future<void> _restore() async {
    if (widget.initial != null) {
      setState(() {
        if (widget.idea?.trim().isNotEmpty == true)
          _draft.idea = widget.idea!.trim();
        _ideaController.text = _draft.idea;
        _loaded = true;
      });
      return;
    }
    // initState ???? Localizations??????? BuildContext ????
    final l10n = appL10n;
    try {
      final StudioDraft? draft;
      if (_bound) {
        final tavern = ref.read(tavernProvider);
        final fromCard = await loadStudioDraftFromCard(
          tavern,
          widget.characterId!,
        );
        // 原卡的原文留着：AI 生成时整段喂进去，免得写出来的东西和这张卡对不上。
        final cardData = await tavern.characterFields(widget.characterId!);
        _cardData = cardData;
        draft = fromCard.isEmpty
            ? studioDraftFromCardData(cardData)
            : fromCard;
      } else {
        draft = await (await ref.read(studioDraftStoreProvider.future)).read();
      }
      if (!mounted) return;
      setState(() {
        _draft = draft ?? StudioDraft();
        if (widget.idea?.trim().isNotEmpty == true)
          _draft.idea = widget.idea!.trim();
        _ideaController.text = _draft.idea;
        _loaded = true;
      });
      unawaited(_autosave());
    } on Object {
      if (!mounted) return;
      setState(() => _loaded = true);
      _say(l10n.studioRestoreFailed);
    }
  }

  /// 没存成卡之前，本地留一份：关掉页面再回来能接上。
  Future<void> _autosave() async {
    if (_bound || !_loaded) return;
    try {
      final store = await ref.read(studioDraftStoreProvider.future);
      await store.write(_draft);
    } on Object {
      // 存不下就算了，别拿它烦用户。
    }
  }

  Future<void> _open(String moduleId) async {
    await Navigator.of(context).push(
      TavernStudioModulePage.route(
        _draft,
        moduleId,
        sourceCard: _cardData,
      ),
    );
    if (!mounted) return;
    setState(() {});
    unawaited(_autosave());
  }

  /// 预览：先看转换器到底写出什么，再决定存不存。
  Future<void> _preview() async {
    final l10n = context.l10n;
    final missing = [
      for (final field
          in studioModule('profile')?.fields ?? const <StudioFieldSpec>[])
        if (field.required && _draft.text('profile', field.key).trim().isEmpty)
          studioFieldLabel('profile', field.key, l10n),
    ];
    if (missing.isNotEmpty) {
      _say(l10n.studioMissingRequired(missing.join('、')));
      return;
    }
    final Map<String, Object?> card;
    try {
      card = buildStudioCard(_draft, creator: l10n.tavernCardStudioTitle);
    } on StudioBuildError catch (e) {
      _say(l10n.studioTooLong(e.descriptionChars, e.cap));
      return;
    }
    final data = card['data']! as Map<String, Object?>;
    final entries =
        ((data['character_book'] as Map?)?['entries'] as List?)?.length ?? 0;
    await showAppSheet<void>(
      context,
      heightFactor: 0.8,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(l10n.studioPreview),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      data['name']! as String,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _previewBlock(
                      l10n.studioTotalChars(
                        (data['description']! as String).length,
                      ),
                      null,
                    ),
                    _previewBlock(
                      l10n.tavernFieldDescription,
                      data['description']! as String,
                    ),
                    _previewBlock(
                      l10n.tavernFieldPersonality,
                      data['personality']! as String,
                    ),
                    _previewBlock(
                      l10n.tavernFieldScenario,
                      data['scenario']! as String,
                    ),
                    _previewBlock(
                      l10n.tavernGreetingNumber(1),
                      data['first_mes']! as String,
                    ),
                    _previewBlock(
                      l10n.tavernFieldExamples,
                      data['mes_example']! as String,
                    ),
                    _previewBlock(l10n.studioBookCount(entries), null),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: FilledButton(
                key: const ValueKey('studio-save'),
                onPressed: () {
                  Navigator.of(sheet).pop();
                  unawaited(_save());
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(
                  _bound ? l10n.studioSaveToCard : l10n.studioSaveAsCard,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewBlock(String label, String? body) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: DshColors.of(context).textTertiary),
        ),
        if (body != null && body.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    ),
  );

  Future<void> _save() async {
    if (_saving) return;
    final l10n = context.l10n;
    setState(() => _saving = true);
    try {
      final card = buildStudioCard(_draft, creator: l10n.tavernCardStudioTitle);
      if (_bound) {
        await _saveIntoCard(widget.characterId!, card);
        if (!mounted) return;
        _say(l10n.studioSavedToCard);
        Navigator.of(context).pop();
        return;
      }
      final character = await ref
          .read(tavernProvider)
          .importCard(
            Uint8List.fromList(utf8.encode(jsonEncode(card))),
            fileName: 'studio_card.json',
          );
      // 存进卡了，本地那份没用的草稿清掉。
      try {
        await (await ref.read(studioDraftStoreProvider.future)).clear();
      } on Object {
        // 清不掉不影响这张卡。
      }
      if (!mounted) return;
      _say(l10n.tavernCardStudioSaved(character.name));
      unawaited(
        Navigator.of(context)
            .pushReplacement(TavernCharacterPage.route(character.id)),
      );
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      _say(l10n.studioSaveFailed);
    }
  }

  /// 存回已有的卡：正文走 updateCharacterFields，书里缺的条目逐条补，
  /// 草稿进 extensions（同一命名空间下的 state 由引擎保住）。
  Future<void> _saveIntoCard(
    String characterId,
    Map<String, Object?> card,
  ) async {
    final tavern = ref.read(tavernProvider);
    final data = card['data']! as Map<String, Object?>;
    await tavern.updateCharacterFields(characterId, {
      for (final key in const [
        'name',
        'description',
        'personality',
        'scenario',
        'first_mes',
        'mes_example',
        'creator_notes',
        'system_prompt',
        'post_history_instructions',
        'alternate_greetings',
        'tags',
      ])
        if (data[key] != null) key: data[key]!,
    });
    // 卡片书里没有的条目才补：按标题判重，免得存一次多一批。
    final fields = await tavern.characterFields(characterId);
    final existing = studioBookTitles(fields);
    for (final entry in studioEntriesMissingFrom(_draft.book, existing)) {
      await tavern.addCharacterBookEntry(characterId, {
        'comment': entry.title,
        'keys': entry.keys,
        'content': entry.content,
        'constant': entry.constant,
        'enabled': true,
        'position': entry.constant ? 'before_char' : 'after_char',
        'insertion_order': 100,
        'selective': false,
        'use_regex': false,
      });
    }
    await saveStudioDraftToCard(tavern, characterId, _draft);
  }

  /// ????????????? / N ??
  String _stateSummary(L10n l10n) {
    final state = _draft.state;
    final properties = state?['schema'];
    final fields = properties is Map ? properties['properties'] : null;
    if (fields is! Map || fields.isEmpty) return l10n.studioStateNone;
    return l10n.studioStateFields(fields.length);
  }

  /// ????????????? AI ???????????????
  Future<void> _pickState() async {
    final l10n = context.l10n;
    final templates = await ref.read(stateTemplatesProvider.future);
    if (!mounted) return;
    final choice = await showAppSheet<String>(
      context,
      heightFactor: 0.7,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(l10n.studioState),
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
                    for (final template in templates)
                      SettingsTile(
                        key: ValueKey('studio-state-${template.id}'),
                        icon: AppIcons.chart,
                        tinted: false,
                        title: l10n.studioStatePick(template.name),
                        subtitle: l10n.studioStateFields(
                          template.fields.length,
                        ),
                        chevron: false,
                        onTap: () =>
                            Navigator.of(sheet).pop('tpl:${template.id}'),
                      ),
                    SettingsTile(
                      key: const ValueKey('studio-state-ai'),
                      icon: AppIcons.generateMedia,
                      tinted: false,
                      title: l10n.studioStateAi,
                      subtitle: l10n.studioStateAiSubtitle,
                      chevron: false,
                      onTap: () => Navigator.of(sheet).pop('ai'),
                    ),
                    if (_draft.state != null)
                      SettingsTile(
                        key: const ValueKey('studio-state-clear'),
                        icon: AppIcons.delete,
                        tinted: false,
                        danger: true,
                        title: l10n.studioStateClear,
                        chevron: false,
                        onTap: () => Navigator.of(sheet).pop('clear'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() {
      if (choice == 'clear') {
        _draft.state = null;
        return;
      }
      if (choice.startsWith('tpl:')) {
        final id = choice.substring(4);
        for (final template in templates) {
          if (template.id == id) _draft.state = template.toState();
        }
      }
    });
    if (choice == 'ai') await _askStateAi();
    unawaited(_autosave());
  }

  /// ? AI ???????????????????????
  Future<void> _askStateAi() async {
    final l10n = context.l10n;
    if (_saving) return;
    setState(() => _saving = true);
    final client = ref.read(tavernModelClientProvider);
    final config = ref.read(tavernModelConfigProvider);
    final buffer = StringBuffer();
    Object? failure;
    try {
      await for (final delta in client.generate(
        config: config,
        body: studioAiBody(
          draft: _draft,
          module: 'profile',
          action: StudioAiAction.state,
          english: AppLocale.isEnglish,
          label: (key) => studioFieldLabel('profile', key, context.l10n),
        ),
        cancellation: ModelCancellation(),
      )) {
        if (delta is ModelText) buffer.write(delta.text);
      }
    } on Object catch (e) {
      failure = e;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (failure != null) {
      _say(l10n.studioAiFailed);
      return;
    }
    final template = studioAiParse(
      buffer.toString(),
      draft: _draft,
      module: 'profile',
      action: StudioAiAction.state,
    ).stateTemplate;
    if (template == null) {
      _say(l10n.studioAiNothing);
      return;
    }
    final adopt = await showAppSheet<bool>(
      context,
      heightFactor: 0.8,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(l10n.studioStateAi),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final field in template.fields)
                      Padding(
                        key: ValueKey('studio-state-proposal-${field.key}'),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              field.title,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              '${field.key} ? ?? ${field.toInitial()}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: DshColors.of(context).textTertiary,
                                  ),
                            ),
                          ],
                        ),
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
                      key: const ValueKey('studio-state-adopt'),
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
    if (adopt == true && mounted) {
      setState(() => _draft.state = template.toState());
      unawaited(_autosave());
    }
  }

  /// ????????????????????????
  Future<void> _simulate() async {
    final l10n = context.l10n;
    if (_saving) return;
    final client = ref.read(tavernModelClientProvider);
    final config = ref.read(tavernModelConfigProvider);
    final cancel = ModelCancellation();
    setState(() => _saving = true);
    final buffer = StringBuffer();
    Object? failure;
    try {
      await for (final delta in client.generate(
        config: config,
        body: studioAiBody(
          draft: _draft,
          module: 'voice',
          action: StudioAiAction.simulate,
          english: AppLocale.isEnglish,
          label: (key) => studioFieldLabel('voice', key, context.l10n),
        ),
        cancellation: cancel,
      )) {
        if (delta is ModelText) buffer.write(delta.text);
      }
    } on Object catch (e) {
      failure = e;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (failure != null) {
      _say(l10n.studioAiFailed);
      return;
    }
    final scenes = studioAiParse(
      buffer.toString(),
      draft: _draft,
      module: 'voice',
      action: StudioAiAction.simulate,
    ).scenes;
    if (scenes.isEmpty) {
      _say(l10n.studioAiNothing);
      return;
    }
    await showAppSheet<void>(
      context,
      heightFactor: 0.85,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(l10n.studioSimulate),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final scene in scenes)
                      Padding(
                        key: ValueKey('studio-scene-${scene.title}'),
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              scene.title,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: DshColors.of(context).textTertiary,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              scene.reply,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: OutlinedButton(
                onPressed: () => Navigator.of(sheet).pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                child: Text(l10n.commonDone),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _say(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Stack(
      children: [
        AppPage.list(
          title: l10n.studioTitle,
          subtitle: Text(l10n.studioSubtitle),
          children: [
            // 「我想要的角色」放在最上面：它不进卡，但每次 AI 生成都按它来。
            SettingsSection(
              title: l10n.studioIdeaTitle,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: FormFieldBlock(
                    key: const ValueKey('studio-idea'),
                    label: l10n.studioIdeaTitle,
                    helper: l10n.studioIdeaHint,
                    child: TextField(
                      controller: _ideaController,
                      minLines: 2,
                      maxLines: 4,
                      enabled: !_saving,
                      onChanged: (text) {
                        _draft.idea = text;
                        _ideaSave?.cancel();
                        _ideaSave = Timer(
                          const Duration(milliseconds: 800),
                          () => unawaited(_autosave()),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            for (final module in studioModules)
              SettingsSection(
                children: [
                  SettingsTile(
                    key: ValueKey('studio-module-${module.id}'),
                    icon: AppIcons.article,
                    tinted: false,
                    title: studioModuleLabel(module.id, l10n),
                    subtitle: studioModuleSubtitle(module.id, l10n),
                    value: Text(_progress(module)),
                    onTap: _saving ? null : () => unawaited(_open(module.id)),
                  ),
                ],
              ),
            SettingsSection(
              children: [
                SettingsTile(
                  key: const ValueKey('studio-state'),
                  icon: AppIcons.chart,
                  tinted: false,
                  title: l10n.studioState,
                  subtitle: _stateSummary(l10n),
                  onTap: _saving ? null : () => unawaited(_pickState()),
                ),
              ],
            ),
            SettingsSection(
              children: [
                SettingsTile(
                  key: const ValueKey('studio-simulate'),
                  icon: AppIcons.play,
                  tinted: false,
                  title: l10n.studioSimulate,
                  subtitle: l10n.studioSimulateSubtitle,
                  onTap: _saving ? null : () => unawaited(_simulate()),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(
                l10n.studioHint,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: DshColors.of(context).textTertiary),
              ),
            ),
            const SizedBox(height: FormBottomBar.height),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.viewInsetsOf(context).bottom,
          child: FormBottomBar(
            child: FilledButton.icon(
              key: const ValueKey('studio-preview'),
              onPressed: _saving ? null : () => unawaited(_preview()),
              icon: const Icon(AppIcons.code, size: 18),
              label: Text(l10n.studioPreviewAction),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _progress(StudioModuleSpec module) {
    final filled = module.fields.where((field) {
      final value = _draft.peek(module.id, field.key);
      return value != null && !value.isEmpty;
    }).length;
    return '$filled/${module.fields.length}';
  }
}

class TavernStudioModulePage extends ConsumerStatefulWidget {
  const TavernStudioModulePage({
    super.key,
    required this.draft,
    required this.moduleId,
    this.sourceCard,
  });

  final StudioDraft draft;
  final String moduleId;

  /// 绑卡时原卡的正文：字段级 ✨ 也要看得见它，否则写出来和这张卡对不上。
  final Map<String, Object?>? sourceCard;

  static Route<void> route(
    StudioDraft draft,
    String moduleId, {
    Map<String, Object?>? sourceCard,
  }) => MaterialPageRoute<void>(
    builder: (_) => TavernStudioModulePage(
      draft: draft,
      moduleId: moduleId,
      sourceCard: sourceCard,
    ),
  );

  @override
  ConsumerState<TavernStudioModulePage> createState() =>
      _TavernStudioModulePageState();
}

class _TavernStudioModulePageState
    extends ConsumerState<TavernStudioModulePage> {
  final _controllers = <String, TextEditingController>{};

  /// 正在跑 AI 的字段；`*` 表示整模块。null 就是没在跑。
  String? _aiField;
  ModelCancellation? _cancel;
  String? _error;

  StudioModuleSpec get _module => studioModule(widget.moduleId)!;

  bool get _busy => _aiField != null;

  @override
  void dispose() {
    _cancel?.cancel();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(String field) => _controllers.putIfAbsent(
    field,
    () =>
        TextEditingController(text: widget.draft.text(widget.moduleId, field)),
  );

  // ── AI ────────────────────────────────────────────────────────────────────

  Future<void> _askFor(String field) async {
    final l10n = context.l10n;
    if (widget.draft.peek(widget.moduleId, field)?.locked == true) {
      _say(l10n.studioAiLocked);
      return;
    }
    final action = await _pickAction(field);
    if (action == null || !mounted) return;
    var instruction = '';
    if (action == StudioAiAction.rewrite) {
      final asked = await _askInstruction();
      // ?????????????????????????????
      if (asked == null || !mounted) return;
      instruction = asked;
    }
    await _run(action, field: field, instruction: instruction);
  }

  Future<void> _askModule() async {
    final action = await _pickAction(null);
    if (action == null || !mounted) return;
    await _run(action, field: null);
  }

  /// 五种动作里挑一个；整模块还多「生成世界书条目」（只在本来就该进书的模块里给）。
  Future<StudioAiAction?> _pickAction(String? field) async {
    final l10n = context.l10n;
    const bookish = {'history', 'world', 'bond', 'rules'};
    final items = field == null
        ? [
            StudioAiAction.wholeModule,
            StudioAiAction.check,
            if (bookish.contains(widget.moduleId)) StudioAiAction.book,
          ]
        : const [
            StudioAiAction.fill,
            StudioAiAction.expand,
            StudioAiAction.trim,
            StudioAiAction.rewrite,
            StudioAiAction.check,
          ];
    return showAppSheet<StudioAiAction>(
      context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(l10n.studioAiActions),
            SheetGroup(
              margin: const EdgeInsets.fromLTRB(
                SheetTitleBar.inset,
                0,
                SheetTitleBar.inset,
                12,
              ),
              children: [
                for (final action in items)
                  SettingsTile(
                    key: ValueKey('studio-ai-${action.name}'),
                    icon: switch (action) {
                      StudioAiAction.fill => AppIcons.generateMedia,
                      StudioAiAction.expand => AppIcons.add,
                      StudioAiAction.trim => AppIcons.remove,
                      StudioAiAction.rewrite => AppIcons.edit,
                      StudioAiAction.check => AppIcons.info,
                      StudioAiAction.wholeModule => AppIcons.generateMedia,
                      StudioAiAction.book => AppIcons.lorebook,
                      StudioAiAction.simulate => AppIcons.play,
                      StudioAiAction.state => AppIcons.chart,
                    },
                    tinted: false,
                    title: _actionTitle(action, l10n),
                    subtitle: _actionSubtitle(action, l10n),
                    chevron: false,
                    onTap: () => Navigator.of(sheet).pop(action),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _actionTitle(StudioAiAction action, L10n l10n) => switch (action) {
    StudioAiAction.fill => l10n.studioAiFill,
    StudioAiAction.expand => l10n.studioAiExpand,
    StudioAiAction.trim => l10n.studioAiTrim,
    StudioAiAction.rewrite => l10n.studioAiRewrite,
    StudioAiAction.check => l10n.studioAiCheck,
    StudioAiAction.wholeModule => l10n.studioAiWholeModule,
    StudioAiAction.book => l10n.studioAiBook,
    StudioAiAction.simulate => l10n.studioSimulate,
    StudioAiAction.state => l10n.studioStateAi,
  };

  String _actionSubtitle(StudioAiAction action, L10n l10n) => switch (action) {
    StudioAiAction.fill => l10n.studioAiFillSubtitle,
    StudioAiAction.expand => l10n.studioAiExpandSubtitle,
    StudioAiAction.trim => l10n.studioAiTrimSubtitle,
    StudioAiAction.rewrite => l10n.studioAiRewriteSubtitle,
    StudioAiAction.check => l10n.studioAiCheckSubtitle,
    StudioAiAction.wholeModule => l10n.studioAiWholeSubtitle,
    StudioAiAction.book => l10n.studioAiBookSubtitle,
    StudioAiAction.simulate => l10n.studioSimulateSubtitle,
    StudioAiAction.state => l10n.studioStateAiSubtitle,
  };

  /// 跑一次：组装提示、真调一次传输、解析、给候选。**不直接写入**。
  Future<void> _run(
    StudioAiAction action, {
    String? field,
    String instruction = '',
  }) async {
    final l10n = context.l10n;
    if (_busy) return;
    final config = ref.read(tavernModelConfigProvider);
    final client = ref.read(tavernModelClientProvider);
    final cancel = ModelCancellation();
    setState(() {
      _aiField = field ?? '*';
      _cancel = cancel;
      _error = null;
    });
    final buffer = StringBuffer();
    TavernUsage? usage;
    Object? failure;
    try {
      await for (final delta in client.generate(
        config: config,
        body: studioAiBody(
          draft: widget.draft,
          module: widget.moduleId,
          field: field,
          action: action,
          instruction: instruction,
          idea: widget.draft.idea,
          sourceCard: widget.sourceCard,
          english: AppLocale.isEnglish,
          label: (key) => studioFieldLabel(widget.moduleId, key, context.l10n),
        ),
        cancellation: cancel,
      )) {
        if (delta is ModelText) {
          buffer.write(delta.text);
        } else if (delta is ModelUsage) {
          usage = delta.usage;
        }
      }
    } on TavernModelException catch (e) {
      if (e.kind != TavernFailure.cancelled) failure = e;
    } on Object catch (e) {
      failure = e;
    }
    if (!mounted) return;
    setState(() {
      _aiField = null;
      _cancel = null;
    });
    if (failure != null) {
      _say(l10n.studioAiFailed);
      return;
    }
    final proposal = studioAiParse(
      buffer.toString(),
      draft: widget.draft,
      module: widget.moduleId,
      field: field,
      action: action,
      // ????????????????????? identity?
      label: (key) => studioFieldLabel(widget.moduleId, key, context.l10n),
    );
    if (proposal.isEmpty) {
      _say(l10n.studioAiNothing);
      return;
    }
    final adopted = await _showProposal(proposal, action: action, usage: usage);
    if (adopted != true || !mounted) return;
    setState(() {
      studioAiApply(
        widget.draft,
        widget.moduleId,
        proposal,
        onlyEmpty: action == StudioAiAction.wholeModule,
      );
      // 文本框自己拿着 controller，写完要把它同步过来。
      for (final entry in _controllers.entries) {
        entry.value.text = widget.draft.text(widget.moduleId, entry.key);
      }
    });
  }

  void _say(String text) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  /// 重写要一句要求。
  Future<String?> _askInstruction() => showAppDialog<String>(
    context: context,
    builder: (_) => const _InstructionDialog(),
  );

  /// 候选：旧的和新的并排（整模块就一条一条列），采用才写。
  Future<bool?> _showProposal(
    StudioAiProposal proposal, {
    required StudioAiAction action,
    TavernUsage? usage,
  }) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final usageLine = _usageLine(usage, l10n);
    return showAppSheet<bool>(
      context,
      heightFactor: 0.85,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(
              action == StudioAiAction.check
                  ? l10n.studioAiIssues
                  : l10n.studioAiProposal,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (proposal.issues.isNotEmpty)
                      for (final issue in proposal.issues)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                studioFieldLabel(
                                  widget.moduleId,
                                  issue.field,
                                  l10n,
                                ),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: dsh.textTertiary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                issue.issue,
                                style: theme.textTheme.bodyMedium,
                              ),
                              if (issue.suggest.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    issue.suggest,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: dsh.textTertiary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    for (final entry in proposal.fields.entries)
                      _proposalBlock(entry.key, entry.value),
                    for (final entry in proposal.entries) _entryBlock(entry),
                    if (usageLine != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          usageLine,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: dsh.textTertiary,
                          ),
                        ),
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
                      key: const ValueKey('studio-ai-discard'),
                      onPressed: () => Navigator.of(sheet).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                      child: Text(l10n.studioAiDiscard),
                    ),
                  ),
                  if (proposal.fields.isNotEmpty ||
                      proposal.entries.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('studio-ai-adopt'),
                        onPressed: () => Navigator.of(sheet).pop(true),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                        child: Text(l10n.studioAiAdopt),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一条世界书条目的候选：标题、关键词、正文，常驻会标出来。
  Widget _entryBlock(StudioBookEntry entry) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    return Padding(
      key: ValueKey('studio-ai-entry-${entry.title}'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.title.isEmpty ? '—' : entry.title,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (entry.constant)
                Text(
                  context.l10n.studioBookConstant,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
          if (entry.keys.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                entry.keys.join('、'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: dsh.textTertiary,
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(entry.content, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _proposalBlock(String field, String next) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final was = widget.draft.text(widget.moduleId, field).trim();
    return Padding(
      key: ValueKey('studio-ai-proposal-$field'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            studioFieldLabel(widget.moduleId, field, l10n),
            style: theme.textTheme.labelMedium?.copyWith(
              color: dsh.textTertiary,
            ),
          ),
          if (was.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              was,
              style: theme.textTheme.bodySmall?.copyWith(
                color: dsh.textDisabled,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(next, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  String? _usageLine(TavernUsage? usage, L10n l10n) {
    if (usage == null) return null;
    final tokens = usage.promptTokens + usage.completionTokens;
    if (tavernModelPrice(usage.model) case final price?) {
      return l10n.studioAiUsage(
        tokens,
        tavernCny(tavernReplyCost(usage, price, DateTime.now())),
      );
    }
    return l10n.studioAiUsageTokens(tokens);
  }

  // ── 页面 ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppPage.list(
      title: studioModuleLabel(widget.moduleId, l10n),
      subtitle: Text(studioModuleSubtitle(widget.moduleId, l10n)),
      actions: [
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: DshColors.of(context).textTertiary,
              ),
            ),
          )
        else
          GlassIconButton(
            key: const ValueKey('studio-ai-module'),
            icon: AppIcons.generateMedia,
            tooltip: l10n.studioAiWholeModule,
            onPressed: () => unawaited(_askModule()),
          ),
      ],
      children: [
        if (_error case final message?)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: DshColors.of(context).danger),
            ),
          ),
        SettingsSection(
          children: [
            for (final field in _module.fields) _fieldRow(context, l10n, field),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.draft.book.isNotEmpty)
                Padding(
                  key: const ValueKey('studio-book-count'),
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    l10n.studioBookCount(widget.draft.book.length),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              Text(
                l10n.studioFieldHint,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: DshColors.of(context).textTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fieldRow(BuildContext context, L10n l10n, StudioFieldSpec field) {
    final value = widget.draft.peek(widget.moduleId, field.key);
    final locked = value?.locked ?? false;
    final running = _aiField == field.key;
    return Padding(
      key: ValueKey('studio-field-${field.key}'),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FormFieldLabel(
                  studioFieldLabel(widget.moduleId, field.key, l10n) +
                      (field.required ? ' *' : ''),
                ),
              ),
              // ✨：让 AI 写这一格。锁着就不给点，跑着就转圈。
              if (running)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  key: ValueKey('studio-ai-${field.key}'),
                  tooltip: locked ? l10n.studioAiLocked : l10n.studioAiActions,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    AppIcons.generateMedia,
                    size: 18,
                    color: locked
                        ? DshColors.of(context).textDisabled
                        : Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: _busy ? null : () => unawaited(_askFor(field.key)),
                ),
              IconButton(
                key: ValueKey('studio-lock-${field.key}'),
                tooltip: locked ? l10n.studioUnlock : l10n.studioLock,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  locked ? AppIcons.lock : AppIcons.unlock,
                  size: 18,
                  color: locked
                      ? Theme.of(context).colorScheme.primary
                      : DshColors.of(context).textTertiary,
                ),
                onPressed: () => setState(
                  () => widget.draft.toggleLock(widget.moduleId, field.key),
                ),
              ),
              IconButton(
                key: ValueKey('studio-undo-${field.key}'),
                tooltip: l10n.studioUndo,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  AppIcons.restart,
                  size: 18,
                  color: widget.draft.canUndo(widget.moduleId, field.key)
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : DshColors.of(context).textDisabled,
                ),
                onPressed: widget.draft.canUndo(widget.moduleId, field.key)
                    ? () => setState(() {
                        widget.draft.undo(widget.moduleId, field.key);
                        _controller(field.key).text = widget.draft.text(
                          widget.moduleId,
                          field.key,
                        );
                      })
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: switch (field.control) {
              StudioControl.line => TextField(
                controller: _controller(field.key),
                onChanged: _writeText(field.key),
                textInputAction: TextInputAction.next,
              ),
              StudioControl.block => TextField(
                controller: _controller(field.key),
                onChanged: _writeText(field.key),
                minLines: 3,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
              ),
              StudioControl.tags => _TagsField(
                key: ValueKey('studio-tags-${field.key}'),
                items: widget.draft.items(widget.moduleId, field.key),
                onChanged: (items) => setState(
                  () =>
                      widget.draft.setItems(widget.moduleId, field.key, items),
                ),
              ),
              StudioControl.list => _ListField(
                key: ValueKey('studio-list-${field.key}'),
                items: widget.draft.items(widget.moduleId, field.key),
                onChanged: (items) => setState(
                  () =>
                      widget.draft.setItems(widget.moduleId, field.key, items),
                ),
              ),
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 8, bottom: 8),
            child: Text(
              l10n.studioBudget(field.budget),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: DshColors.of(context).textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  ValueChanged<String> _writeText(String field) => (text) {
    widget.draft.setText(widget.moduleId, field, text);
    setState(() {});
  };
}

/// 重写前问一句要求。controller 归对话框自己管，退场动画走完才释放。
class _InstructionDialog extends StatefulWidget {
  const _InstructionDialog();

  @override
  State<_InstructionDialog> createState() => _InstructionDialogState();
}

class _InstructionDialogState extends State<_InstructionDialog> {
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
      title: Text(l10n.studioAiRewrite),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: l10n.studioAiInstruction,
          hintText: l10n.studioAiInstructionHint,
        ),
        onSubmitted: (text) => Navigator.of(context).pop(text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('studio-ai-instruction-ok'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.commonDone),
        ),
      ],
    );
  }
}

/// 标签：一颗颗可点的胶囊，最后一个是"加一个"。
class _TagsField extends StatefulWidget {
  const _TagsField({super.key, required this.items, required this.onChanged});

  final List<String> items;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_TagsField> createState() => _TagsFieldState();
}

class _TagsFieldState extends State<_TagsField> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    widget.onChanged([...widget.items, text]);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (index, item) in widget.items.indexed)
              InputChip(
                label: Text(item),
                onDeleted: () =>
                    widget.onChanged([...widget.items]..removeAt(index)),
                deleteIcon: const Icon(AppIcons.close, size: 14),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _input,
          onSubmitted: (_) => _add(),
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: l10n.studioAddTag,
            suffixIcon: IconButton(
              icon: const Icon(AppIcons.add, size: 18),
              onPressed: _add,
            ),
          ),
        ),
      ],
    );
  }
}

/// 列表：一行一条，长的能多行，可以删、可以加。
class _ListField extends StatefulWidget {
  const _ListField({super.key, required this.items, required this.onChanged});

  final List<String> items;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_ListField> createState() => _ListFieldState();
}

class _ListFieldState extends State<_ListField> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, item) in widget.items.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: ObjectKey(item),
                    initialValue: item,
                    minLines: 1,
                    maxLines: 4,
                    onChanged: (text) {
                      final next = [...widget.items];
                      next[index] = text;
                      widget.onChanged(next);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(AppIcons.delete, size: 18),
                  onPressed: () =>
                      widget.onChanged([...widget.items]..removeAt(index)),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => widget.onChanged([...widget.items, '']),
            icon: const Icon(AppIcons.add, size: 16),
            label: Text(l10n.studioAddItem),
          ),
        ),
      ],
    );
  }
}
