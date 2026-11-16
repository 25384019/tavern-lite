// 专业创作的 AI 层：提示里带什么、回包怎么过滤、采用时写哪。
//
// 护栏是这一层的重点：锁定字段不许被写、只收本模块的键、字段动作只收目标字段。
//
//   flutter test test/tavern_studio_ai_test.dart

import 'package:dsh_app/tavern/state_templates.dart';
import 'package:dsh_app/tavern/tavern_studio_ai.dart';
import 'package:dsh_app/tavern/tavern_studio_draft.dart';
import 'package:flutter_test/flutter_test.dart';

String id(String key) => key;

StudioDraft draftWith({bool lockedAppearance = false}) {
  final draft = StudioDraft();
  draft.setText('profile', 'name', '林晚');
  draft.setText('profile', 'identity', '面馆老板');
  draft.setText('profile', 'appearance', '短发，围裙上有酱油点。');
  draft.setText('mind', 'inner', '怕被需要之后又被丢下。');
  if (lockedAppearance) draft.toggleLock('profile', 'appearance');
  return draft;
}

void main() {
  test('创作灵感随草稿往返，并进入专业 AI 提示', () {
    final draft = StudioDraft(idea: '雨港里的成年灯塔守望者');
    expect(draft.isEmpty, isFalse);
    final restored = StudioDraft.fromJson(draft.toJson()).copy();
    final messages = studioAiMessages(
      draft: restored,
      module: 'mind',
      field: 'inner',
      action: StudioAiAction.fill,
      label: id,
    );
    expect(messages.last['content'], contains('雨港里的成年灯塔守望者'));
  });
  group('提示', () {
    test('带上模块、已经写了的、以及锁定的标记', () {
      final draft = draftWith(lockedAppearance: true);
      final messages = studioAiMessages(
        draft: draft,
        module: 'profile',
        field: 'body',
        action: StudioAiAction.fill,
        label: id,
      );
      final system = messages.first['content']! as String;
      final ask = messages.last['content']! as String;
      expect(system, contains('JSON'));
      expect(system, contains('锁定'));
      expect(ask, contains('人物档案'));
      expect(ask, contains('已经写了'));
      // 锁定的那个带着标记进提示，让模型知道不能改
      expect(ask, contains('【锁定】appearance'));
      // 全局摘要：姓名和身份
      expect(ask, contains('林晚'));
      // 目标字段的人话名字在里面
      expect(ask, contains('body'));
      // 输出形状
      expect(ask, contains('"fields"'));
    });

    test('五种动作写成不同的话，不是一个模板套所有', () {
      String askOf(StudioAiAction action, {String instruction = ''}) =>
          studioAiMessages(
                draft: draftWith(),
                module: 'profile',
                field: 'appearance',
                action: action,
                instruction: instruction,
                label: id,
              ).last['content']!
              as String;

      expect(askOf(StudioAiAction.fill), contains('补全'));
      expect(askOf(StudioAiAction.expand), contains('长'));
      expect(askOf(StudioAiAction.trim), contains('精简'));
      expect(
        askOf(StudioAiAction.rewrite, instruction: '更冷一点'),
        contains('更冷一点'),
      );
      expect(askOf(StudioAiAction.check), contains('检查'));
      // 检查要的是 issues，不是 fields
      expect(askOf(StudioAiAction.check), contains('"issues"'));
      expect(askOf(StudioAiAction.fill), isNot(contains('"issues"')));
    });

    test('英文一份，形状一样', () {
      final ask =
          studioAiMessages(
                draft: draftWith(),
                module: 'profile',
                field: 'appearance',
                action: StudioAiAction.fill,
                english: true,
                label: id,
              ).last['content']!
              as String;
      expect(ask, contains('Profile'));
      expect(ask, contains('Fill in'));
    });
  });

  group('键名', () {
    const labels = {
      'name': '姓名',
      'identity': '角色身份',
      'appearance': '外貌',
      'body': '体态细节',
      'habits': '生活习惯',
    };
    String labelOf(String key) => labels[key] ?? key;

    test('提示里必须出现程序要的英文键，不能只有中文名', () {
      final ask =
          studioAiMessages(
                draft: StudioDraft(),
                module: 'profile',
                field: 'identity',
                action: StudioAiAction.fill,
                label: labelOf,
              ).last['content']!
              as String;
      expect(ask, contains('identity'), reason: '要告诉模型键名是 identity');
      expect(ask, contains('角色身份'));
      // 输出形状里也得是 identity
      expect(ask, contains('"identity"'));
    });

    test('整模块只列空着且没锁的字段', () {
      final draft = StudioDraft();
      draft.setText('profile', 'name', '林晚');
      draft.setText('profile', 'appearance', '短发。');
      draft.toggleLock('profile', 'body');
      final ask =
          studioAiMessages(
                draft: draft,
                module: 'profile',
                action: StudioAiAction.wholeModule,
                label: labelOf,
              ).last['content']!
              as String;
      expect(ask, contains('- identity'));
      expect(ask, isNot(contains('- appearance')), reason: '已经有内容的不该再让模型写');
      expect(ask, isNot(contains('- body')), reason: '锁着的也不该列');
    });

    test('模型回中文名也能对回键', () {
      final proposal = studioAiParse(
        '{"fields":{"角色身份":"面馆老板"}}',
        draft: StudioDraft(),
        module: 'profile',
        field: 'identity',
        action: StudioAiAction.fill,
        label: labelOf,
      );
      expect(proposal.fields['identity'], '面馆老板');
    });

    test('整模块：已有内容的字段没锁也不覆盖', () {
      final draft = StudioDraft();
      draft.setText('profile', 'appearance', '旧的。');
      final proposal = studioAiParse(
        '{"fields":{"appearance":"新的。","body":"左手有疤。"}}',
        draft: draft,
        module: 'profile',
        action: StudioAiAction.wholeModule,
        label: labelOf,
      );
      expect(proposal.fields.keys, ['body']);
    });

    test('采用时 onlyEmpty 再拦一道：已有内容不写', () {
      final draft = StudioDraft();
      draft.setText('profile', 'appearance', '旧的。');
      studioAiApply(
        draft,
        'profile',
        const StudioAiProposal(fields: {'appearance': '新的。', 'body': '左手有疤。'}),
        onlyEmpty: true,
      );
      expect(draft.text('profile', 'appearance'), '旧的。');
      expect(draft.text('profile', 'body'), '左手有疤。');
    });
  });

  group('灵魂档案', () {
    test('每一格的提示里都带着它，而且是"不许改"的口径', () {
      final draft = StudioDraft();
      draft.setText('soul', 'motive', '想被需要');
      draft.setItems('soul', 'constants', ['不会主动求人']);
      draft.setText('soul', 'conflict', '想靠近又怕被丢下');
      final ask =
          studioAiMessages(
                draft: draft,
                module: 'profile',
                field: 'appearance',
                action: StudioAiAction.fill,
                label: id,
              ).last['content']!
              as String;
      expect(ask, contains('灵魂'));
      expect(ask, contains('想被需要'));
      expect(ask, contains('不会主动求人'));
      expect(ask, contains('想靠近又怕被丢下'));
      expect(ask, contains('不许改'));
    });

    test('没写灵魂就不占提示的地方', () {
      final ask =
          studioAiMessages(
                draft: StudioDraft(),
                module: 'profile',
                field: 'appearance',
                action: StudioAiAction.fill,
                label: id,
              ).last['content']!
              as String;
      expect(ask, isNot(contains('灵魂')));
    });
  });

  group('试演', () {
    test('解析三段台词，空的丢掉', () {
      final proposal = studioAiParse(
        '{"scenes":[{"title":"被搭话","reply":"*抬眼看你* 又是你？"},'
        '{"title":"被冒犯","reply":"滚。"},{"title":"空的","reply":"  "}]}',
        draft: StudioDraft(),
        module: 'voice',
        action: StudioAiAction.simulate,
      );
      expect(proposal.scenes, hasLength(2));
      expect(proposal.scenes.first.title, '被搭话');
      expect(proposal.scenes.last.reply, '滚。');
    });

    test('提示要三段、要的是 scenes', () {
      final ask =
          studioAiMessages(
                draft: StudioDraft(),
                module: 'voice',
                action: StudioAiAction.simulate,
                label: id,
              ).last['content']!
              as String;
      expect(ask, contains('三段'));
      expect(ask, contains('"scenes"'));
    });

    test('试演不写任何字段（采用时是空提议的一部分）', () {
      final draft = StudioDraft();
      final proposal = studioAiParse(
        '{"scenes":[{"title":"a","reply":"b"}]}',
        draft: draft,
        module: 'voice',
        action: StudioAiAction.simulate,
      );
      studioAiApply(draft, 'voice', proposal);
      expect(draft.isEmpty, isTrue, reason: '试演只给人看，不该动草稿');
    });
  });

  group('状态方案', () {
    test('解析成状态项：类型、范围、选项都对', () {
      final proposal = studioAiParse(
        '{"fields":['
        '{"key":"affection","title":"好感","type":"number","initial":20,"min":-100,"max":100},'
        '{"key":"mood","title":"心情","type":"choice","initial":"平静","options":["平静","高兴"]},'
        '{"key":"isOpen","title":"营业中","type":"boolean","initial":true},'
        '{"title":"没有 key 的"}'
        ']}',
        draft: StudioDraft(),
        module: 'profile',
        action: StudioAiAction.state,
      );
      final template = proposal.stateTemplate;
      expect(template, isNotNull);
      expect(template!.fields.map((f) => f.key), [
        'affection',
        'mood',
        'isOpen',
      ]);
      expect(template.fields.first.min, -100);
      expect(template.fields[1].options, ['平静', '高兴']);
      expect(template.fields[2].type, StateFieldType.boolean);
    });

    test('提示里要 fields，也要说清 type / initial', () {
      final ask =
          studioAiMessages(
                draft: StudioDraft(),
                module: 'profile',
                action: StudioAiAction.state,
                label: id,
              ).last['content']!
              as String;
      expect(ask, contains('"fields"'));
      expect(ask, contains('type'));
      expect(ask, contains('initial'));
    });

    test('一条都没有就是空提议', () {
      expect(
        studioAiParse(
          '{"fields":[]}',
          draft: StudioDraft(),
          module: 'profile',
          action: StudioAiAction.state,
        ).isEmpty,
        isTrue,
      );
    });
  });

  group('解析', () {
    test('只收本模块、目标字段、没锁的', () {
      final draft = draftWith(lockedAppearance: true);
      final proposal = studioAiParse(
        '```json\n{"fields":{"appearance":"新外貌","body":"左手有疤","inner":"越界的另一个模块","nope":"不存在的键"}}\n```',
        draft: draft,
        module: 'profile',
        field: 'body',
        action: StudioAiAction.fill,
      );
      expect(proposal.fields.keys, ['body'], reason: '锁定的、别的模块的、不存在的都该丢');
      expect(proposal.fields['body'], '左手有疤');
    });

    test('整模块：只收空的、没锁的字段（有内容的不覆盖）', () {
      // draftWith 里 name / identity / appearance 都写了内容，appearance 还锁了。
      final draft = draftWith(lockedAppearance: true);
      final proposal = studioAiParse(
        '{"fields":{"appearance":"不该覆盖","body":"左手有疤","identity":"面馆老板"}}',
        draft: draft,
        module: 'profile',
        action: StudioAiAction.wholeModule,
      );
      expect(proposal.fields.keys.toSet(), {
        'body',
      }, reason: 'identity 有内容也不许覆盖');
      expect(proposal.fields['body'], '左手有疤');
    });

    test('列表值按行拆开', () {
      final proposal = studioAiParse(
        '{"fields":{"likes":["煮面","听雨"]}}',
        draft: StudioDraft(),
        module: 'profile',
        field: 'likes',
        action: StudioAiAction.fill,
      );
      expect(proposal.fields['likes'], '煮面\n听雨');
    });

    test('检查只要问题，字段动作不要 issues', () {
      final check = studioAiParse(
        '{"issues":[{"field":"fear","issue":"怕黑，但经历里说从不怕黑","suggest":"改成怕被留下"}]}',
        draft: draftWith(),
        module: 'mind',
        action: StudioAiAction.check,
      );
      expect(check.issues, hasLength(1));
      expect(check.issues.first.field, 'fear');
      expect(check.fields, isEmpty);

      final fill = studioAiParse(
        '{"issues":[{"field":"fear","issue":"x"}]}',
        draft: draftWith(),
        module: 'mind',
        field: 'fear',
        action: StudioAiAction.fill,
      );
      expect(fill.isEmpty, isTrue);
    });

    test('围栏和前后废话都能救回来；烂东西返回空', () {
      final ok = studioAiParse(
        '好的，这是结果：\n```json\n{"fields":{"body":"左手有疤"}}\n```\n还要改吗？',
        draft: StudioDraft(),
        module: 'profile',
        field: 'body',
        action: StudioAiAction.fill,
      );
      expect(ok.fields['body'], '左手有疤');
      expect(
        studioAiParse(
          '我不想写',
          draft: StudioDraft(),
          module: 'profile',
          field: 'body',
          action: StudioAiAction.fill,
        ).isEmpty,
        isTrue,
      );
      expect(
        studioAiParse(
          '{坏掉的 json',
          draft: StudioDraft(),
          module: 'profile',
          field: 'body',
          action: StudioAiAction.fill,
        ).isEmpty,
        isTrue,
      );
    });

    test('空的、只有空白的值丢掉', () {
      final proposal = studioAiParse(
        '{"fields":{"body":"","identity":"   "}}',
        draft: StudioDraft(),
        module: 'profile',
        action: StudioAiAction.wholeModule,
      );
      expect(proposal.isEmpty, isTrue);
    });
  });

  group('采用', () {
    test('文本字段写进草稿，来源记成 ai，并且能撤销', () {
      final draft = StudioDraft();
      draft.setText('profile', 'body', '旧内容');
      studioAiApply(
        draft,
        'profile',
        const StudioAiProposal(fields: {'body': '新内容'}),
      );
      expect(draft.text('profile', 'body'), '新内容');
      expect(draft.peek('profile', 'body')!.source, StudioSource.ai);
      expect(draft.undo('profile', 'body'), isTrue);
      expect(draft.text('profile', 'body'), '旧内容');
    });

    test('列表字段按行写进去，空行不留', () {
      final draft = StudioDraft();
      studioAiApply(
        draft,
        'profile',
        const StudioAiProposal(fields: {'likes': '煮面\n\n听雨'}),
      );
      expect(draft.items('profile', 'likes'), ['煮面', '听雨']);
    });

    test('锁定的字段即使混进提议也不写', () {
      final draft = draftWith(lockedAppearance: true);
      studioAiApply(
        draft,
        'profile',
        const StudioAiProposal(fields: {'appearance': '不该覆盖'}),
      );
      expect(draft.text('profile', 'appearance'), '短发，围裙上有酱油点。');
    });

    test('不认识的键默默丢掉，不炸', () {
      final draft = StudioDraft();
      studioAiApply(
        draft,
        'profile',
        const StudioAiProposal(fields: {'nope': 'x'}),
      );
      expect(draft.isEmpty, isTrue);
    });
  });
}
