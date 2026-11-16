// AI 角色工坊: 一句灵感，一张完整的卡。
//
// 两档（设计稿）：
//   · 快速创作 —— 只有「核心创意」和「详细程度」，默认就是这一档；
//   · 高级创作 —— 再指定姓名、身份、世界观、与玩家关系、性格标签、补充设定。
// 两档走同一个请求；没填的字段不会出现在提示里，模型也就不会去猜。
//
// 不走聊天管线：没有预设、没有历史、没有引擎上下文。一次 chat-completions
// 调用（[tavernModelClientProvider]），流式贴出来。回包由 [tavernCardParse]
// 解析；解析不了的原文摊在页面上让人看，不静默丢掉。存卡走 importCard，
// 所以新卡和导入的卡一样有 id、有页、能继续编辑。

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/model_access.dart';
import '../../tavern/lorebook_ai.dart';
import '../../tavern/preset_persona.dart';
import '../../tavern/tavern_card_studio.dart';
import '../../tavern/tavern_provider.dart';
import '../../tavern/tavern_session_usage.dart';
import '../../tavern/tavern_settings.dart';
import '../common/app_sheet.dart';
import '../common/capsule_chip.dart';
import '../common/sheet_title_bar.dart';
import '../providers/provider_widgets.dart';
import '../settings/settings_widgets.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'tavern_character_edit_page.dart';
import 'tavern_presets_page.dart' show tavernPresetsProvider;
import 'tavern_studio_page.dart';

/// 快速创作 / 高级创作.
enum _StudioMode { quick, advanced }

class TavernCardStudioPage extends ConsumerStatefulWidget {
  const TavernCardStudioPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const TavernCardStudioPage());

  @override
  ConsumerState<TavernCardStudioPage> createState() =>
      _TavernCardStudioPageState();
}

class _TavernCardStudioPageState extends ConsumerState<TavernCardStudioPage> {
  final _idea = TextEditingController();
  final _name = TextEditingController();
  final _identity = TextEditingController();
  final _extra = TextEditingController();
  final _ideaFocus = FocusNode();
  final _rawScroll = ScrollController();

  var _mode = _StudioMode.quick;
  var _length = TavernCardLength.standard;

  /// 世界观 / 与玩家关系: the chosen label, null for none.
  /// 世界观 / 与玩家关系: free text, with a list of common ones to tap.
  final _world = TextEditingController();
  final _relation = TextEditingController();

  /// 性格标签: indices into the trait list of the current language.
  final _traits = <int>{};

  /// While a reply is being written.
  var _busy = false;
  var _raw = '';
  ModelCancellation? _cancel;

  /// The last reply, parsed. Null until one ends well.
  Map<String, Object?>? _card;
  TavernUsage? _usage;
  String? _model;
  String? _error;
  String? _rawShown;

  /// ??????????????????????????????
  final _previewKey = GlobalKey();
  var _saving = false;

  bool get _english => AppLocale.isEnglish;

  List<String> _worlds(L10n l10n) => [
    l10n.tavernCardStudioWorldCity,
    l10n.tavernCardStudioWorldCampus,
    l10n.tavernCardStudioWorldAncient,
    l10n.tavernCardStudioWorldSpace,
    l10n.tavernCardStudioWorldDoom,
    l10n.tavernCardStudioWorldFantasy,
  ];

  List<String> _relations(L10n l10n) => [
    l10n.tavernCardStudioRelStranger,
    l10n.tavernCardStudioRelNeighbor,
    l10n.tavernCardStudioRelColleague,
    l10n.tavernCardStudioRelClassmate,
    l10n.tavernCardStudioRelChildhood,
    l10n.tavernCardStudioRelLover,
    l10n.tavernCardStudioRelFamily,
    l10n.tavernCardStudioRelRival,
  ];

  List<String> _allTraits(L10n l10n) => [
    l10n.tavernCardTraitWarm,
    l10n.tavernCardTraitCold,
    l10n.tavernCardTraitTsundere,
    l10n.tavernCardTraitSharp,
    l10n.tavernCardTraitLively,
    l10n.tavernCardTraitQuiet,
    l10n.tavernCardTraitScheming,
    l10n.tavernCardTraitAirhead,
  ];

  /// 人格层：资源库 › 预设 里挑一层垫在提示前面（null = 不用）。
  /// 制卡这条线自己记一份，和世界书工坊那份不共用（tavern_settings）。
  /// build 里读它，选完立刻重画。
  String? get _personaId => ref.watch(tavernSettingsProvider).cardPersonaId;

  /// 生成时用：那会儿不在 build 里，不能 watch。
  String? get _personaIdNow => ref.read(tavernSettingsProvider).cardPersonaId;

  /// 存卡时顺手写一本卡内世界书（进 character_book，跟着卡走）。
  var _bookOn = false;
  var _bookAuto = true;
  final _bookBrief = TextEditingController();
  String? _bookProgress;

  @override
  void dispose() {
    _cancel?.cancel();
    for (final c in [
      _idea,
      _name,
      _identity,
      _extra,
      _world,
      _relation,
      _bookBrief,
    ]) {
      c.dispose();
    }
    _ideaFocus.dispose();
    _rawScroll.dispose();
    super.dispose();
  }

  /// Keeps the streaming box on its last line as the reply grows.
  void _stickRaw() {
    if (!_rawScroll.hasClients) return;
    _rawScroll.jumpTo(_rawScroll.position.maxScrollExtent);
  }

  /// 选中的人格层：从资源库里那本预设现取。取不到就当没选。
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

  /// 挑一层人格：资源库里导入过的预设都在这里。
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
            SheetTitleBar(l10n.tavernCardStudioPersona),
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
                      key: const ValueKey('tavern-card-persona-none'),
                      icon: AppIcons.dropdown,
                      tinted: false,
                      title: l10n.tavernCardStudioPersonaNone,
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
                        key: ValueKey('tavern-card-persona-${preset.id}'),
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
        .setCardPersona(picked.isEmpty ? null : picked);
  }

  /// 一次性的文本请求：不流到界面，等整段回来（写世界书用的）。
  Future<String?> _askText(
    List<Map<String, Object?>> messages, {
    int maxTokens = 4000,
  }) async {
    final client = ref.read(tavernModelClientProvider);
    final config = ref.read(tavernModelConfigProvider);
    final buffer = StringBuffer();
    try {
      await for (final delta in client.generate(
        config: config,
        body: {
          'messages': messages,
          'temperature': 0.9,
          'max_tokens': maxTokens,
        },
        cancellation: ModelCancellation(),
      )) {
        if (delta is ModelText) buffer.write(delta.text);
      }
    } on Object {
      return null;
    }
    return buffer.toString();
  }

  /// 卡存好之后，给它写一本自带的世界书。
  ///
  /// 用的是**制卡这一路自己的提示**（[cardBookMessages]），不是世界书工坊那四步：
  /// 这里的锚点是这张卡本身，条目只在这张卡的世界里成立。
  /// 失败不撤销存卡——卡已经在了，说清楚就行。
  Future<void> _writeCardBook(
    TavernCharacter character,
    L10n l10n,
    ScaffoldMessengerState messenger,
  ) async {
    final card = _card;
    if (card == null) return;
    final provider = ref.read(tavernProvider);
    if (mounted) {
      setState(() => _bookProgress = l10n.tavernCardStudioBookWriting);
    }
    try {
      final persona = await _personaText();
      final reply = await _askText(
        cardBookMessages(
          card: card,
          brief: _bookAuto ? '' : _bookBrief.text,
          persona: persona,
        ),
        maxTokens: 4000,
      );
      final entries = reply == null
          ? const <LorebookDraftEntry>[]
          : cardBookParse(reply);
      if (entries.isEmpty) {
        if (mounted) setState(() => _bookProgress = null);
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.tavernCardStudioBookFailed)),
        );
        return;
      }
      for (final entry in entries) {
        await provider.addCharacterBookEntry(
          character.id,
          cardBookEntryFields(entry),
        );
      }
      if (mounted) setState(() => _bookProgress = null);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.tavernCardStudioBookDone(entries.length))),
      );
    } on Object {
      if (mounted) setState(() => _bookProgress = null);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.tavernCardStudioBookFailed)),
      );
    }
  }

  /// The wish as the form stands: 快速 only carries the idea, 高级 carries all.
  TavernCardWish _wish(L10n l10n) {
    final advanced = _mode == _StudioMode.advanced;
    final traits = _allTraits(l10n);
    return TavernCardWish(
      idea: _idea.text,
      name: advanced ? _name.text : '',
      identity: advanced ? _identity.text : '',
      world: advanced ? _world.text : '',
      relation: advanced ? _relation.text : '',
      traits: advanced
          ? [
              for (final (index, trait) in traits.indexed)
                if (_traits.contains(index)) trait,
            ]
          : const [],
      extra: advanced ? _extra.text : '',
      length: _length,
      english: _english,
    );
  }

  Future<void> _generate() async {
    final l10n = context.l10n;
    if (_busy) return;
    final idea = _idea.text.trim();
    if (idea.isEmpty) {
      setState(() => _error = l10n.tavernCardStudioIdeaNeeded);
      _ideaFocus.requestFocus();
      return;
    }
    if (!ref.read(modelAccessProvider)) {
      setState(() => _error = l10n.tavernCardStudioNoKey);
      return;
    }
    final config = ref.read(tavernModelConfigProvider);
    final client = ref.read(tavernModelClientProvider);
    final persona = await _personaText();
    if (!mounted) return;
    final cancel = ModelCancellation();
    final buffer = StringBuffer();
    // Rebuilds at most ten times a second, however fast the tokens come.
    final tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final text = buffer.toString();
      if (text == _raw) return;
      setState(() => _raw = text);
      _stickRaw();
    });
    setState(() {
      _busy = true;
      _error = null;
      _raw = '';
      _rawShown = null;
      _card = null;
      _usage = null;
      _model = config.model;
      _cancel = cancel;
    });
    var usage = null as TavernUsage?;
    Object? failure;
    var stopped = false;
    try {
      await for (final delta in client.generate(
        config: config,
        body: tavernCardRequestBody(_wish(l10n), persona: persona),
        cancellation: cancel,
      )) {
        if (delta is ModelText) {
          buffer.write(delta.text);
        } else if (delta is ModelUsage) {
          usage = delta.usage;
        }
      }
    } on TavernModelException catch (e) {
      if (e.kind == TavernFailure.cancelled) {
        stopped = true;
      } else {
        failure = e;
      }
    } on Object catch (e) {
      failure = e;
    }
    tick.cancel();
    if (!mounted) return;
    final text = buffer.toString();
    // 停下来时可能刚好写完：仍然试着解析，解析不了也不报错。
    final card = failure == null ? tavernCardParse(text) : null;
    setState(() {
      _busy = false;
      _cancel = null;
      _raw = text;
      _rawShown = text.trim().isEmpty ? null : text;
      _usage = usage;
      if (failure != null) {
        _error = _failureText(failure);
      } else if (card == null) {
        _error = stopped
            ? null
            : (text.trim().isEmpty
                  ? l10n.tavernCardStudioFailed
                  : l10n.tavernCardStudioParseFailed);
      } else {
        _card = card;
      }
    });
    if (card != null) {
      _ideaFocus.unfocus();
      // ???????????????? context?
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _previewKey.currentContext;
        if (target != null) {
          unawaited(
            Scrollable.ensureVisible(
              target,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              alignment: 0.02,
            ),
          );
        }
      });
    }
  }

  /// A sentence the user can act on, not the transport's code.
  String _failureText(Object failure) {
    final l10n = context.l10n;
    if (failure is TavernModelException) {
      return switch (failure.kind) {
        TavernFailure.noKey => l10n.tavernCardStudioNoKey,
        TavernFailure.network => l10n.tavernCardStudioNetwork,
        TavernFailure.contextTooLong => l10n.tavernCardStudioParseFailed,
        _ => l10n.tavernCardStudioFailed,
      };
    }
    return l10n.tavernCardStudioFailed;
  }

  void _stop() {
    _cancel?.cancel();
    setState(() => _busy = false);
  }

  Future<void> _save() async {
    final card = _card;
    if (card == null || _saving) return;
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final character = await ref
          .read(tavernProvider)
          .importCard(
            Uint8List.fromList(
              utf8.encode(
                jsonEncode(
                  tavernCardJson(card, creator: l10n.tavernCardStudioTitle),
                ),
              ),
            ),
            fileName: 'ai_card.json',
          );
      if (!mounted) return;
      // 卡已经在了：顺手写的那本世界书就算失败也不撤销存卡。
      if (_bookOn) await _writeCardBook(character, l10n, messenger);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.tavernCardStudioSaved(character.name))),
      );
      // 已经存进去，接着就能改：编辑页替换掉制卡页，返回是书架。
      unawaited(
        navigator.pushReplacement(TavernCharacterEditPage.route(character.id)),
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l10n.tavernCardStudioSaveFailed;
      });
    }
  }

  /// The tokens this reply took, and what they cost when the model is priced.
  String? _usageLine(L10n l10n) {
    final usage = _usage;
    if (usage == null) return null;
    final tokens = usage.promptTokens + usage.completionTokens;
    if (tavernModelPrice(usage.model ?? _model) case final price?) {
      return l10n.tavernCardStudioTokensCost(
        tokens,
        tavernCny(tavernReplyCost(usage, price, DateTime.now())),
      );
    }
    return l10n.tavernCardStudioTokens(tokens);
  }

  /// 世界观 / 关系: a sheet of suggestions, one tap each, or 不指定 to clear.
  /// Whatever was typed stays until an option is picked — the field is free text.
  Future<void> _pick({
    required String title,
    required List<String> options,
    required TextEditingController controller,
  }) async {
    final picked = await showAppSheet<String>(
      context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(title),
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
                    for (final option in ['', ...options])
                      SettingsTile(
                        key: ValueKey('studio-pick-$option'),
                        icon: AppIcons.dropdown,
                        tinted: false,
                        title: option.isEmpty
                            ? context.l10n.tavernCardStudioNone
                            : option,
                        value: option == controller.text
                            ? Icon(
                                AppIcons.selected,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        chevron: false,
                        onTap: () => Navigator.of(sheet).pop(option),
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
    controller.text = picked;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final card = _card;
    final usageLine = _usageLine(l10n);
    final canGenerate = !_busy && !_saving;
    final advanced = _mode == _StudioMode.advanced;

    // 生成键钉在底部：需求写完就在手边，不用为了点它把页面滚下去。
    return Stack(
      children: [
        AppPage.list(
          title: l10n.tavernCardStudioPageTitle,
          subtitle: Text(l10n.tavernCardStudioSubtitle),
          actions: [
            if (_rawShown != null)
              GlassIconButton(
                key: const ValueKey('tavern-card-studio-raw'),
                icon: AppIcons.code,
                tooltip: l10n.tavernCardStudioRaw,
                onPressed: () => _showRaw(_rawShown!),
              ),
          ],
          children: [
            // 提示和流式原文放在最上面：写完点生成，眼睛不用往下找。
            _status(context, l10n),
            if (_busy || (_raw.isNotEmpty && card == null))
              _streamingBox(context),
            SettingsSection(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: SegmentedPill<_StudioMode>(
                    key: const ValueKey('tavern-card-studio-mode'),
                    expand: true,
                    segments: [
                      PillSegment(
                        _StudioMode.quick,
                        l10n.tavernCardStudioQuick,
                      ),
                      PillSegment(
                        _StudioMode.advanced,
                        l10n.tavernCardStudioAdvanced,
                      ),
                    ],
                    selected: _mode,
                    onChanged: canGenerate
                        ? (mode) => setState(() => _mode = mode)
                        : null,
                  ),
                ),
              ],
            ),
            // 想自己一层层写，而不是让模型一把写完：进专业创作。
            SettingsSection(
              children: [
                SettingsTile(
                  key: const ValueKey('tavern-card-studio-pro'),
                  icon: AppIcons.article,
                  tinted: false,
                  title: l10n.studioTitle,
                  subtitle: l10n.studioSubtitle,
                  onTap: canGenerate
                      ? () => unawaited(
                          Navigator.of(context)
                              .push(TavernStudioPage.route(idea: _idea.text)),
                        )
                      : null,
                ),
              ],
            ),
            SettingsSection(
              footer: Text(l10n.tavernCardStudioNote),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: FormFieldBlock(
                    key: const ValueKey('tavern-card-studio-idea'),
                    label: l10n.tavernCardStudioIdea,
                    helper: l10n.tavernCardStudioIdeaHint,
                    child: TextField(
                      controller: _idea,
                      focusNode: _ideaFocus,
                      enabled: canGenerate,
                      minLines: 3,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      // 一开写，上一回的提示就过时了。
                      onChanged: (text) {
                        if (_error != null && text.trim().isNotEmpty) {
                          setState(() => _error = null);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            // 人设那一层，和「要不要顺手写一本世界书」。
            SettingsSection(
              title: l10n.tavernCardStudioExtras,
              children: [
                SettingsTile(
                  key: const ValueKey('tavern-card-studio-persona'),
                  icon: AppIcons.dropdown,
                  tinted: false,
                  title: l10n.tavernCardStudioPersona,
                  subtitle: _personaName ?? l10n.tavernCardStudioPersonaNone,
                  onTap: canGenerate ? () => unawaited(_pickPersona()) : null,
                ),
                SettingsTile(
                  key: const ValueKey('tavern-card-studio-book'),
                  icon: AppIcons.lorebook,
                  tinted: false,
                  title: l10n.tavernCardStudioBook,
                  subtitle: l10n.tavernCardStudioBookHint,
                  trailing: Switch(
                    value: _bookOn,
                    onChanged: canGenerate
                        ? (on) => setState(() => _bookOn = on)
                        : null,
                  ),
                  chevron: false,
                  onTap: canGenerate
                      ? () => setState(() => _bookOn = !_bookOn)
                      : null,
                ),
                if (_bookOn) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: SegmentedPill<bool>(
                      key: const ValueKey('tavern-card-studio-book-mode'),
                      expand: true,
                      segments: [
                        PillSegment(true, l10n.tavernCardStudioBookAuto),
                        PillSegment(false, l10n.tavernCardStudioBookMine),
                      ],
                      selected: _bookAuto,
                      onChanged: canGenerate
                          ? (auto) => setState(() => _bookAuto = auto)
                          : null,
                    ),
                  ),
                  if (!_bookAuto)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: FormFieldBlock(
                        key: const ValueKey('tavern-card-studio-book-brief'),
                        label: l10n.tavernCardStudioBookBrief,
                        helper: l10n.tavernCardStudioBookBriefHint,
                        child: TextField(
                          controller: _bookBrief,
                          enabled: canGenerate,
                          minLines: 2,
                          maxLines: 4,
                        ),
                      ),
                    ),
                ],
              ],
            ),
            if (advanced) ...[
              _pair(
                context,
                _textField(
                  key: 'tavern-card-studio-name',
                  label: l10n.tavernCardStudioName,
                  hint: l10n.tavernCardStudioNameHint,
                  controller: _name,
                  enabled: canGenerate,
                ),
                _textField(
                  key: 'tavern-card-studio-identity',
                  label: l10n.tavernCardStudioIdentity,
                  hint: l10n.tavernCardStudioIdentityHint,
                  controller: _identity,
                  enabled: canGenerate,
                ),
              ),
              _pair(
                context,
                _freeField(
                  key: 'tavern-card-studio-world',
                  label: l10n.tavernCardStudioWorld,
                  hint: l10n.tavernCardStudioWorldHint,
                  controller: _world,
                  enabled: canGenerate,
                  onPick: () => unawaited(
                    _pick(
                      title: l10n.tavernCardStudioWorld,
                      options: _worlds(l10n),
                      controller: _world,
                    ),
                  ),
                ),
                _freeField(
                  key: 'tavern-card-studio-relation',
                  label: l10n.tavernCardStudioRelation,
                  hint: l10n.tavernCardStudioRelationHint,
                  controller: _relation,
                  enabled: canGenerate,
                  onPick: () => unawaited(
                    _pick(
                      title: l10n.tavernCardStudioRelation,
                      options: _relations(l10n),
                      controller: _relation,
                    ),
                  ),
                ),
              ),
              SettingsSection(
                title: l10n.tavernCardStudioTraits,
                footer: Text(l10n.tavernCardStudioTraitsNote),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        key: const ValueKey('tavern-card-studio-traits'),
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (index, trait) in _allTraits(l10n).indexed)
                            CapsuleChoiceChip(
                              label: trait,
                              selected: _traits.contains(index),
                              onSelected: canGenerate
                                  ? () => setState(() {
                                      _traits.contains(index)
                                          ? _traits.remove(index)
                                          : _traits.add(index);
                                    })
                                  : () {},
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SettingsSection(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: FormFieldBlock(
                      key: const ValueKey('tavern-card-studio-extra'),
                      label: l10n.tavernCardStudioExtra,
                      child: TextField(
                        controller: _extra,
                        enabled: canGenerate,
                        minLines: 2,
                        maxLines: 5,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: l10n.tavernCardStudioExtraHint,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            _lengthSection(l10n, canGenerate),
            if (_bookProgress case final progress?)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  progress,
                  key: const ValueKey('tavern-card-studio-book-progress'),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: DshColors.of(context).textTertiary),
                ),
              ),
            if (card != null)
              KeyedSubtree(
                key: _previewKey,
                child: _preview(context, l10n, card),
              ),
            if (usageLine != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                child: Text(
                  usageLine,
                  key: const ValueKey('tavern-card-studio-usage'),
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
            child: _busy
                ? FilledButton.tonalIcon(
                    key: const ValueKey('tavern-card-studio-stop'),
                    onPressed: _stop,
                    icon: const Icon(AppIcons.stop, size: 18),
                    label: Text(l10n.tavernCardStudioStop),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  )
                : FilledButton.icon(
                    key: const ValueKey('tavern-card-studio-generate'),
                    onPressed: canGenerate ? _generate : null,
                    icon: const Icon(AppIcons.generateMedia, size: 18),
                    label: Text(l10n.tavernCardStudioGenerate),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// Two fields side by side on a wide screen, stacked on a phone.
  Widget _pair(BuildContext context, Widget a, Widget b) {
    if (MediaQuery.sizeOf(context).width < 640) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [a, b],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        Expanded(child: b),
      ],
    );
  }

  Widget _textField({
    required String key,
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool enabled,
  }) => SettingsSection(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: FormFieldBlock(
          key: ValueKey(key),
          label: label,
          child: TextField(
            controller: controller,
            enabled: enabled,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(hintText: hint),
          ),
        ),
      ),
    ],
  );

  /// 世界观 / 关系: typed freely, with a list of common ones behind the arrow.
  /// Typing and picking share one controller, so a pick just fills the field
  /// and the user can keep editing it afterwards.
  Widget _freeField({
    required String key,
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool enabled,
    required VoidCallback onPick,
  }) => SettingsSection(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: FormFieldBlock(
          key: ValueKey(key),
          label: label,
          child: TextField(
            controller: controller,
            enabled: enabled,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: hint,
              // 右边这颗只是"从常见项里挑一个"，不点它也能自己写。
              suffixIcon: IconButton(
                key: ValueKey('$key-pick'),
                tooltip: label,
                icon: Icon(
                  AppIcons.expand,
                  size: 18,
                  color: DshColors.of(context).textTertiary,
                ),
                onPressed: enabled ? onPick : null,
              ),
            ),
          ),
        ),
      ),
    ],
  );

  /// 篇幅：三段，决定 max_tokens 和提示里的字数要求。
  Widget _lengthSection(L10n l10n, bool enabled) => SettingsSection(
    title: l10n.tavernCardStudioLength,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SegmentedPill<TavernCardLength>(
          key: const ValueKey('tavern-card-studio-length'),
          expand: true,
          segments: [
            PillSegment(
              TavernCardLength.brief,
              l10n.tavernCardStudioLengthBrief,
            ),
            PillSegment(
              TavernCardLength.standard,
              l10n.tavernCardStudioLengthStandard,
            ),
            PillSegment(TavernCardLength.rich, l10n.tavernCardStudioLengthRich),
          ],
          selected: _length,
          onChanged: enabled
              ? (value) => setState(() => _length = value)
              : null,
        ),
      ),
    ],
  );

  /// What just happened: a failure, or the line the card is written under.
  Widget _status(BuildContext context, L10n l10n) {
    final error = _error;
    final text = error ?? (_busy ? l10n.tavernCardStudioWriting : null);
    if (text == null) return const SizedBox.shrink();
    final danger = DshColors.of(context).danger;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_busy) ...[
              SizedBox.square(
                dimension: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DshColors.of(context).textTertiary,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                text,
                key: const ValueKey('tavern-card-studio-status'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: error == null
                      ? DshColors.of(context).textTertiary
                      : danger,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The reply as it comes, before it is a card.
  Widget _streamingBox(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Container(
      key: const ValueKey('tavern-card-studio-stream'),
      constraints: const BoxConstraints(maxHeight: 180),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
      ),
      child: SingleChildScrollView(
        controller: _rawScroll,
        child: Text(
          _raw,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontFamily: 'monospace',
            height: 1.5,
          ),
        ),
      ),
    ),
  );

  Widget _preview(BuildContext context, L10n l10n, Map<String, Object?> card) {
    final text = Theme.of(context).textTheme.bodyMedium;
    final tags =
        (card['tags'] as List<Object?>?)?.whereType<String>().toList() ??
        const <String>[];
    final greetings =
        (card['alternate_greetings'] as List<Object?>?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];
    Widget row(String label, String value) => value.trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: DshColors.of(context).textTertiary),
                ),
                const SizedBox(height: 4),
                Text(value.trim(), style: text),
              ],
            ),
          );
    return Column(
      key: const ValueKey('tavern-card-studio-preview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: l10n.tavernCardStudioPreview,
          footer: Text(l10n.tavernCardStudioPreviewNote),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    card['name']! as String,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in tags) Chip(label: Text(tag)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  row(
                    l10n.tavernFieldDescription,
                    card['description']! as String,
                  ),
                  row(
                    l10n.tavernFieldPersonality,
                    card['personality']! as String,
                  ),
                  row(l10n.tavernFieldScenario, card['scenario']! as String),
                  row(
                    l10n.tavernGreetingNumber(1),
                    card['first_mes']! as String,
                  ),
                  row(
                    l10n.tavernCardStudioGreetings(greetings.length),
                    greetings.map((g) => '· $g').join('\n'),
                  ),
                  row(l10n.tavernFieldExamples, card['mes_example']! as String),
                  row(
                    l10n.tavernCreatorNotes,
                    card['creator_notes']! as String,
                  ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('tavern-card-studio-again'),
                  onPressed: _saving ? null : () => unawaited(_generate()),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: Text(l10n.tavernCardStudioAgain),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('tavern-card-studio-save'),
                  onPressed: _saving ? null : () => unawaited(_save()),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: Text(l10n.tavernCardStudioSave),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showRaw(String text) {
    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.l10n.tavernCardStudioRaw),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: Text(context.l10n.commonClose),
          ),
        ],
      ),
    );
  }
}
