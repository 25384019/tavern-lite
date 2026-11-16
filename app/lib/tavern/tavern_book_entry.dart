/// A lorebook entry as the editor reads and writes it: a card's own book's
/// field names (V2 character_book: keys, secondary_keys, insertion_order,
/// enabled, ST's other fields under extensions). A book in the library may be
/// kept in ST's own world-info shape instead (key, keysecondary, order,
/// disable, position as a number, the rest at the top); these turn one into
/// the other, so the same editor serves both.
library;

/// ST's own entry as the editor's (card-shaped) entry.
Map<String, Object?> tavernNativeToCard(Map<String, Object?> native) => {
  'comment': native['comment'] ?? '',
  'keys': native['key'] ?? const <Object?>[],
  'secondary_keys': native['keysecondary'] ?? const <Object?>[],
  'selective': native['selective'] ?? false,
  'content': native['content'] ?? '',
  'constant': native['constant'] ?? false,
  'enabled': native['disable'] != true,
  'insertion_order': native['order'] ?? 100,
  'position': native['position'] == 0 ? 'before_char' : 'after_char',
  'extensions': {
    for (final MapEntry(key: card, value: own) in _extensionNames.entries)
      if (native.containsKey(own)) card: native[own],
  },
};

/// The editor's changes (or a whole new entry) in ST's own field names. The
/// card's position word goes: the number in extensions says the same.
Map<String, Object?> tavernCardToNative(Map<String, Object?> card) => {
  for (final MapEntry(:key, :value) in card.entries)
    if (_topNames[key] case final own?)
      own: key == 'enabled' ? value != true : value
    else if (key == 'extensions' && value is Map<String, Object?>)
      for (final MapEntry(key: name, value: field) in value.entries)
        ?_extensionNames[name]: field,
};

/// Card name → ST's own, for the top-level fields ('enabled' is ST's 'disable', turned over).
const _topNames = {
  'comment': 'comment',
  'keys': 'key',
  'secondary_keys': 'keysecondary',
  'selective': 'selective',
  'content': 'content',
  'constant': 'constant',
  'enabled': 'disable',
  'insertion_order': 'order',
};

/// Card extensions → ST's own top-level fields.
///
/// 左边的名字是 CC v3 条目 `extensions` 里的写法（世界书导入器认这一套，
/// 见 packages/dsh_tavern/lib/src/io/world_info_intake.dart 的 _v3EntryExtensions），
/// 右边是 ST 原生条目的顶层字段名。写回原生书时逐个搬过去，读回来时再搬回来，
/// 所以同一份编辑器既能编卡内书，也能编资源库里的书。
const _extensionNames = {
  'position': 'position',
  'depth': 'depth',
  'role': 'role',
  'selectiveLogic': 'selectiveLogic',
  'probability': 'probability',
  'useProbability': 'useProbability',
  'case_sensitive': 'caseSensitive',
  'match_whole_words': 'matchWholeWords',
  // 递归三件套：谁能被谁触发。
  //
  // ⚠️ 名字是 ST 的，行为是引擎的，而且**两者方向相反**（2026-11-16 核过
  // packages/dsh_tavern/lib/src/worldinfo/world_info.dart）：
  //   excludeRecursion —— 752 行：递归扫描阶段直接跳过这一条（= ST 的 Prevent Recursion）；
  //   preventRecursion —— 869 行：这一条不进「可以继续触发别人」的名单（= ST 的 Exclude Recursion）。
  // 界面上按引擎的真实行为写说明，别照 ST 的字面意思翻。
  'exclude_recursion': 'excludeRecursion',
  'prevent_recursion': 'preventRecursion',
  'delay_until_recursion': 'delayUntilRecursion',
  // 互斥分组。
  'group': 'group',
  'group_override': 'groupOverride',
  'group_weight': 'groupWeight',
  // 扫描与冷却。
  'scan_depth': 'scanDepth',
  'sticky': 'sticky',
  'cooldown': 'cooldown',
  'delay': 'delay',
  'use_regex': 'use_regex',
};

/// [into] with [changes] laid over it: maps one level down merged (as the
/// engine merges a card entry's extensions), everything else replaced.
Map<String, Object?> tavernMergeEntry(
  Map<String, Object?> into,
  Map<String, Object?> changes,
) => {
  ...into,
  for (final MapEntry(:key, :value) in changes.entries)
    key: switch ((into[key], value)) {
      (final Map<String, Object?> was, final Map<String, Object?> now) => {
        ...was,
        ...now,
      },
      _ => value,
    },
};

/// 引擎的 `delayUntilRecursion` 是什么层级：`true` 当 1（ST 的老写法），
/// 数字就是层级本身，别的/负数当 0（= 不开）。
///
/// 编辑页必须按这个读、按这个写：把 2 当成布尔关掉，用户只改个名字也会把
/// 层级悄悄改成 false——那是在弄坏别人的世界书。
int tavernBookRecursionLevel(Object? value) => switch (value) {
  true => 1,
  final num n when n.isFinite && n > 0 => n.round(),
  _ => 0,
};

/// 只有需要的时候才写：原来就是 `true` 且层级还是 1，就继续写 `true`，
/// 不要凭空把 JSON 形状换掉。
Object? tavernBookRecursionValue(int level, Object? was) =>
    was == true && level == 1 ? true : (level <= 0 ? 0 : level);

/// 这两个一起开，这条永远不生效。
///
/// 引擎里：`delayUntilRecursion` 只在递归扫描阶段才考虑这一条（world_info.dart 741），
/// `excludeRecursion` 又在递归扫描阶段直接把它跳过（752）。两句话一起成立 =
/// 任何阶段都不激活，等于一条死条目。所以保存前挡住，让用户留一个。
bool tavernRecursionConflict({
  required bool excludeRecursion,
  required bool delayUntilRecursion,
}) => excludeRecursion && delayUntilRecursion;
