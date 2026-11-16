// 草稿与卡片的安全读写：写进 extensions.dshgo.studio，读得回来，
// 未知字段和卡内世界书一个字不动。
//
//   flutter test test/studio_roundtrip_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dsh_app/tavern/tavern_studio_draft.dart';
import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter_test/flutter_test.dart';

const _card = {
  'spec': 'chara_card_v3',
  'spec_version': '3.0',
  'data': {
    'name': '林晚',
    'description': '短发，围裙上有酱油点。',
    'personality': '嘴硬。',
    'scenario': '面馆。',
    'first_mes': '坐吧。',
    'mes_example': '',
    'creator_notes': '一张测试卡。',
    'system_prompt': '',
    'post_history_instructions': '',
    'alternate_greetings': <String>[],
    'tags': ['测试'],
    'creator': 'test',
    'character_version': '1.0',
    // 宿主不认识的字段：读写都不能弄丢
    'x-future-field': {'keep': true},
    'extensions': {
      'dshgo': {
        'state': {'v': 1},
      },
      'other-plugin': {'flag': 1},
    },
    'character_book': {
      'entries': [
        {
          'id': 0,
          'keys': ['码头'],
          'content': '潮水一天两次。',
        },
      ],
    },
  },
};

Map<String, Object?> studioOf(Map<String, Object?>? fields) =>
    switch ((fields?['extensions'] as Map?)?['dshgo']) {
      final Map dshgo =>
        (dshgo['studio'] as Map?)?.cast<String, Object?>() ?? const {},
      _ => const {},
    };

void main() {
  late Directory dir;
  late Tavern tavern;
  late String characterId;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('studio_roundtrip');
    tavern = await openTavern('${dir.path}/tavern');
    final card = await tavern.importCard(
      Uint8List.fromList(utf8.encode(jsonEncode(_card))),
      fileName: 'card.json',
    );
    characterId = card.id;
  });

  tearDown(() async {
    await tavern.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('草稿写进卡片再读回来，字段、锁定、条目都在', () async {
    final draft = StudioDraft();
    draft.setText('profile', 'name', '林晚');
    draft.setText('profile', 'appearance', '短发。');
    draft.toggleLock('profile', 'name');
    draft.addBookEntry(
      StudioBookEntry(title: '码头', content: '潮水一天两次。', keys: ['码头']),
    );

    await tavern.updateCharacterData(characterId, {
      'extensions': {
        'dshgo': {'studio': draft.toJson()},
      },
    });

    final fields = await tavern.characterFields(characterId);
    final back = StudioDraft.fromJson(studioOf(fields));
    expect(back.text('profile', 'appearance'), '短发。');
    expect(back.peek('profile', 'name')!.locked, isTrue);
    expect(back.book.single.title, '码头');
  });

  test('别的东西一个都不动：未知字段、别的插件、卡内世界书、正文', () async {
    final draft = StudioDraft()..setText('profile', 'appearance', 'x');
    await tavern.updateCharacterData(characterId, {
      'extensions': {
        'dshgo': {'studio': draft.toJson()},
      },
    });

    final fields = (await tavern.characterFields(characterId))!;
    expect(fields['x-future-field'], {'keep': true});
    final ext = fields['extensions']! as Map<String, Object?>;
    expect((ext['other-plugin']! as Map)['flag'], 1, reason: '别的插件的扩展要留着');
    expect(
      (ext['dshgo']! as Map)['state'],
      isNotNull,
      reason: '同一个 dshgo 下的 state 也要留着',
    );
    final book = fields['character_book']! as Map<String, Object?>;
    expect((book['entries']! as List), hasLength(1));
    expect(fields['description'], '短发，围裙上有酱油点。', reason: '正文没被顺手改掉');
  });

  test('character_book 不许从这里改，会明确拒绝', () async {
    await expectLater(
      tavern.updateCharacterData(characterId, {
        'character_book': {'entries': <Object?>[]},
      }),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('空补丁 = 读，不会把卡写坏', () async {
    final before = await tavern.characterFields(characterId);
    await tavern.updateCharacterData(characterId, const {});
    final after = await tavern.characterFields(characterId);
    expect(after, before);
  });

  test('不存在的卡报 TavernImportError', () async {
    await expectLater(
      tavern.updateCharacterData('card-00000000000000000000000000000000', {
        'x': 1,
      }),
      throwsA(isA<TavernImportError>()),
    );
  });
}
