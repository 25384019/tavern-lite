// 世界书 AI 的解析：蓝图 / 规划 / 一批条目 / 审查 / 单条条目，以及折成 ST 原生 entries。
//
//   flutter test test/lorebook_ai_test.dart

import 'dart:convert';

import 'package:dsh_app/tavern/lorebook_ai.dart';
import 'package:flutter_test/flutter_test.dart';

const _blueprint = LorebookBlueprint(
  name: '雨港',
  overview: '一年下三百天雨的海港城，靠盐和船活着。',
  rules: ['雨港没有晴天', '盐比钱硬'],
  factions: ['盐行', '船帮'],
  places: ['码头', '后厨'],
  conflicts: ['盐行要涨税，船帮不干'],
);

void main() {
  group('蓝图', () {
    test('名字和概述都要，列表缺了就是空', () {
      final blueprint = lorebookBlueprintParse(
        '{"name":"雨港","overview":"一年下三百天雨。","rules":["没有晴天"],'
        '"factions":[],"places":["码头"],"conflicts":[]}',
      );
      expect(blueprint, isNotNull);
      expect(blueprint!.name, '雨港');
      expect(blueprint.rules, ['没有晴天']);
      expect(blueprint.factions, isEmpty);
      expect(blueprint.places, ['码头']);
    });

    test('名字空着就用兜底名，不算失败', () {
      final blueprint = lorebookBlueprintParse('{"overview":"一个地方。"}');
      expect(blueprint!.name, '新的世界');
    });

    test('什么都没有才算失败', () {
      expect(lorebookBlueprintParse('{"name":"","overview":""}'), isNull);
      expect(lorebookBlueprintParse('好的，我来帮你写。'), isNull);
    });

    test('围栏和前后废话都救得回来', () {
      final blueprint = lorebookBlueprintParse(
        '好的：\n```json\n{"name":"雨港","overview":"一个地方。"}\n```\n希望有用',
      );
      expect(blueprint!.name, '雨港');
    });
  });

  group('规划', () {
    test('只收有标题的，重名的去掉', () {
      final plan = lorebookPlanParse(
        '{"entries":[{"title":"码头","kind":"place","why":"开场"},'
        '{"title":"码头"},{"title":"  "},{"title":"盐行","kind":"faction"}]}',
      );
      expect(plan.map((e) => e.title), ['码头', '盐行']);
      expect(plan.first.kind, 'place');
      expect(plan.first.why, '开场');
    });

    test('提示里带上蓝图和条数', () {
      final ask =
          lorebookPlanMessages(
                blueprint: _blueprint,
                target: 6,
              ).last['content']!
              as String;
      expect(ask, contains('雨港'));
      expect(ask, contains('6'));
      expect(ask, contains('"entries"'));
    });
  });

  group('一批条目', () {
    test('没有正文的丢掉，关键词和常驻都认', () {
      final entries = lorebookBatchParse(
        '{"entries":[{"title":"码头","content":"潮水一天两次。","keys":["码头","潮水"]},'
        '{"title":"空的","content":"   "},'
        '{"title":"雨","content":"一年下三百天雨。","constant":true}]}',
      );
      expect(entries, hasLength(2));
      expect(entries.first.keys, ['码头', '潮水']);
      expect(entries.last.constant, isTrue);
    });

    test('一次超过上限就截到 8 条', () {
      final many = {
        'entries': [
          for (var i = 0; i < 20; i++) {'title': '条$i', 'content': '内容$i'},
        ],
      };
      final entries = lorebookBatchParse(jsonEncode(many));
      expect(entries, hasLength(lorebookBatchLimit));
    });

    test('提示里列清楚要写哪几条', () {
      final ask =
          lorebookBatchMessages(
                blueprint: _blueprint,
                entries: const [
                  LorebookPlanEntry(title: '码头', kind: 'place'),
                  LorebookPlanEntry(title: '盐行', kind: 'faction'),
                ],
              ).last['content']!
              as String;
      expect(ask, contains('码头'));
      expect(ask, contains('盐行'));
      expect(ask, contains('constant'));
    });
  });

  group('审查', () {
    test('只收说得清问题的', () {
      final issues = lorebookCheckParse(
        '{"issues":[{"title":"码头","issue":"和规则「没有晴天」冲突","suggest":"改成阴天"},'
        '{"title":"盐行","issue":""}]}',
      );
      expect(issues, hasLength(1));
      expect(issues.single.suggest, '改成阴天');
    });

    test('提示里带现有的条目', () {
      final ask =
          lorebookCheckMessages(
                blueprint: _blueprint,
                entries: const [
                  LorebookDraftEntry(title: '码头', content: '潮水一天两次。'),
                ],
              ).last['content']!
              as String;
      expect(ask, contains('码头'));
      expect(ask, contains('"issues"'));
    });
  });

  group('折成 ST 原生条目', () {
    test('uid 连续、关键词、位置按常驻走', () {
      final json = lorebookEntriesJson(const [
        LorebookDraftEntry(title: '码头', content: '潮水一天两次。', keys: ['码头', '潮水']),
        LorebookDraftEntry(title: '雨', content: '一年下三百天雨。', constant: true),
      ]);
      expect(json.keys, ['0', '1']);
      final first = json['0']! as Map<String, Object?>;
      expect(first['uid'], 0);
      expect(first['comment'], '码头');
      expect(first['key'], ['码头', '潮水']);
      expect(first['constant'], isFalse);
      expect(first['position'], 1);
      expect(first['disable'], isFalse);
      final second = json['1']! as Map<String, Object?>;
      expect(second['constant'], isTrue);
      expect(second['position'], 0, reason: '常驻的放前面');
    });
  });

  group('单条条目', () {
    test('提示带上世界名、条目名、关键词和现有内容', () {
      final ask =
          lorebookEntryAiMessages(
                worldName: '雨港',
                title: '码头',
                keys: const ['码头', '潮水'],
                current: '潮水一天两次。',
                action: LorebookEntryAiAction.expand,
              ).last['content']!
              as String;
      expect(ask, contains('雨港'));
      expect(ask, contains('码头'));
      expect(ask, contains('潮水一天两次。'));
      expect(ask, contains('写长'));
    });

    test('关键词那一种要的是逗号分隔的几个词', () {
      final ask =
          lorebookEntryAiMessages(
                worldName: '雨港',
                title: '码头',
                keys: const [],
                current: '',
                action: LorebookEntryAiAction.keywords,
              ).last['content']!
              as String;
      expect(ask, contains('关键词'));
      expect(ask, contains('逗号'));
    });

    test('回答解析：JSON、围栏、散文都收', () {
      expect(aiProseParse('{"content":"潮水一天两次。"}'), '潮水一天两次。');
      expect(aiProseParse('```\n潮水一天两次。\n```'), '潮水一天两次。');
      expect(aiProseParse('潮水一天两次。'), '潮水一天两次。');
      expect(aiProseParse('  '), isNull);
    });

    test('关键词解析：逗号、顿号、换行都拆，太长的不算关键词', () {
      final keys = aiKeysParse('码头，潮水、盐行\n这是一个明显太长了不像关键词的句子');
      expect(keys, ['码头', '潮水', '盐行']);
    });
  });
}
