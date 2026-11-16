// AI 制卡 的纯逻辑：请求怎么组、模型的回答怎么变成一张卡。
// Run on the host: flutter test test/tavern_card_studio_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_app/tavern/tavern_card_studio.dart';

void main() {
  group('parse', () {
    test('a plain JSON object', () {
      final card = tavernCardParse(
        '{"name":"林晚","description":"二十四岁，短发","personality":"嘴硬",'
        '"scenario":"深夜的厨房","first_mes":"*掀开锅盖* 又饿了？",'
        '"mes_example":"<START>","alternate_greetings":["你也来一碗？"],'
        '"tags":["日常","治愈"],"creator_notes":"慢慢来"}',
      );
      expect(card, isNotNull);
      expect(card!['name'], '林晚');
      expect(card['personality'], '嘴硬');
      expect(card['tags'], ['日常', '治愈']);
      expect(card['alternate_greetings'], ['你也来一碗？']);
    });

    test('a fenced object with prose around it', () {
      final card = tavernCardParse(
        '好的，这是你的卡：\n```json\n{"name":"阿澈","description":"d"}\n```\n需要改什么告诉我。',
      );
      expect(card, isNotNull);
      expect(card!['name'], '阿澈');
      expect(card['description'], 'd');
      // Fields the model left out are empty, never missing.
      expect(card['personality'], '');
      expect(card['alternate_greetings'], isEmpty);
    });

    test('a card wrapped in CCv3 data', () {
      final card = tavernCardParse(
        '{"spec":"chara_card_v3","data":{"name":"沈青","description":"x"}}',
      );
      expect(card, isNotNull);
      expect(card!['name'], '沈青');
    });

    test('nonsense is null, not a guess', () {
      expect(tavernCardParse(''), isNull);
      expect(tavernCardParse('我不想写这个。'), isNull);
      // 只有描述、没有名字：现在给个占位名（能看、能改），不再整份丢掉。
      expect(tavernCardParse('{"description":"no name"}')!['name'], '未命名角色');
      expect(tavernCardParse('{broken json'), isNull);
    });

    test('drifted shapes are coerced', () {
      final card = tavernCardParse(
        '{"name":"  白露  ","tags":"日常,治愈、 慢热","alternate_greetings":"一\\n二"}',
      );
      expect(card!['name'], '白露');
      expect(card['tags'], ['日常', '治愈', '慢热']);
      expect(card['alternate_greetings'], ['一', '二']);
    });
  });

  group('request', () {
    test('快速创作 only carries the idea, in the reader’s language', () {
      final wish = TavernCardWish(idea: '隔壁的女大学生');
      expect(wish.isQuick, isTrue);
      final zh = tavernCardMessages(wish);
      expect(zh.first['role'], 'system');
      expect((zh.first['content']! as String), contains('{{user}}'));
      expect((zh.last['content']! as String), contains('隔壁的女大学生'));
      // Nothing the user did not choose reaches the model.
      for (final line in ['名字必须叫', '身份：', '世界观：', '性格必须包含']) {
        expect((zh.last['content']! as String), isNot(contains(line)));
      }

      final en = tavernCardMessages(
        TavernCardWish(idea: 'the girl next door', english: true),
      );
      expect((en.last['content']! as String), contains('the girl next door'));
      expect(
        (en.first['content']! as String),
        contains('Output one JSON object only'),
      );
    });

    test('高级创作 puts every chosen field in the brief', () {
      final wish = TavernCardWish(
        idea: '深夜还在营业的面馆老板',
        name: '沈青',
        identity: '面馆老板',
        world: '现代都市',
        relation: '邻居',
        traits: ['温柔', '毒舌'],
        extra: '白天睡觉，从不提自己的过去。',
      );
      expect(wish.isQuick, isFalse);
      final said = tavernCardMessages(wish).last['content']! as String;
      expect(said, contains('「沈青」'));
      expect(said, contains('身份：面馆老板'));
      expect(said, contains('世界观：现代都市'));
      expect(said, contains('关系：邻居'));
      expect(said, contains('性格必须包含：温柔、毒舌'));
      expect(said, contains('白天睡觉，从不提自己的过去。'));

      final english =
          tavernCardMessages(
                TavernCardWish(
                  idea: 'the noodle cook',
                  name: 'Shen',
                  world: 'Modern city',
                  english: true,
                ),
              ).last['content']!
              as String;
      expect(english, contains('Name: Shen exactly.'));
      expect(english, contains('Setting: Modern city.'));
    });

    test('the body carries a ceiling that grows with the length', () {
      expect(
        tavernCardRequestBody(const TavernCardWish(idea: 'x'))['max_tokens'],
        TavernCardLength.standard.maxTokens,
      );
      expect(
        tavernCardRequestBody(
          const TavernCardWish(idea: 'x', length: TavernCardLength.brief),
        )['max_tokens'],
        TavernCardLength.brief.maxTokens,
      );
      expect(
        tavernCardRequestBody(
          const TavernCardWish(idea: 'x', length: TavernCardLength.rich),
        )['max_tokens'],
        TavernCardLength.rich.maxTokens,
      );
      expect(
        TavernCardLength.brief.maxTokens,
        lessThan(TavernCardLength.standard.maxTokens),
      );
      expect(
        TavernCardLength.standard.maxTokens,
        lessThan(TavernCardLength.rich.maxTokens),
      );
    });
  });

  group('card', () {
    test('what the library is handed is a V2 card', () {
      final data = tavernCardParse(
        '{"name":"林晚","description":"d","tags":["a"]}',
      )!;
      final json = tavernCardJson(data, creator: 'AI 制卡');
      expect(json['spec'], 'chara_card_v2');
      expect(json['spec_version'], '2.0');
      final inner = json['data']! as Map<String, Object?>;
      expect(inner['name'], '林晚');
      expect(inner['creator'], 'AI 制卡');
      expect(inner['mes_example'], '');
      expect(inner['extensions'], isEmpty);
      // It must survive a round trip through the importer's JSON.
      expect(jsonDecode(jsonEncode(json)), isA<Map<String, Object?>>());
    });
  });

  group('截断修复（真实模型会撞 token 上限）', () {
    test('半个字符串 + 悬空顿号：补上引号和括号，能解析', () {
      const truncated =
          '{"name":"林晚","description":"短发，围裙上有酱油点。",'
          '"alternate_greetings":["*正蹲在门口择菜* 来了。"],'
          '"tags":["日常","邻居"],"creator_notes":"适合喜欢慢热日常的玩家、';
      final card = tavernCardParse(truncated);
      expect(card, isNotNull, reason: '截断的尾巴应该能修回来');
      expect(card!['name'], '林晚');
      expect(card['tags'], ['日常', '邻居']);
    });

    test('写到一半的 key：退到最后一个完整的值', () {
      const truncated =
          '{"name":"林晚","description":"短发。","tags":["日常"],"creator_not';
      final card = tavernCardParse(truncated);
      expect(card, isNotNull);
      expect(card!['name'], '林晚');
      expect(card['tags'], ['日常']);
    });

    test('写到一半的数组项：也退得回来', () {
      const truncated =
          '{"name":"林晚","description":"短发。","alternate_greetings":["第一句", "第二';
      final card = tavernCardParse(truncated);
      expect(card, isNotNull);
      // 半截的那一项会被补上引号保住（也接受只留第一句），关键是能解析。
      final greetings = (card!['alternate_greetings']! as List).cast<String>();
      expect(greetings.first, '第一句');
    });

    test('本来就不是 JSON 的，别硬修', () {
      expect(tavernCardRepair('好的，我来帮你写一张卡。'), isNull);
      expect(tavernCardParse('好的，我来帮你写一张卡。'), isNull);
    });

    test('完整 JSON 不会被改坏', () {
      const good = '{"name":"林晚","description":"短发。"}';
      expect(tavernCardRepair(good), isNull, reason: '没截断就别动手');
      expect(tavernCardParse(good)!['name'], '林晚');
    });
  });

  group('键名别名（中文提示下模型会翻译键名）', () {
    test('中文键名也认', () {
      final card = tavernCardParse(
        '{"名字":"灯塔看守人","描述":"在海边守了三十年灯。","性格":"沉默",'
        '"开场白":"*抬头看你* 灯还亮着。","标签":["海边","孤独"]}',
      );
      expect(card, isNotNull);
      expect(card!['name'], '灯塔看守人');
      expect(card['description'], '在海边守了三十年灯。');
      expect(card['first_mes'], '*抬头看你* 灯还亮着。');
      expect(card['tags'], ['海边', '孤独']);
    });

    test('camelCase / 别的英文写法也认', () {
      final card = tavernCardParse(
        '{"char_name":"Keeper","desc":"Thirty years of light.",'
        '"firstMessage":"*looks up* Still burning.","creatorNotes":"slow burn"}',
      );
      expect(card!['name'], 'Keeper');
      expect(card['first_mes'], '*looks up* Still burning.');
      expect(card['creator_notes'], 'slow burn');
    });

    test('没有名字但有内容：给占位名，别整份丢掉', () {
      final card = tavernCardParse('{"描述":"一个不爱说话的守灯人。"}');
      expect(card, isNotNull);
      expect(card!['name'], '未命名角色');
      expect(card['description'], '一个不爱说话的守灯人。');
    });

    test('什么都没有才算失败', () {
      expect(tavernCardParse('{"foo":"bar"}'), isNull);
    });
  });
}
