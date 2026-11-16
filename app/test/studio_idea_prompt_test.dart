// 「我想要的角色」必须真的发给模型——专业创作里的每一格都照它写。
//
//   flutter test test/studio_idea_prompt_test.dart

import 'package:dsh_app/tavern/tavern_studio_ai.dart';
import 'package:dsh_app/tavern/tavern_studio_draft.dart';
import 'package:flutter_test/flutter_test.dart';

String _ask(StudioDraft draft) =>
    studioAiMessages(
          draft: draft,
          module: 'profile',
          field: 'name',
          action: StudioAiAction.fill,
          label: (key) => key,
        ).last['content']!
        as String;

void main() {
  test('写了的「我想要的角色」进提示', () {
    final ask = _ask(StudioDraft()..idea = '一个在雨港修船的女人，五十岁');
    expect(ask, contains('我想要的角色'));
    expect(ask, contains('雨港'));
  });

  test('没写就不占地方', () {
    expect(_ask(StudioDraft()), isNot(contains('我想要的角色')));
  });

  test('从制卡页带过来的那句创意也认（同一个字段）', () {
    final draft = StudioDraft()..idea = 'a lighthouse keeper on a lonely island';
    expect(_ask(draft), contains('lighthouse keeper'));
  });

  test('整模块生成也带着它', () {
    final ask =
        studioAiMessages(
              draft: StudioDraft()..idea = '码头上的哑巴船工',
              module: 'profile',
              action: StudioAiAction.wholeModule,
              label: (key) => key,
            ).last['content']!
            as String;
    expect(ask, contains('哑巴船工'));
  });
}
