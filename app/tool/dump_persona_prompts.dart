// 把「人格层」摊开看：同一个创意，在 不套 / 内置写卡 / 内置写书 / 你的预设 四种情况下，
// 真正发给模型的 messages 长什么样、各占多少字。
//
// 用途：拿真预设和内置两份做 A/B，看差别在哪几段，而不必真的花钱调模型。
//
//   dart --packages=.dart_tool/package_config.json tool/dump_persona_prompts.dart
//   dart --packages=.dart_tool/package_config.json tool/dump_persona_prompts.dart --preset 你的预设.json
//   …再加 --out ../docs/persona-ab.md 就直接写成 UTF-8 文件（重定向会写成 UTF-16，别用）。
//
// 预设 JSON 就是 SillyTavern 那种（带 prompts / prompt_order，或老的三条 *_prompt 字段）。

import 'dart:convert';
import 'dart:io';

import 'package:dsh_app/tavern/lorebook_ai.dart';
import 'package:dsh_app/tavern/preset_persona.dart';
import 'package:dsh_app/tavern/tavern_card_studio.dart';

const _idea = 'a lighthouse keeper on a lonely island';

void main(List<String> args) {
  final presetIndex = args.indexOf('--preset');
  String? presetRaw;
  if (presetIndex >= 0 && presetIndex + 1 < args.length) {
    final file = File(args[presetIndex + 1]);
    if (!file.existsSync()) {
      stderr.writeln('找不到预设文件：${file.path}');
      exitCode = 2;
      return;
    }
    presetRaw = file.readAsStringSync();
  }

  Map<String, Object?>? preset;
  if (presetRaw != null) {
    final decoded = jsonDecode(presetRaw);
    preset = decoded is Map<String, Object?> ? decoded : null;
    if (preset == null) {
      stderr.writeln('这个 JSON 不是对象，读不了。');
      exitCode = 2;
      return;
    }
  }

  final outIndex = args.indexOf('--out');
  final outPath = outIndex >= 0 && outIndex + 1 < args.length
      ? args[outIndex + 1]
      : null;
  final buffer = StringBuffer();
  void say([String line = '']) => buffer.writeln(line);
  void blank() => buffer.writeln();

  say('# 人格层对照：$_idea');
  blank();
  for (final item in _cases(preset)) {
    final card = tavernCardMessages(
      const TavernCardWish(idea: _idea),
      persona: item.persona,
    );
    final book = lorebookBlueprintMessages(
      idea: _idea,
      scale: '中',
      kind: LorebookKind.style,
      persona: item.persona,
    );
    say('## ${item.name}');
    blank();
    say('- 人格层：${item.persona?.length ?? 0} 字');
    if (item.dropped.isNotEmpty) {
      say('- 丢弃：${item.dropped.map((one) => one.toString()).join('；')}');
    }
    say('- 写卡 messages：${_chars(card)} 字 / ${card.length} 条');
    say('- 写书 messages：${_chars(book)} 字 / ${book.length} 条');
    blank();
    if (item.persona case final persona?) {
      say('```text');
      say(_head(persona));
      say('```');
      blank();
    }
  }

  say('## 展开：写卡请求（以内置写卡为例）');
  blank();
  say('```json');
  say(
    const JsonEncoder.withIndent('  ').convert(
      tavernCardRequestBody(
        const TavernCardWish(idea: _idea),
        persona: builtinPersona(builtinCardPersonaId, false),
      ),
    ),
  );
  say('```');

  final text = buffer.toString();
  if (outPath != null) {
    File(outPath).writeAsStringSync(text);
    stdout.writeln('written: $outPath (${text.length} chars)');
  } else {
    stdout.write(text);
  }
}

List<({String name, String? persona, List<PersonaDropped> dropped})> _cases(
  Map<String, Object?>? preset,
) {
  final built = preset == null ? null : presetPersona(preset);
  return [
    (name: '不套人格', persona: null, dropped: const <PersonaDropped>[]),
    (
      name: '内置 · 写卡用',
      persona: builtinPersona(builtinCardPersonaId, false),
      dropped: const <PersonaDropped>[],
    ),
    (
      name: '内置 · 写书用',
      persona: builtinPersona(builtinBookPersonaId, false),
      dropped: const <PersonaDropped>[],
    ),
    if (built != null)
      (
        name: '我的预设（按内容筛过）',
        persona: built.text,
        dropped: built.dropped,
      ),
  ];
}

int _chars(List<Map<String, Object?>> messages) => messages.fold<int>(
  0,
  (sum, message) => sum + '${message['content'] ?? ''}'.length,
);

/// 太长的人格层只看头尾，避免把整份预设铺进文档。
String _head(String text, {int limit = 600}) {
  if (text.length <= limit) return text;
  return '${text.substring(0, limit)}\n…（共 ${text.length} 字，后面略）';
}
