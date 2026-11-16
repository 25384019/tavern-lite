// 预设能从应用里新建、复制、改、删，并且改完读得回来。
//
//   flutter test test/preset_new_test.dart

import 'dart:io';

import 'package:dsh_app/tavern/preset_new.dart';
import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late Tavern tavern;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('preset_new');
    tavern = await openTavern('${dir.path}/tavern');
  });

  tearDown(() async {
    await tavern.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('新建一个预设：列表里有它，打开能读到主提示', () async {
    final id = await createEmptyPreset(
      tavern,
      name: '我的预设',
      mainPrompt: '你要写得短。',
    );
    final presets = await tavern.listPresets();
    expect(presets.map((p) => p.name), contains('我的预设'));

    final preset = await tavern.preset(id);
    expect(preset, isNotNull);
    final prompts = preset!.raw['prompts']! as List;
    final main = prompts.cast<Map<String, Object?>>().firstWhere(
      (p) => p['identifier'] == presetMainIdentifier,
    );
    expect(main['content'], '你要写得短。');
    expect(preset.raw['temperature'], 0.8);
  });

  test('名字空着有兜底名', () async {
    final id = await createEmptyPreset(tavern, name: '   ');
    final preset = await tavern.preset(id);
    expect(preset!.name, '我的预设');
  });

  test('改了参数和主提示，读回来是新值', () async {
    final id = await createEmptyPreset(tavern, name: 'A', mainPrompt: '旧的');
    await tavern.updatePreset(id, {'temperature': 0.3, 'top_p': 0.5});
    await tavern.updatePresetPrompt(id, presetMainIdentifier, {
      'content': '新的',
    });
    final preset = await tavern.preset(id);
    expect(preset!.raw['temperature'], 0.3);
    expect(preset.raw['top_p'], 0.5);
    final main = (preset.raw['prompts']! as List)
        .cast<Map<String, Object?>>()
        .firstWhere((p) => p['identifier'] == presetMainIdentifier);
    expect(main['content'], '新的');
  });

  test('复制：新的一份名字带副本，参数照旧，原的那份还在', () async {
    final id = await createEmptyPreset(tavern, name: '原件', mainPrompt: '原样');
    final source = (await tavern.preset(id))!;
    final copyId = await duplicatePreset(tavern, source);

    expect(copyId, isNot(id));
    final copy = (await tavern.preset(copyId))!;
    expect(copy.name, '原件 副本');
    expect(copy.raw['temperature'], source.raw['temperature']);
    expect((await tavern.preset(id))!.name, '原件');
    expect((await tavern.listPresets()), hasLength(2));
  });

  test('删掉之后就没了', () async {
    final id = await createEmptyPreset(tavern, name: '要删的');
    await tavern.deletePreset(id);
    expect((await tavern.listPresets()).any((p) => p.id == id), isFalse);
  });

  test('设为默认：选择里读得到', () async {
    final id = await createEmptyPreset(tavern, name: '默认的');
    await tavern.setDefaultPreset(id);
    final selection = await tavern.presetSelection();
    expect(selection.defaultPresetId, id);
  });
}
