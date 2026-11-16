// 从应用里新建一个预设：引擎没有 create，只有 importPreset，
// 所以「新建」= 造一份最小的 ST 预设 JSON 导进去。
//
// 形状照 ST 的预设：采样参数在顶层，提示词在 prompts，用 prompt_order
// 排第一组（100001）的顺序。不写任何私有字段，导出去 ST 也认。

import 'dart:convert';

import 'package:dsh_tavern/dsh_tavern.dart';

/// 一条提示词在 ST 预设里的标识。主提示用 ST 自己的 `main`。
const presetMainIdentifier = 'main';

Map<String, Object?> emptyPresetJson(String name, {String mainPrompt = ''}) => {
  'name': name.trim().isEmpty ? '我的预设' : name.trim(),
  'temperature': 0.8,
  'frequency_penalty': 0,
  'presence_penalty': 0,
  'top_p': 0.95,
  'top_k': 0,
  'openai_max_tokens': 800,
  'prompts': [
    {
      'identifier': presetMainIdentifier,
      'name': '主提示',
      'system_prompt': true,
      'role': 'system',
      'content': mainPrompt,
      'injection_position': 0,
      'injection_depth': 4,
      'enabled': true,
    },
  ],
  'prompt_order': [
    {
      'character_id': 100001,
      'order': [
        {'identifier': presetMainIdentifier, 'enabled': true},
      ],
    },
  ],
};

/// 新建一个预设，返回它的 id。
Future<String> createEmptyPreset(
  Tavern tavern, {
  required String name,
  String mainPrompt = '',
}) async {
  final json = emptyPresetJson(name, mainPrompt: mainPrompt);
  final result = await tavern.importPreset(
    _encode(json),
    // ?????????????ST ?????????????????????
    fileName: '${json['name']}.json',
  );
  return result.preset.id;
}

/// 复制一份：读出现有的 content/参数，换个名字再导进去。
Future<String> duplicatePreset(Tavern tavern, TavernPreset source) async {
  final raw = source.raw;
  final copy = <String, Object?>{...raw, 'name': '${source.name} 副本'};
  final result = await tavern.importPreset(
    _encode(copy),
    fileName: '${copy['name']}.json',
  );
  return result.preset.id;
}

String _encode(Map<String, Object?> json) => jsonEncode(json);
