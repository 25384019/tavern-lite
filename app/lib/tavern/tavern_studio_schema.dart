// 生成文件，别手改：改 `tool/gen_studio_schema.py` 里的表，重跑。
//
// 创作层的字段规格：九个模块、59 个字段，每个都带着控件类型、字数预算和去向。
// 去向只有三种：
//   card —— 会被转换器写进 description / personality / scenario / …；
//   book —— 变成世界书条目，关键词触发时才注入；
//   meta —— 只留在 extensions 里，给导演/剧本按需用，不占卡片字数。

import '../../l10n/l10n.dart';

/// 字段怎么填。
enum StudioControl { line, block, tags, list }

/// 这段文字最后去哪。
enum StudioTarget { card, book, meta }

class StudioFieldSpec {
  const StudioFieldSpec(
    this.key,
    this.control,
    this.budget,
    this.target, {
    this.required = false,
  });

  final String key;
  final StudioControl control;

  /// 建议字数。超了不减分，但转换器会按它裁剪。
  final int budget;
  final StudioTarget target;

  /// 存卡前必须填。
  final bool required;

  bool get isList => control == StudioControl.tags || control == StudioControl.list;
}

class StudioModuleSpec {
  const StudioModuleSpec(this.id, this.fields);

  final String id;
  final List<StudioFieldSpec> fields;

  StudioFieldSpec? field(String key) {
    for (final field in fields) {
      if (field.key == key) return field;
    }
    return null;
  }
}

const studioModules = <StudioModuleSpec>[
  StudioModuleSpec('profile', [
    StudioFieldSpec('name', StudioControl.line, 12, StudioTarget.card, required: true),
    StudioFieldSpec('nickname', StudioControl.line, 12, StudioTarget.card),
    StudioFieldSpec('age', StudioControl.line, 8, StudioTarget.card),
    StudioFieldSpec('gender', StudioControl.tags, 4, StudioTarget.card),
    StudioFieldSpec('species', StudioControl.line, 12, StudioTarget.card),
    StudioFieldSpec('appearance', StudioControl.block, 160, StudioTarget.card, required: true),
    StudioFieldSpec('body', StudioControl.block, 120, StudioTarget.card),
    StudioFieldSpec('identity', StudioControl.line, 20, StudioTarget.card),
    StudioFieldSpec('likes', StudioControl.tags, 60, StudioTarget.card),
    StudioFieldSpec('habits', StudioControl.block, 120, StudioTarget.card),
    StudioFieldSpec('ability', StudioControl.block, 120, StudioTarget.book),
    StudioFieldSpec('weakness', StudioControl.block, 100, StudioTarget.book),
  ]),
  StudioModuleSpec('mind', [
    StudioFieldSpec('surface', StudioControl.tags, 40, StudioTarget.card),
    StudioFieldSpec('inner', StudioControl.block, 160, StudioTarget.card),
    StudioFieldSpec('values', StudioControl.block, 100, StudioTarget.card),
    StudioFieldSpec('desire', StudioControl.block, 80, StudioTarget.meta),
    StudioFieldSpec('fear', StudioControl.block, 80, StudioTarget.meta),
    StudioFieldSpec('flaw', StudioControl.block, 80, StudioTarget.card),
    StudioFieldSpec('trigger', StudioControl.list, 120, StudioTarget.book),
    StudioFieldSpec('defense', StudioControl.block, 100, StudioTarget.book),
  ]),
  StudioModuleSpec('bond', [
    StudioFieldSpec('initial', StudioControl.line, 20, StudioTarget.card),
    StudioFieldSpec('impression', StudioControl.block, 120, StudioTarget.card),
    StudioFieldSpec('trust', StudioControl.line, 4, StudioTarget.meta),
    StudioFieldSpec('intimacy', StudioControl.tags, 60, StudioTarget.book),
    StudioFieldSpec('conflict', StudioControl.block, 120, StudioTarget.card),
    StudioFieldSpec('growth', StudioControl.list, 160, StudioTarget.book),
  ]),
  StudioModuleSpec('history', [
    StudioFieldSpec('family', StudioControl.block, 140, StudioTarget.card),
    StudioFieldSpec('upbringing', StudioControl.block, 140, StudioTarget.card),
    StudioFieldSpec('timeline', StudioControl.list, 200, StudioTarget.book),
    StudioFieldSpec('secret', StudioControl.block, 120, StudioTarget.book),
    StudioFieldSpec('memory', StudioControl.block, 100, StudioTarget.book),
    StudioFieldSpec('goal', StudioControl.block, 80, StudioTarget.meta),
  ]),
  StudioModuleSpec('world', [
    StudioFieldSpec('era', StudioControl.line, 20, StudioTarget.book),
    StudioFieldSpec('geography', StudioControl.block, 160, StudioTarget.book),
    StudioFieldSpec('factions', StudioControl.list, 200, StudioTarget.book),
    StudioFieldSpec('society', StudioControl.block, 140, StudioTarget.book),
    StudioFieldSpec('places', StudioControl.list, 200, StudioTarget.book),
    StudioFieldSpec('worldRules', StudioControl.list, 160, StudioTarget.book),
  ]),
  StudioModuleSpec('voice', [
    StudioFieldSpec('tone', StudioControl.tags, 30, StudioTarget.card),
    StudioFieldSpec('wording', StudioControl.block, 120, StudioTarget.card),
    StudioFieldSpec('catchphrase', StudioControl.list, 40, StudioTarget.card),
    StudioFieldSpec('action', StudioControl.block, 100, StudioTarget.meta),
    StudioFieldSpec('emotion', StudioControl.block, 100, StudioTarget.card),
    StudioFieldSpec('samples', StudioControl.list, 300, StudioTarget.card),
    StudioFieldSpec('firstMes', StudioControl.block, 260, StudioTarget.card),
  ]),
  StudioModuleSpec('scene', [
    StudioFieldSpec('meeting', StudioControl.block, 140, StudioTarget.card),
    StudioFieldSpec('backdrop', StudioControl.block, 160, StudioTarget.card),
    StudioFieldSpec('tension', StudioControl.block, 120, StudioTarget.card),
    StudioFieldSpec('direction', StudioControl.list, 120, StudioTarget.book),
    StudioFieldSpec('openings', StudioControl.list, 260, StudioTarget.card),
  ]),
  StudioModuleSpec('rules', [
    StudioFieldSpec('autonomy', StudioControl.tags, 40, StudioTarget.card),
    StudioFieldSpec('knowledge', StudioControl.block, 140, StudioTarget.card),
    StudioFieldSpec('principles', StudioControl.list, 160, StudioTarget.card),
    StudioFieldSpec('interaction', StudioControl.list, 140, StudioTarget.card),
    StudioFieldSpec('consistency', StudioControl.list, 120, StudioTarget.card),
  ]),
  StudioModuleSpec('soul', [
    StudioFieldSpec('motive', StudioControl.block, 60, StudioTarget.meta),
    StudioFieldSpec('constants', StudioControl.tags, 40, StudioTarget.meta),
    StudioFieldSpec('conflict', StudioControl.block, 60, StudioTarget.meta),
    StudioFieldSpec('soulGrowth', StudioControl.block, 60, StudioTarget.meta),
  ]),
];

/// 模块 id → 它的规格；没有就 null。
StudioModuleSpec? studioModule(String id) {
  for (final module in studioModules) {
    if (module.id == id) return module;
  }
  return null;
}

/// 模块名。
String studioModuleLabel(String module, L10n l10n) => switch (module) {
  'profile' => l10n.studioModuleProfile,
  'mind' => l10n.studioModuleMind,
  'bond' => l10n.studioModuleBond,
  'history' => l10n.studioModuleHistory,
  'world' => l10n.studioModuleWorld,
  'voice' => l10n.studioModuleVoice,
  'scene' => l10n.studioModuleScene,
  'rules' => l10n.studioModuleRules,
  'soul' => l10n.studioModuleSoul,
  _ => module,
};

/// 一句话说明：这一模块管什么。
String studioModuleSubtitle(String module, L10n l10n) => switch (module) {
  'profile' => l10n.studioModuleProfileSub,
  'mind' => l10n.studioModuleMindSub,
  'bond' => l10n.studioModuleBondSub,
  'history' => l10n.studioModuleHistorySub,
  'world' => l10n.studioModuleWorldSub,
  'voice' => l10n.studioModuleVoiceSub,
  'scene' => l10n.studioModuleSceneSub,
  'rules' => l10n.studioModuleRulesSub,
  'soul' => l10n.studioModuleSoulSub,
  _ => '',
};

/// 字段名。
String studioFieldLabel(String module, String field, L10n l10n) =>
    switch ('$module.$field') {
      'profile.name' => l10n.studioProfileName,
      'profile.nickname' => l10n.studioProfileNickname,
      'profile.age' => l10n.studioProfileAge,
      'profile.gender' => l10n.studioProfileGender,
      'profile.species' => l10n.studioProfileSpecies,
      'profile.appearance' => l10n.studioProfileAppearance,
      'profile.body' => l10n.studioProfileBody,
      'profile.identity' => l10n.studioProfileIdentity,
      'profile.likes' => l10n.studioProfileLikes,
      'profile.habits' => l10n.studioProfileHabits,
      'profile.ability' => l10n.studioProfileAbility,
      'profile.weakness' => l10n.studioProfileWeakness,
      'mind.surface' => l10n.studioMindSurface,
      'mind.inner' => l10n.studioMindInner,
      'mind.values' => l10n.studioMindValues,
      'mind.desire' => l10n.studioMindDesire,
      'mind.fear' => l10n.studioMindFear,
      'mind.flaw' => l10n.studioMindFlaw,
      'mind.trigger' => l10n.studioMindTrigger,
      'mind.defense' => l10n.studioMindDefense,
      'bond.initial' => l10n.studioBondInitial,
      'bond.impression' => l10n.studioBondImpression,
      'bond.trust' => l10n.studioBondTrust,
      'bond.intimacy' => l10n.studioBondIntimacy,
      'bond.conflict' => l10n.studioBondConflict,
      'bond.growth' => l10n.studioBondGrowth,
      'history.family' => l10n.studioHistoryFamily,
      'history.upbringing' => l10n.studioHistoryUpbringing,
      'history.timeline' => l10n.studioHistoryTimeline,
      'history.secret' => l10n.studioHistorySecret,
      'history.memory' => l10n.studioHistoryMemory,
      'history.goal' => l10n.studioHistoryGoal,
      'world.era' => l10n.studioWorldEra,
      'world.geography' => l10n.studioWorldGeography,
      'world.factions' => l10n.studioWorldFactions,
      'world.society' => l10n.studioWorldSociety,
      'world.places' => l10n.studioWorldPlaces,
      'world.worldRules' => l10n.studioWorldWorldRules,
      'voice.tone' => l10n.studioVoiceTone,
      'voice.wording' => l10n.studioVoiceWording,
      'voice.catchphrase' => l10n.studioVoiceCatchphrase,
      'voice.action' => l10n.studioVoiceAction,
      'voice.emotion' => l10n.studioVoiceEmotion,
      'voice.samples' => l10n.studioVoiceSamples,
      'voice.firstMes' => l10n.studioVoiceFirstMes,
      'scene.meeting' => l10n.studioSceneMeeting,
      'scene.backdrop' => l10n.studioSceneBackdrop,
      'scene.tension' => l10n.studioSceneTension,
      'scene.direction' => l10n.studioSceneDirection,
      'scene.openings' => l10n.studioSceneOpenings,
      'rules.autonomy' => l10n.studioRulesAutonomy,
      'rules.knowledge' => l10n.studioRulesKnowledge,
      'rules.principles' => l10n.studioRulesPrinciples,
      'rules.interaction' => l10n.studioRulesInteraction,
      'rules.consistency' => l10n.studioRulesConsistency,
      'soul.motive' => l10n.studioSoulMotive,
      'soul.constants' => l10n.studioSoulConstants,
      'soul.conflict' => l10n.studioSoulConflict,
      'soul.soulGrowth' => l10n.studioSoulSoulGrowth,
      _ => field,
    };

/// 一个模块里必填却又空着的字段，存卡前拦一下。
List<String> studioMissingRequired(String module, String Function(String key) read) => [
  for (final field in studioModule(module)?.fields ?? const <StudioFieldSpec>[])
    if (field.required && read(field.key).trim().isEmpty) field.key,
];
