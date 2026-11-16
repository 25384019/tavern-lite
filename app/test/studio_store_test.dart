// 草稿的存放：本地未存草稿、卡片里的那份、以及"按标题去重"的补条目。
//
//   flutter test test/studio_store_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dsh_app/tavern/studio_store.dart';
import 'package:dsh_app/tavern/tavern_studio_draft.dart';
import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter_test/flutter_test.dart';

const _card = {
  'spec': 'chara_card_v3',
  'spec_version': '3.0',
  'data': {
    'name': '林晚',
    'description': '',
    'personality': '',
    'scenario': '',
    'first_mes': '',
    'mes_example': '',
    'creator_notes': '',
    'system_prompt': '',
    'post_history_instructions': '',
    'alternate_greetings': <String>[],
    'tags': <String>[],
    'creator': '',
    'character_version': '1.0',
    'extensions': {
      'dshgo': {
        'state': {'v': 1},
      },
    },
    'character_book': {
      'entries': [
        {
          'id': 0,
          'comment': '码头',
          'keys': ['码头'],
          'content': 'x',
        },
      ],
    },
  },
};

void main() {
  group('本地草稿', () {
    late Directory dir;
    late StudioDraftStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('studio_store');
      store = StudioDraftStore(Directory('${dir.path}/studio'));
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('没写过就读不到', () async {
      expect(await store.read(), isNull);
    });

    test('写了读得回来，字段和锁定都在', () async {
      final draft = StudioDraft();
      draft.setText('profile', 'name', '林晚');
      draft.toggleLock('profile', 'name');
      draft.addBookEntry(StudioBookEntry(title: '码头', content: '潮水一天两次。'));
      await store.write(draft);

      final back = (await store.read())!;
      expect(back.text('profile', 'name'), '林晚');
      expect(back.peek('profile', 'name')!.locked, isTrue);
      expect(back.book.single.title, '码头');
    });

    test('空草稿 = 清掉，不留空壳', () async {
      final draft = StudioDraft()..setText('profile', 'name', '林晚');
      await store.write(draft);
      expect(await store.read(), isNotNull);
      await store.write(StudioDraft());
      expect(await store.read(), isNull);
      expect(await store.directory.exists(), isTrue);
    });

    test('文件坏了当没有，不让工作室打不开', () async {
      await store.directory.create(recursive: true);
      await File('${store.directory.path}/draft.json')
          .writeAsString('{不是 json');
      expect(await store.read(), isNull);
    });

    test('清掉之后真的没了', () async {
      final draft = StudioDraft()..setText('profile', 'name', '林晚');
      await store.write(draft);
      await store.clear();
      expect(await store.read(), isNull);
    });
  });

  group('卡片里的草稿', () {
    late Directory dir;
    late Tavern tavern;
    late String id;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('studio_card');
      tavern = await openTavern('${dir.path}/tavern');
      id = (await tavern.importCard(
        Uint8List.fromList(utf8.encode(jsonEncode(_card))),
        fileName: 'card.json',
      )).id;
    });

    tearDown(() async {
      await tavern.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('没写过就是空草稿', () async {
      expect((await loadStudioDraftFromCard(tavern, id)).isEmpty, isTrue);
    });

    test('写回去读得回来，而且不碰 state', () async {
      final draft = StudioDraft()..setText('profile', 'appearance', '短发。');
      await saveStudioDraftToCard(tavern, id, draft);

      final back = await loadStudioDraftFromCard(tavern, id);
      expect(back.text('profile', 'appearance'), '短发。');

      final fields = (await tavern.characterFields(id))!;
      final dshgo = (fields['extensions']! as Map)['dshgo']! as Map;
      expect(dshgo['state'], isNotNull, reason: '同一个 dshgo 下的 state 不能被冲掉');
      expect(dshgo['studio'], isNotNull);
    });

    test('卡片书的标题读得出来', () async {
      expect(studioBookTitles(await tavern.characterFields(id)), ['码头']);
      expect(studioBookTitles(null), isEmpty);
    });

    test('按标题去重：卡片里已有「码头」，只补「雨」', () {
      final wanted = [
        StudioBookEntry(title: '码头', content: '新内容'),
        StudioBookEntry(title: '雨', content: '一年下三百天雨。'),
        StudioBookEntry(title: '  ', content: '没标题的'),
      ];
      final missing = studioEntriesMissingFrom(wanted, ['码头']);
      expect(missing.map((e) => e.title), ['雨']);
    });
  });

  group('老卡起一份草稿', () {
    test('有把握的字段对着搬过去', () {
      final draft = studioDraftFromCardData({
        'name': '林晚',
        'description': '短发，围裙上有酱油点。',
        'personality': '嘴硬。',
        'scenario': '雨夜的面馆。',
        'first_mes': '坐吧。',
        'mes_example': '<START>\n{{user}}: 有面吗？',
        'tags': ['日常', '治愈'],
      });
      expect(draft.text('profile', 'name'), '林晚');
      expect(draft.text('profile', 'appearance'), '短发，围裙上有酱油点。');
      expect(draft.text('mind', 'inner'), '嘴硬。');
      expect(draft.text('scene', 'meeting'), '雨夜的面馆。');
      expect(draft.text('voice', 'firstMes'), '坐吧。');
      expect(draft.text('voice', 'samples'), contains('有面吗'));
      expect(draft.items('mind', 'surface'), ['日常', '治愈']);
    });

    test('空字段不硬塞，null 也不炸', () {
      final draft = studioDraftFromCardData({
        'name': '林晚',
        'description': '',
        'personality': null,
      });
      expect(draft.text('profile', 'name'), '林晚');
      expect(draft.peek('profile', 'appearance'), isNull, reason: '空的就别建');
      expect(draft.peek('mind', 'inner'), isNull);
      expect(studioDraftFromCardData(null).isEmpty, isTrue);
    });
  });
}
