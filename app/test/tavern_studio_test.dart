// 创作层的地基：草稿怎么记、撤销怎么退、转换器怎么把字变成卡。
// 跑在宿主上，不用设备：flutter test test/tavern_studio_test.dart

import 'dart:convert';

import 'package:dsh_app/tavern/tavern_studio_build.dart';
import 'package:dsh_app/tavern/tavern_studio_draft.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一段刚好 [n] 字、且以句号结尾的中文，用来撑爆预算。
String para(int n) {
  final buffer = StringBuffer();
  while (buffer.length < n - 1) {
    buffer.write('很久以前发生过一件事。');
  }
  final text = buffer.toString();
  return '${text.substring(0, n - 1)}。';
}

StudioDraft filled() {
  final draft = StudioDraft();
  draft.setText('profile', 'name', '林晚');
  draft.setText('profile', 'nickname', '晚晚');
  draft.setText('profile', 'age', '24');
  draft.setText('profile', 'gender', '女');
  draft.setText('profile', 'identity', '面馆老板');
  draft.setText('profile', 'appearance', '短发，围裙上有洗不掉的酱油点。');
  draft.setText('profile', 'body', '左手腕有一道旧疤。');
  draft.setText('profile', 'habits', '半夜煮面，白天睡觉。');
  draft.setItems('mind', 'surface', ['嘴硬', '心软']);
  draft.setText('mind', 'inner', '怕被人需要之后又被丢下。');
  draft.setText('mind', 'flaw', '不肯先开口。');
  draft.setText('bond', 'initial', '隔壁新搬来的客人');
  draft.setText('bond', 'impression', '第一次来就点错了单，还硬说是店里的问题。');
  draft.setText('history', 'family', '母亲开过同一家面馆。');
  draft.setText('scene', 'meeting', '雨夜，她正往锅里添水。');
  draft.setItems('voice', 'tone', ['寡言', '偶尔毒舌']);
  draft.setText('voice', 'firstMes', '*掀开锅盖* 又饿了？');
  draft.setItems('scene', 'openings', ['你也来一碗？', '坐吧，别站着。']);
  draft.setItems('voice', 'samples', ['{{user}}: 还有面吗？\n{{char}}: 有，等五分钟。']);
  draft.setItems('rules', 'principles', ['不赊账']);
  draft.setItems('rules', 'interaction', ['先动手再说话']);
  return draft;
}

void main() {
  group('草稿', () {
    test('写进去读得出来，空值不留垃圾', () {
      final draft = StudioDraft();
      draft.setText('profile', 'name', '林晚');
      draft.setItems('mind', 'surface', ['嘴硬', '', '  ', '心软']);
      expect(draft.text('profile', 'name'), '林晚');
      expect(draft.items('mind', 'surface'), ['嘴硬', '心软'], reason: '空条目要丢掉');
      expect(draft.filledCount, 2);
      expect(draft.isEmpty, isFalse);
    });

    test('撤销只是一步一步退，退到底就不动了', () {
      final draft = StudioDraft();
      draft.setText('profile', 'a', '一');
      draft.setText('profile', 'a', '二');
      draft.setText('profile', 'a', '三');
      expect(draft.canUndo('profile', 'a'), isTrue);
      expect(draft.undo('profile', 'a'), isTrue);
      expect(draft.text('profile', 'a'), '二');
      expect(draft.undo('profile', 'a'), isTrue);
      expect(draft.text('profile', 'a'), '一');
      // 第一次写入时还没有上一版，所以到底了。
      expect(draft.undo('profile', 'a'), isFalse);
      expect(draft.text('profile', 'a'), '一');
    });

    test('值没变不记一步撤销', () {
      final draft = StudioDraft();
      draft.setText('profile', 'a', '一');
      draft.setText('profile', 'a', '一');
      expect(draft.canUndo('profile', 'a'), isFalse);
    });

    test('条目字段也能撤销，按行还原', () {
      final draft = StudioDraft();
      draft.setItems('mind', 'surface', ['嘴硬']);
      draft.setItems('mind', 'surface', ['嘴硬', '心软']);
      expect(draft.items('mind', 'surface'), ['嘴硬', '心软']);
      expect(draft.undo('mind', 'surface'), isTrue);
      expect(draft.items('mind', 'surface'), ['嘴硬']);
    });

    test('锁定的字段能被单独拎出来，做 AI 的约束', () {
      final draft = StudioDraft();
      draft.setText('profile', 'name', '林晚');
      draft.setText('profile', 'identity', '面馆老板');
      draft.setText('profile', 'identity', '');
      draft.toggleLock('profile', 'name');
      expect(draft.peek('profile', 'name')!.locked, isTrue);
      // 空的锁定字段不该进约束，否则提示里全是冒号。
      draft.toggleLock('profile', 'identity');
      expect(draft.lockedValues('profile'), {'name': '林晚'});
    });

    test('JSON 往返：锁、来源、撤销栈都还在，空字段不留', () {
      final draft = filled();
      draft.toggleLock('profile', 'appearance');
      final back = StudioDraft.fromJson(jsonDecode(jsonEncode(draft.toJson())));
      expect(back.text('profile', 'name'), '林晚');
      expect(back.peek('profile', 'appearance')!.locked, isTrue);
      expect(back.items('mind', 'surface'), ['嘴硬', '心软']);
      expect(back.items('voice', 'tone'), ['寡言', '偶尔毒舌']);
      final raw = back.toJson()['modules']! as Map;
      expect((raw['bond']! as Map)['trust'], isNull, reason: '没写的字段不该占地方');
    });

    test('烂 JSON 不炸，读成空草稿', () {
      expect(StudioDraft.fromJson(null).isEmpty, isTrue);
      expect(StudioDraft.fromJson({'modules': 42}).isEmpty, isTrue);
      expect(
        StudioDraft.fromJson({
          'modules': {
            'profile': {'name': '不是对象'},
          },
        }).isEmpty,
        isTrue,
      );
    });
  });

  group('转换器', () {
    test('空草稿只留一个名字，不编内容、不造世界书', () {
      final card = buildStudioCard(
        StudioDraft(),
        creator: 'AI 制卡',
        fallbackName: '新角色',
      );
      final data = card['data']! as Map<String, Object?>;
      expect(data['name'], '新角色');
      expect(data['description'], '');
      expect(data['first_mes'], '');
      expect(data.containsKey('character_book'), isFalse);
      // 草稿本身一定要跟着走，不然导出再导入就没了。
      expect((data['extensions']! as Map)['dshgo'], isNotNull);
    });

    test('描述按顺序拼：外观 → 身份 → 内在 → 关系 → 经历 → 缺陷', () {
      final card = buildStudioCard(filled(), creator: 'AI 制卡');
      final description = (card['data']! as Map)['description']! as String;
      final order = [
        '短发',
        '24 岁',
        '面馆老板',
        '怕被人需要',
        '隔壁新搬来的客人',
        '母亲开过同一家面馆',
        '不肯先开口',
      ].map(description.indexOf).toList();
      expect(order.every((at) => at >= 0), isTrue, reason: '每一段都该在描述里');
      for (var i = 1; i < order.length; i++) {
        expect(order[i], greaterThan(order[i - 1]), reason: '第 $i 段顺序不对');
      }
    });

    test('性格、场景、开场白、示例各就各位', () {
      final data =
          buildStudioCard(filled(), creator: 'AI 制卡')['data']!
              as Map<String, Object?>;
      expect(data['personality'], contains('嘴硬、心软'));
      expect(data['personality'], contains('寡言、偶尔毒舌'));
      expect(data['scenario'], contains('雨夜'));
      expect(data['first_mes'], contains('又饿了'));
      expect((data['alternate_greetings']! as List), ['你也来一碗？', '坐吧，别站着。']);
      expect(data['mes_example'], startsWith('<START>'));
      expect(data['mes_example'], contains('{{char}}'));
      expect(data['system_prompt'], contains('不赊账'));
      expect(data['post_history_instructions'], contains('先动手再说话'));
      expect((data['tags']! as List), ['嘴硬', '心软', '寡言', '偶尔毒舌']);
    });

    test('写得太多就按顺序裁：先砍经历，再砍内在，最后拒绝保存', () {
      final draft = filled();
      // 每段都顶到预算上限，加起来约 960 字，超过默认的 900。
      draft.setText('profile', 'appearance', para(160));
      draft.setText('profile', 'body', para(120));
      draft.setText('mind', 'inner', para(160));
      draft.setText('bond', 'impression', para(140));
      draft.setText('history', 'family', para(140));
      draft.setText('history', 'upbringing', para(140));
      draft.setText('mind', 'flaw', para(80));

      String describe(int cap) =>
          (buildStudioCard(draft, creator: 'x', descriptionCap: cap)['data']!
                  as Map)['description']!
              as String;

      // 默认上限：压到 900 以内，第一步就是砍经历（每段只留 40 字）。
      final normal = describe(studioDescriptionCap);
      expect(normal.length, lessThanOrEqualTo(studioDescriptionCap));
      expect(normal, isNot(contains(para(140))), reason: '经历应该被压短了');

      // 再紧一点：内在性格只留一句。
      final tight = describe(400);
      expect(tight.length, lessThanOrEqualTo(400));

      // 紧到不可能：报错，而不是写出半句话的卡。
      expect(
        () => buildStudioCard(draft, creator: 'x', descriptionCap: 60),
        throwsA(isA<StudioBuildError>()),
      );
    });

    test('世界规则进书且常驻，地点按 `关键词|正文` 拆', () {
      final draft = filled();
      draft.setItems('world', 'worldRules', ['夜里不接生客。']);
      draft.setItems('world', 'places', ['后厨｜只有她能进，灶台是老式的', '阁楼']);
      final entries =
          ((buildStudioCard(draft, creator: 'x')['data']!
                      as Map)['character_book']!
                  as Map)['entries']!
              as List;
      expect(entries, hasLength(3));

      final rules = entries.first as Map<String, Object?>;
      expect(rules['constant'], isTrue);
      expect(rules['position'], 'before_char');
      expect(rules['keys'], ['夜里不接生客']);

      final kitchen = entries[1] as Map<String, Object?>;
      expect(kitchen['keys'], ['后厨']);
      expect(kitchen['content'], '只有她能进，灶台是老式的');
      expect(kitchen['constant'], isFalse);

      // 没写关键词的：拿正文开头几个字兜底。
      final attic = entries[2] as Map<String, Object?>;
      expect(attic['keys'], ['阁楼']);
    });

    test('条目有上限，超了不会无限长', () {
      final draft = filled();
      draft.setItems('world', 'places', [for (var i = 0; i < 40; i++) '地点$i']);
      final entries =
          ((buildStudioCard(draft, creator: 'x')['data']!
                      as Map)['character_book']!
                  as Map)['entries']!
              as List;
      expect(entries.length, lessThanOrEqualTo(studioBookLimit));
    });

    test('没有关键词的整段文字（能力/秘密）先不进书', () {
      final draft = filled();
      draft.setText('profile', 'ability', '闭着眼也能把面下到刚好。');
      draft.setText('history', 'secret', '她母亲的店其实是被烧掉的。');
      final data = buildStudioCard(draft, creator: 'x')['data']! as Map;
      expect(data.containsKey('character_book'), isFalse);
      // 但这些字没丢，还在草稿里。
      final studio =
          ((data['extensions']! as Map)['dshgo']! as Map)['studio']! as Map;
      final back = StudioDraft.fromJson(studio);
      expect(back.text('history', 'secret'), contains('烧掉'));
    });

    test('草稿里带状态，转换器写进 extensions.dshgo.state', () {
      final draft = filled();
      draft.state = {
        'schema': {
          'type': 'object',
          'properties': {
            'affection': {
              'type': 'integer',
              'title': '好感',
              'minimum': -100,
              'maximum': 100,
            },
          },
        },
        'init': {'affection': 20},
      };
      final data = buildStudioCard(draft, creator: 'x')['data']! as Map;
      final dshgo = (data['extensions']! as Map)['dshgo']! as Map;
      expect((dshgo['state']! as Map)['init'], {'affection': 20});
      // 草稿 JSON 往返之后状态还在
      final back = StudioDraft.fromJson(dshgo['studio']);
      expect(back.state, isNotNull);
    });

    test('没有状态就不写这个键', () {
      final data = buildStudioCard(filled(), creator: 'x')['data']! as Map;
      final dshgo = (data['extensions']! as Map)['dshgo']! as Map;
      expect(dshgo.containsKey('state'), isFalse);
    });

    test('卡片能过一遍 JSON，草稿原样回来', () {
      final draft = filled();
      final card = buildStudioCard(draft, creator: 'AI 制卡');
      final decoded = jsonDecode(jsonEncode(card)) as Map<String, Object?>;
      final data = decoded['data']! as Map<String, Object?>;
      final studio = ((data['extensions']! as Map)['dshgo']! as Map)['studio'];
      final back = StudioDraft.fromJson(studio);
      expect(back.text('profile', 'name'), '林晚');
      expect(back.items('voice', 'samples'), draft.items('voice', 'samples'));
      expect(back.text('scene', 'meeting'), '雨夜，她正往锅里添水。');
    });
  });
}
