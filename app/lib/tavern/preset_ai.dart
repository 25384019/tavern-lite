// 预设里的提示词，让 AI 写或改写一段。
//
// 只产出「一段文字」——落回哪个提示由界面决定（现在就是当前这条的 content）。
// 模型经常直接回一段散文而不是 JSON，这里两种都收：先试 JSON 的 content，
// 没有就整段当正文。反正都要给人看过才采用。

import 'dart:convert';

/// 提示词可以做什么。
enum PresetAiAction { write, expand, trim }

List<Map<String, Object?>> presetPromptMessages({
  required String presetName,
  required String promptName,
  required String current,
  required PresetAiAction action,
  String instruction = '',
  bool english = false,
}) {
  final system = english
      ? 'You write system prompts for a SillyTavern preset. Answer with the prompt text only — '
            'no explanation, no markdown fence, no quotes around it. Use {{user}} and {{char}}.'
      : '你在给酒馆预设写提示词。只回提示词正文，不要解释、不要代码块、不要加引号。'
            '用 {{user}} 指代玩家、{{char}} 指代角色。';
  final task = switch (action) {
    PresetAiAction.write =>
      english ? 'Write this prompt from scratch.' : '从头写这条提示词。',
    PresetAiAction.expand =>
      english ? 'Lengthen it; keep every existing rule.' : '写长一些，已有的规则一条都不要丢。',
    PresetAiAction.trim =>
      english
          ? 'Tighten it to about 70%; keep every rule.'
          : '压到七成左右，规则一条都不要丢。',
  };
  return [
    {'role': 'system', 'content': system},
    {
      'role': 'user',
      'content': [
        english ? 'Preset: $presetName' : '预设：$presetName',
        english ? 'Prompt: $promptName' : '提示词：$promptName',
        if (current.trim().isNotEmpty) ...[
          '',
          english ? 'Now:' : '现在的内容：',
          current.trim(),
        ],
        if (instruction.trim().isNotEmpty) ...[
          '',
          english
              ? 'What I want: ${instruction.trim()}'
              : '我想要：${instruction.trim()}',
        ],
        '',
        task,
      ].join('\n'),
    },
  ];
}

Map<String, Object?> presetPromptBody(
  List<Map<String, Object?>> messages, {
  int maxTokens = 900,
}) => {'messages': messages, 'temperature': 0.85, 'max_tokens': maxTokens};

/// 从回答里取出提示词正文；取不出返回 null。
String? presetPromptParse(String reply) {
  final text = reply.trim();
  if (text.isEmpty) return null;
  // 1) 先试 JSON 里带 content 的
  var inner = text;
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
  if (fence != null) inner = fence.group(1)!.trim();
  final start = inner.indexOf('{');
  final end = inner.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      final decoded = jsonDecode(inner.substring(start, end + 1));
      if (decoded is Map && decoded['content'] is String) {
        final content = (decoded['content']! as String).trim();
        return content.isEmpty ? null : content;
      }
    } on FormatException {
      // 不是 JSON，往下走
    }
  }
  // 2) 整段当正文（去掉可能残留的围栏）
  final plain = text
      .replaceAll(RegExp(r'^```[a-zA-Z]*\s*'), '')
      .replaceAll(RegExp(r'```\s*$'), '')
      .trim();
  return plain.isEmpty ? null : plain;
}
