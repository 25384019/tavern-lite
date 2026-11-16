// 状态模板：折成卡片里的 extensions.dshgo.state，能读回来，键和类型不出错。
//
//   flutter test test/state_templates_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:dsh_app/tavern/state_templates.dart';
import 'package:flutter_test/flutter_test.dart';

StateTemplate sample() => StateTemplate(
  id: 'tpl-1',
  name: '客栈日常',
  fields: [
    StateField(
      key: 'affection',
      title: '好感',
      type: StateFieldType.number,
      initial: 20,
      min: -100,
      max: 100,
    ),
    StateField(
      key: 'mood',
      title: '心情',
      type: StateFieldType.choice,
      initial: '平静',
      options: ['平静', '高兴'],
    ),
    StateField(
      key: 'bag',
      title: '背包',
      type: StateFieldType.list,
      initial: ['铜钥匙'],
    ),
    StateField(
      key: 'isOpen',
      title: '营业中',
      type: StateFieldType.boolean,
      initial: true,
    ),
    StateField(
      key: 'place',
      title: '地点',
      type: StateFieldType.text,
      initial: '大堂',
    ),
  ],
);

void main() {
  group('折成卡片的 state', () {
    test('schema 和 init 对得上每一项', () {
      final state = sample().toState();
      final schema = state['schema']! as Map<String, Object?>;
      final properties = schema['properties']! as Map<String, Object?>;
      expect(properties.keys, ['affection', 'mood', 'bag', 'isOpen', 'place']);

      final affection = properties['affection']! as Map<String, Object?>;
      expect(affection['type'], 'integer');
      expect(affection['title'], '好感');
      expect(affection['minimum'], -100);
      expect(affection['maximum'], 100);
      expect(affection['default'], 20);

      final mood = properties['mood']! as Map<String, Object?>;
      expect(mood['enum'], ['平静', '高兴']);

      final bag = properties['bag']! as Map<String, Object?>;
      expect(bag['type'], 'array');
      expect((bag['items']! as Map)['type'], 'string');

      final init = state['init']! as Map<String, Object?>;
      expect(init, {
        'affection': 20,
        'mood': '平静',
        'bag': ['铜钥匙'],
        'isOpen': true,
        'place': '大堂',
      });
    });

    test('初始值不合法就退回默认，不写坏卡', () {
      final template = StateTemplate(
        id: 'x',
        name: 'x',
        fields: [
          StateField(
            key: 'a',
            title: 'A',
            type: StateFieldType.number,
            initial: '不是数字',
            min: 5,
            max: 10,
          ),
          StateField(
            key: 'b',
            title: 'B',
            type: StateFieldType.boolean,
            initial: 'true',
          ),
          StateField(
            key: 'c',
            title: 'C',
            type: StateFieldType.choice,
            initial: '不在选项里',
            options: ['甲', '乙'],
          ),
          StateField(
            key: 'd',
            title: 'D',
            type: StateFieldType.list,
            initial: '甲，乙、 丙',
          ),
        ],
      );
      final init = template.toState()['init']! as Map<String, Object?>;
      expect(init['a'], 5, reason: '解析不了就用最小值');
      expect(init['b'], false);
      expect(init['c'], '甲');
      expect(init['d'], ['甲', '乙', '丙'], reason: '字符串按标点拆');
    });
  });

  group('往返', () {
    test('模板 JSON 来回一趟不丢东西', () {
      final back = StateTemplate.fromJson(
        jsonDecode(jsonEncode(sample().toJson())) as Map<String, Object?>,
      );
      expect(back.name, '客栈日常');
      expect(back.fields.map((f) => f.key), [
        'affection',
        'mood',
        'bag',
        'isOpen',
        'place',
      ]);
      expect(back.fields.first.min, -100);
      expect(back.fields.first.max, 100);
      expect(back.fields[1].options, ['平静', '高兴']);
      expect(back.fields[2].type, StateFieldType.list);
    });

    test('从一张老卡的 state 读成模板（老卡兼容）', () {
      final state = {
        'schema': {
          'type': 'object',
          'properties': {
            'affection': {
              'type': 'integer',
              'title': '好感',
              'minimum': -100,
              'maximum': 100,
            },
            'mood': {
              'type': 'string',
              'title': '心情',
              'enum': ['平静', '高兴'],
            },
            'bag': {
              'type': 'array',
              'title': '背包',
              'items': {'type': 'string'},
            },
            'secret': {'type': 'boolean', 'title': '秘密', 'x-dsh-hidden': true},
          },
        },
        'init': {
          'affection': 20,
          'mood': '平静',
          'bag': <String>[],
          'secret': false,
        },
      };
      final template = StateTemplate.fromState(
        state,
        id: 'tpl-old',
        name: '老卡',
      );
      expect(template, isNotNull);
      expect(template!.fields, hasLength(4));
      expect(template.fields.first.type, StateFieldType.number);
      expect(template.fields[1].type, StateFieldType.choice);
      expect(template.fields[3].hidden, isTrue);
      // 再折回去，形状还是原来的样子
      final again = template.toState();
      final props = (again['schema']! as Map)['properties']! as Map;
      expect(props.keys, ['affection', 'mood', 'bag', 'secret']);
    });

    test('没有 state 的卡读不出模板', () {
      expect(StateTemplate.fromState(null, id: 'x', name: 'x'), isNull);
      expect(
        StateTemplate.fromState({'schema': {}}, id: 'x', name: 'x'),
        isNull,
      );
    });
  });

  group('自检', () {
    test('键为空、重复、非法字符、范围反了、枚举没选项都要报', () {
      final bad = StateTemplate(
        id: 'x',
        name: 'x',
        fields: [
          StateField(key: '', title: '空键', type: StateFieldType.text),
          StateField(key: 'a', title: 'A', type: StateFieldType.number),
          StateField(key: 'a', title: '重复的 A', type: StateFieldType.number),
          StateField(key: '1abc', title: '非法', type: StateFieldType.text),
          StateField(
            key: 'range',
            title: '范围反了',
            type: StateFieldType.number,
            min: 10,
            max: 1,
          ),
          StateField(key: 'choice', title: '枚举', type: StateFieldType.choice),
        ],
      );
      final issues = stateTemplateIssues(bad);
      expect(issues.any((i) => i.contains('没有内部键')), isTrue);
      expect(issues.any((i) => i.contains('重复')), isTrue);
      expect(issues.any((i) => i.contains('字母')), isTrue);
      expect(issues.any((i) => i.contains('最小值比最大值大')), isTrue);
      expect(issues.any((i) => i.contains('没有选项')), isTrue);
    });

    test('正常模板没有问题', () {
      expect(stateTemplateIssues(sample()), isEmpty);
    });
  });

  group('存储', () {
    late Directory dir;
    late StateTemplateStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('state_templates');
      store = StateTemplateStore(dir);
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('没写过就是空的', () async {
      expect(await store.read(), isEmpty);
    });

    test('写了读得回来', () async {
      await store.write([sample()]);
      final back = await store.read();
      expect(back, hasLength(1));
      expect(back.single.name, '客栈日常');
      expect(back.single.fields, hasLength(5));
    });

    test('坏文件当没有', () async {
      await File('${dir.path}/state_templates.json').writeAsString('[');
      expect(await store.read(), isEmpty);
    });

    test('id 不重复', () {
      final ids = {for (var i = 0; i < 50; i++) newStateTemplateId(i)};
      expect(ids, hasLength(50));
    });
  });
}
