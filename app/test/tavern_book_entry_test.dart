// 条目在两种形状之间的搬运：卡内书（CC v3 的字段名）↔ ST 原生书（key/order/...）。
// 这是"同一份编辑器既能编卡内书、也能编资源库里的书"的唯一依据，所以单独测。
//
//   flutter test test/tavern_book_entry_test.dart

import 'package:dsh_app/tavern/tavern_book_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('原生 → 卡片：顶层字段换个名字，ST 自己的一套搬进 extensions', () {
    final card = tavernNativeToCard({
      'uid': 3,
      'key': ['码头', '潮水'],
      'keysecondary': ['夜'],
      'content': '潮水一天两次。',
      'comment': '码头',
      'order': 90,
      'disable': true,
      'position': 3,
      'depth': 6,
      'probability': 40,
      'excludeRecursion': true,
      'preventRecursion': true,
      'delayUntilRecursion': true,
      'group': '港口',
      'groupOverride': true,
      'groupWeight': 40,
      'scanDepth': 2,
      'sticky': 3,
      'cooldown': 4,
      'delay': 5,
      'use_regex': true,
    });
    expect(card['keys'], ['码头', '潮水']);
    expect(card['secondary_keys'], ['夜']);
    expect(card['insertion_order'], 90);
    expect(card['enabled'], isFalse, reason: 'ST 的 disable 就是卡片的 enabled 反面');
    expect(card['position'], 'after_char');
    final ext = card['extensions']! as Map<String, Object?>;
    expect(ext['depth'], 6);
    expect(ext['probability'], 40);
    // 这一轮新接上的专业字段，一个都不能在路上丢。
    expect(ext['exclude_recursion'], true);
    expect(ext['prevent_recursion'], true);
    expect(ext['delay_until_recursion'], true);
    expect(ext['group'], '港口');
    expect(ext['group_override'], true);
    expect(ext['group_weight'], 40);
    expect(ext['scan_depth'], 2);
    expect(ext['sticky'], 3);
    expect(ext['cooldown'], 4);
    expect(ext['delay'], 5);
    expect(ext['use_regex'], true);
  });

  test('卡片 → 原生：extensions 里的东西回到顶层，位置词换成数字', () {
    final native = tavernCardToNative({
      'comment': '码头',
      'keys': ['码头'],
      'secondary_keys': <String>[],
      'selective': false,
      'content': '潮水一天两次。',
      'constant': false,
      'enabled': true,
      'insertion_order': 100,
      'position': 'after_char',
      'extensions': <String, Object?>{
        'position': 3,
        'exclude_recursion': true,
        'group': '港口',
        'group_weight': 40,
        'sticky': 2,
        'use_regex': true,
      },
    });
    expect(native['key'], ['码头']);
    expect(native['order'], 100);
    expect(native['disable'], false);
    expect(native['excludeRecursion'], true);
    expect(native['group'], '港口');
    expect(native['groupWeight'], 40);
    expect(native['sticky'], 2);
    expect(native['use_regex'], true);
    // 卡片自己的位置词不留：数字版的 position 说得更准。
    expect(native.containsKey('position'), isTrue);
    expect(native['position'], 3);
  });

  test('原地合并：extensions 往下合一层，别的直接换', () {
    final merged = tavernMergeEntry(
      {
        'content': '旧',
        'extensions': {'group': '旧组', 'sticky': 1},
      },
      {
        'content': '新',
        'extensions': {'cooldown': 9},
      },
    );
    expect(merged['content'], '新');
    final ext = merged['extensions']! as Map<String, Object?>;
    expect(ext['group'], '旧组', reason: '没改的扩展字段要留住');
    expect(ext['sticky'], 1);
    expect(ext['cooldown'], 9);
  });

  test('走一圈回来还是原来的样子（新字段也一样）', () {
    final original = <String, Object?>{
      'comment': '码头',
      'key': ['码头'],
      'keysecondary': <String>[],
      'selective': false,
      'content': '潮水一天两次。',
      'constant': false,
      'disable': false,
      'order': 100,
      'position': 0,
      'excludeRecursion': true,
      'group': '港口',
      'groupWeight': 40,
      'sticky': 2,
      'cooldown': 3,
      'delay': 4,
      'scanDepth': 2,
      'use_regex': true,
    };
    final back = tavernCardToNative(tavernNativeToCard(original));
    for (final key in [
      'comment',
      'constant',
      'order',
      'excludeRecursion',
      'group',
      'groupWeight',
      'sticky',
      'cooldown',
      'delay',
      'scanDepth',
      'use_regex',
    ]) {
      expect(back[key], original[key], reason: '$key 在路上丢了');
    }
  });

  group('递归层级', () {
    // 引擎的 delayUntilRecursion 是数字：true 只是老写法的 1。
    // 编辑页把它当布尔读会把 2 悄悄变成 false——那是在弄坏别人的书。
    test('读：true 当 1，数字原样，别的当 0', () {
      expect(tavernBookRecursionLevel(true), 1);
      expect(tavernBookRecursionLevel(2), 2);
      expect(tavernBookRecursionLevel(0), 0);
      expect(tavernBookRecursionLevel(null), 0);
      expect(tavernBookRecursionLevel(false), 0);
      expect(tavernBookRecursionLevel('3'), 0);
      expect(tavernBookRecursionLevel(-1), 0);
    });

    test('写：原来 true 且还是 1 就继续写 true，形状不变', () {
      expect(tavernBookRecursionValue(1, true), true);
      expect(tavernBookRecursionValue(2, true), 2);
      expect(tavernBookRecursionValue(1, 2), 1);
      expect(tavernBookRecursionValue(0, 2), 0);
      expect(tavernBookRecursionValue(0, null), 0);
    });

    test('只改名字不动层级：读进来多少，写回去还是多少', () {
      for (final was in <Object?>[true, 2, 0]) {
        final level = tavernBookRecursionLevel(was);
        expect(tavernBookRecursionValue(level, was), was);
      }
    });
  });

  group('递归冲突', () {
    // 引擎里：delayUntilRecursion 只在递归阶段考虑（world_info.dart 741），
    // excludeRecursion 又在递归阶段跳过（752）。两个一起 = 永不激活。
    test('只在递归里出现 + 递归里跳过 = 死条目，要挡住', () {
      expect(
        tavernRecursionConflict(
          excludeRecursion: true,
          delayUntilRecursion: true,
        ),
        isTrue,
      );
    });

    test('只开一个都合法', () {
      expect(
        tavernRecursionConflict(
          excludeRecursion: true,
          delayUntilRecursion: false,
        ),
        isFalse,
      );
      expect(
        tavernRecursionConflict(
          excludeRecursion: false,
          delayUntilRecursion: true,
        ),
        isFalse,
      );
      expect(
        tavernRecursionConflict(
          excludeRecursion: false,
          delayUntilRecursion: false,
        ),
        isFalse,
      );
    });
  });
}
