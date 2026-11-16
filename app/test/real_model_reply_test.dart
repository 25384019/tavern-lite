// 真实模型的原文长什么样，就按那个样子测：内层引号没转义 + 结尾被截断。
//
//   flutter test test/real_model_reply_test.dart
//
// 样本来自 2026-11-16 真机实测（DeepSeek）：「陆怀灯」那次失败的原始回复。

import 'package:dsh_app/tavern/tavern_card_studio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('真实原文：内层引号没转义 + 结尾截断，也能解析出卡', () {
    const reply = '''{
  "name": "陆怀灯",
  "description": "陆怀灯，三十四岁，身形清瘦，常年穿着洗得发白的靛蓝灯塔制服。{{user}}是三个月前漂到港口的陌生人。",
  "personality": "说话慢，尾音常吞掉半个字，习惯用"嗯"开头。口头禅是"灯亮着呢"。嘴上硬，总说"别添乱"，心里却把每个人的船期记得比潮汐表还清。最怕听见
''';
    final card = tavernCardParse(reply);
    expect(card, isNotNull, reason: '真实现场的原文要能救回来');
    expect(card!['name'], '陆怀灯');
    expect(card['description'], contains('靛蓝灯塔制服'));
    expect(card['personality'], contains('口头禅'), reason: '截断前写好的性格也要拿回来');
  });

  test('内层引号但没截断', () {
    const reply = '{"name":"A","personality":"习惯用"嗯"开头，口头禅是"灯亮着呢"。"}';
    final card = tavernCardParse(reply);
    expect(card, isNotNull);
    expect(card!['personality'], contains('嗯'));
    expect(card['personality'], contains('灯亮着呢'));
  });

  test('正常的 JSON 不受影响', () {
    final card = tavernCardParse('{"name":"A","personality":"用「嗯」开头"}');
    expect(card!['personality'], '用「嗯」开头');
  });

  test('兜底扫描：截断在字符串里也取值', () {
    final card = tavernCardParse('{"name":"A","personality":"说到一半');
    expect(card, isNotNull);
    expect(card!['personality'], '说到一半');
  });

  test('兜底扫描：内层引号 + 截断', () {
    final card = tavernCardParse('{"name":"A","personality":"用"嗯"开头，说着说着');
    expect(card, isNotNull);
    expect(card!['personality'], contains('说着说着'));
  });

  test('什么都没有才算失败', () {
    expect(tavernCardParse('我不想写这个。'), isNull);
  });
}
