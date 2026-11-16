// 草稿里的世界书条目：存得住、转得进卡、AI 生成的能落进来。
//
//   flutter test test/tavern_studio_book_test.dart

import 'package:dsh_app/tavern/tavern_studio_ai.dart';
import 'package:dsh_app/tavern/tavern_studio_build.dart';
import 'package:dsh_app/tavern/tavern_studio_draft.dart';
import 'package:flutter_test/flutter_test.dart';

StudioDraft draftWithWorld() {
  final draft = StudioDraft();
  draft.setText('profile', 'name', '林晚');
  draft.setText('world', 'era', '现代都市');
  draft.setText('world', 'geography', '靠海的雨港，一年下三百天雨。');
  return draft;
}

void main() {
  group('草稿', () {
    test('加、删、空的不收', () {
      final draft = StudioDraft();
      draft.addBookEntry(
        StudioBookEntry(title: '码头', content: '潮水一天两次。', keys: ['码头', '潮水']),
      );
      draft.addBookEntry(StudioBookEntry(title: '空的', content: '   '));
      expect(draft.book, hasLength(1));
      expect(draft.book.first.keys, ['码头', '潮水']);

      draft.removeBookEntry(0);
      expect(draft.book, isEmpty);
      // 越界删不炸
      draft.removeBookEntry(5);
    });

    test('JSON 往返：标题、正文、关键词、常驻都在', () {
      final draft = draftWithWorld();
      draft.addBookEntry(
        StudioBookEntry(title: '码头', content: '潮水一天两次。', keys: ['码头']),
      );
      draft.addBookEntry(
        StudioBookEntry(title: '雨', content: '这里一年下三百天雨。', constant: true),
      );
      final back = StudioDraft.fromJson(draft.toJson());
      expect(back.book, hasLength(2));
      expect(back.book[0].title, '码头');
      expect(back.book[0].keys, ['码头']);
      expect(back.book[1].constant, isTrue, reason: '常驻要留住');
      // 老草稿没有 book 字段也不该炸
      expect(StudioDraft.fromJson({'v': 1, 'modules': {}}).book, isEmpty);
    });
  });

  group('转换器', () {
    test('草稿里的条目写进 character_book，带关键词和常驻位', () {
      final draft = draftWithWorld();
      draft.addBookEntry(
        StudioBookEntry(
          title: '码头',
          content: '潮水一天两次，第一次来的人总会被困住。',
          keys: ['码头', '潮水'],
        ),
      );
      draft.addBookEntry(
        StudioBookEntry(title: '雨', content: '一年下三百天雨。', constant: true),
      );

      final data =
          buildStudioCard(draft, creator: 'x')['data']! as Map<String, Object?>;
      final book = data['character_book']! as Map<String, Object?>;
      final entries = book['entries']! as List;
      expect(entries, hasLength(2));

      final dock = entries[0] as Map<String, Object?>;
      expect(dock['keys'], ['码头', '潮水']);
      expect(dock['comment'], '码头');
      expect(dock['content'], contains('潮水一天两次'));
      expect(dock['constant'], isFalse);
      expect(dock['position'], 'after_char');

      final rain = entries[1] as Map<String, Object?>;
      expect(rain['constant'], isTrue);
      expect(rain['position'], 'before_char', reason: '常驻的放前面');
      expect(rain['keys'], ['一年下三百天'], reason: '没写关键词就拿开头六个字兜底');
    });

    test('草稿条目排在字段里写的条目前面', () {
      final draft = draftWithWorld();
      draft.setItems('world', 'places', ['后厨｜只有她能进']);
      draft.addBookEntry(
        StudioBookEntry(title: '码头', content: '潮水一天两次。', keys: ['码头']),
      );
      final entries =
          ((buildStudioCard(draft, creator: 'x')['data']!
                      as Map)['character_book']!
                  as Map)['entries']!
              as List;
      expect(entries, hasLength(2));
      expect((entries[0] as Map)['comment'], '码头');
      expect((entries[1] as Map)['comment'], contains('地点'));
    });

    test('条目总数还是有上限', () {
      final draft = draftWithWorld();
      for (var i = 0; i < 40; i++) {
        draft.addBookEntry(StudioBookEntry(title: '条目$i', content: '内容$i'));
      }
      final entries =
          ((buildStudioCard(draft, creator: 'x')['data']!
                      as Map)['character_book']!
                  as Map)['entries']!
              as List;
      expect(entries.length, lessThanOrEqualTo(studioBookLimit));
    });
  });

  group('AI', () {
    test('解析 entries；没正文的丢掉', () {
      final proposal = studioAiParse(
        '{"entries":[{"title":"码头","keys":["码头","潮水"],"content":"潮水一天两次。"},'
        '{"title":"空的","keys":["x"],"content":"   "}]}',
        draft: StudioDraft(),
        module: 'world',
        action: StudioAiAction.book,
      );
      expect(proposal.entries, hasLength(1));
      expect(proposal.entries.first.title, '码头');
      expect(proposal.entries.first.keys, ['码头', '潮水']);
    });

    test('生成条目的提示要 entries 而不是 fields', () {
      final ask =
          studioAiMessages(
                draft: draftWithWorld(),
                module: 'world',
                action: StudioAiAction.book,
                label: (key) => key,
              ).last['content']!
              as String;
      expect(ask, contains('"entries"'));
      expect(ask, contains('关键词'));
    });

    test('采用后进草稿的书；再来一批是追加不是覆盖', () {
      final draft = draftWithWorld();
      studioAiApply(
        draft,
        'world',
        StudioAiProposal(
          entries: [
            StudioBookEntry(title: '码头', content: '潮水一天两次。', keys: ['码头']),
          ],
        ),
      );
      expect(draft.book, hasLength(1));

      studioAiApply(
        draft,
        'world',
        StudioAiProposal(
          entries: [StudioBookEntry(title: '雨', content: '一年下三百天雨。')],
        ),
      );
      expect(draft.book, hasLength(2));
      expect(draft.book.map((e) => e.title), ['码头', '雨']);
    });
  });
}
