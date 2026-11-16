// 预设提示词的 AI：两种回答形状都要能用（JSON 或整段散文）。
//
//   flutter test test/preset_ai_test.dart

import 'package:dsh_app/tavern/preset_ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('解析', () {
    test('JSON 里的 content', () {
      expect(presetPromptParse('{"content":"你要写得短。"}'), '你要写得短。');
    });

    test('包在围栏里的 JSON 也认', () {
      expect(
        presetPromptParse('好的：\n```json\n{"content":"短句优先。"}\n```'),
        '短句优先。',
      );
    });

    test('模型直接回散文：整段当正文', () {
      expect(
        presetPromptParse('你要写得短。每段不超过三句。\n不要总结。'),
        '你要写得短。每段不超过三句。\n不要总结。',
      );
    });

    test('围栏包着散文：去掉围栏', () {
      expect(presetPromptParse('```\n第一句。\n第二句。\n```'), '第一句。\n第二句。');
    });

    test('空的、只有空白的都算失败', () {
      expect(presetPromptParse(''), isNull);
      expect(presetPromptParse('   \n  '), isNull);
      expect(presetPromptParse('{"content":"   "}'), isNull);
    });
  });

  group('提示', () {
    test('带上预设名、提示名、现在的内容和我的要求', () {
      final ask =
          presetPromptMessages(
                presetName: '我的预设',
                promptName: '主提示',
                current: '旧的写法。',
                action: PresetAiAction.write,
                instruction: '更冷一点',
              ).last['content']!
              as String;
      expect(ask, contains('我的预设'));
      expect(ask, contains('主提示'));
      expect(ask, contains('旧的写法。'));
      expect(ask, contains('更冷一点'));
      expect(ask, contains('从头写'));
    });

    test('扩写和精简要的东西不一样，但都说「规则别丢」', () {
      String askOf(PresetAiAction action) =>
          presetPromptMessages(
                presetName: 'p',
                promptName: 'n',
                current: '内容',
                action: action,
              ).last['content']!
              as String;
      expect(askOf(PresetAiAction.expand), contains('写长'));
      expect(askOf(PresetAiAction.trim), contains('七成'));
      expect(askOf(PresetAiAction.trim), contains('规则一条都不要丢'));
    });

    test('要求空着就不带那一段', () {
      final ask =
          presetPromptMessages(
                presetName: 'p',
                promptName: 'n',
                current: '',
                action: PresetAiAction.write,
              ).last['content']!
              as String;
      expect(ask, isNot(contains('我想要')));
    });
  });
}
