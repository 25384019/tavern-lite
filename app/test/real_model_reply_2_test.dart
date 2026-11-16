// 第二份真实原文（2026-11-16 22:0x，主人复测「陈望海」）：
// 截断在 personality 里，描述里有 {{user}}。
//
//   flutter test test/real_model_reply_2_test.dart

import 'package:dsh_app/tavern/tavern_card_studio.dart';
import 'package:flutter_test/flutter_test.dart';

const _reply = '''{
  "name": "陈望海",
  "description": "陈望海，四十二岁，雾港灯塔的守塔人。他身材高大却习惯微微弓着背，像总在低头看路。他起初戒备，但见{{user}}并无恶意，便默许了这场意外的相遇。",
  "personality": "陈望海寡言少语，说话前总要先沉默几秒，声音低沉平缓，像怕惊动什么。口头禅是"慢点来"。他表面疏离，实则心软，见人受冷会默默烧水，嘴上却只说"顺便"。他极度珍视灯塔的规律，每晚十点必去检查灯芯，雷打不动。心里''';

void main() {
  test('陈望海那份原文：能解析出名字、描述和性格', () {
    final card = tavernCardParse(_reply);
    expect(card, isNotNull, reason: '这份原文必须能救回来');
    expect(card!['name'], '陈望海');
    expect(card['description'], contains('雾港灯塔的守塔人'));
    expect(card['personality'], contains('口头禅'));
    expect(card['personality'], contains('雷打不动'));
  });

  test('没有 {{user}} 时同样能解析（对照组）', () {
    const plain = '''{
  "name": "陈望海",
  "description": "雾港灯塔的守塔人。",
  "personality": "寡言少语，口头禅是"慢点来"。每晚十点检查灯芯，心里''';
    final card = tavernCardParse(plain);
    expect(card!['name'], '陈望海');
    expect(card['personality'], contains('慢点来'));
  });
}
