// 状态的显示名与编辑类型：卡片写的中文 title 要盖过内部键，撞名要能区分，
// 类型要能判出来（数字 / 枚举 / 布尔 / 列表 / 文本）。
//
//   flutter test test/tavern_state_hints_test.dart

import 'package:dsh_app/tavern/tavern_state_hints.dart';
import 'package:dsh_app/ui/tavern/tavern_state_editor.dart';
import 'package:flutter_test/flutter_test.dart';

const _schema = <String, Object?>{
  'type': 'object',
  'properties': {
    'affection': {
      'type': 'integer',
      'title': '好感',
      'minimum': -100,
      'maximum': 100,
    },
    'stamina': {'type': 'integer', 'title': '体力', 'minimum': 0, 'maximum': 100},
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
    'time': {'type': 'string', 'title': '时间'},
    'place': {'type': 'string', 'title': '地点'},
    // 没有 title 的：回退键名
    'hidden_flag': {'type': 'boolean'},
    // 和 mood 撞名，用来验去重
    'mood_copy': {'type': 'string', 'title': '心情'},
  },
};

void main() {
  group('显示名', () {
    test('有 title 就用 title，没有才用键名', () {
      expect(tavernStateLabel(_schema, '/affection', 'affection'), '好感');
      expect(
        tavernStateLabel(_schema, '/hidden_flag', 'hidden_flag'),
        'hidden_flag',
      );
      // 卡片没有 schema（老卡）：一律键名，和以前一样。
      expect(tavernStateLabel(null, '/affection', 'affection'), 'affection');
    });

    test('同层撞名补键名，不撞就不动', () {
      final labels = tavernStateLabels(_schema, '', [
        'affection',
        'mood',
        'mood_copy',
      ]);
      expect(labels[0], '好感');
      expect(labels[1], '心情（mood）');
      expect(labels[2], '心情（mood_copy）');
    });

    test('嵌套字段按 JSON Pointer 找得到自己的 title', () {
      const nested = <String, Object?>{
        'type': 'object',
        'properties': {
          'place': {
            'type': 'object',
            'title': '地点',
            'properties': {
              'name': {'type': 'string', 'title': '地名'},
            },
          },
        },
      };
      expect(tavernStateLabel(nested, '/place', 'place'), '地点');
      expect(tavernStateLabel(nested, '/place/name', 'name'), '地名');
      // 没有的就退回键名，不会串到父级去。
      expect(tavernStateLabel(nested, '/place/other', 'other'), 'other');
    });
  });

  group('编辑类型', () {
    Map<String, Object?>? node(String key) =>
        (tavernStateSchemaAt(_schema, '/$key'));

    test('schema 说是什么就是什么', () {
      expect(stateValueKind(node('affection'), 20), 'number');
      expect(stateValueKind(node('mood'), '平静'), 'enum');
      expect(stateValueKind(node('bag'), ['铜钥匙']), 'array');
      expect(stateValueKind(node('time'), '深夜'), 'string');
      expect(stateValueKind(node('hidden_flag'), false), 'boolean');
    });

    test('没有 schema 时按现有值的形状判断', () {
      expect(stateValueKind(null, 20), 'number');
      expect(stateValueKind(null, true), 'boolean');
      expect(stateValueKind(null, ['a']), 'array');
      expect(stateValueKind(null, 'x'), 'string');
      expect(stateValueKind(null, {'a': 1}), 'json');
      expect(stateValueKind(null, null), 'json');
    });

    test('枚举优先于 string：带 enum 的字符串要用选项而不是输入框', () {
      expect(stateValueKind(node('mood'), '平静'), 'enum');
      expect(stateValueKind({'type': 'string'}, '随便'), 'string');
    });
  });
}
