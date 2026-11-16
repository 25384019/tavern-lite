// 生成前的一层「人格」：从用户自己的预设里取出系统提示，垫在任务提示前面。
//
// 只取真有人写内容的系统提示（main / nsfw / 越狱 / 文风这类），跳过 marker
// （对话示例、世界书前后、聊天历史这些占位），顺序照预设自己的 prompt_order。
// 一个都取不到就返回 null，调用方照原样发——不因为选了个空预设就发不出去。

/// 预设里能当人格层的那几条，按预设的顺序拼成一段；没有就 null。
String? presetPersonaText(Map<String, Object?> raw) {
  final parts = <String>[];
  for (final prompt in _orderedPrompts(raw)) {
    if (prompt['marker'] == true) continue;
    final role = prompt['role'];
    if (role != 'system' && prompt['system_prompt'] != true) continue;
    final content = prompt['content'];
    if (content is! String) continue;
    final text = content.trim();
    if (text.isEmpty || parts.contains(text)) continue;
    parts.add(text);
  }
  if (parts.isEmpty) {
    // 老预设：三条单独字段。
    for (final key in const ['main_prompt', 'nsfw_prompt', 'jailbreak_prompt']) {
      final value = raw[key];
      if (value is! String) continue;
      final text = value.trim();
      if (text.isEmpty || parts.contains(text)) continue;
      parts.add(text);
    }
  }
  return parts.isEmpty ? null : parts.join('\n\n');
}

/// 预设的提示顺序：主聊天那组（character_id 100001）优先，其次第一组，
/// 都没有就按 prompts 数组自己的顺序。
List<Map<String, Object?>> _orderedPrompts(Map<String, Object?> raw) {
  final listed = <Map<String, Object?>>[];
  final prompts = raw['prompts'];
  if (prompts is List) {
    for (final item in prompts) {
      if (item is Map) listed.add(item.cast<String, Object?>());
    }
  }
  if (listed.isEmpty) return listed;
  final byIdentifier = <String, Map<String, Object?>>{};
  for (final prompt in listed) {
    final identifier = prompt['identifier'];
    if (identifier is String && byIdentifier[identifier] == null) {
      byIdentifier[identifier] = prompt;
    }
  }
  final ordered = <Map<String, Object?>>[];
  for (final identifier in _orderIdentifiers(raw)) {
    final prompt = byIdentifier[identifier];
    if (prompt != null && !ordered.contains(prompt)) ordered.add(prompt);
  }
  // 顺序表里没列到的（新加的、手加的）接在后面，别丢。
  for (final prompt in listed) {
    if (!ordered.contains(prompt)) ordered.add(prompt);
  }
  return ordered;
}

List<String> _orderIdentifiers(Map<String, Object?> raw) {
  final orders = raw['prompt_order'];
  if (orders is! List) return const [];
  List<Object?>? picked;
  for (final group in orders) {
    if (group is! Map) continue;
    final id = group['character_id'];
    if (id == 100001 || id == '100001') {
      picked = group['order'] as List<Object?>?;
      break;
    }
  }
  if (picked == null) {
    for (final group in orders) {
      if (group is! Map) continue;
      picked = group['order'] as List<Object?>?;
      break;
    }
  }
  if (picked == null) return const [];
  return [
    for (final item in picked)
      if (item is Map && item['enabled'] != false && item['identifier'] is String)
        item['identifier']! as String,
  ];
}

/// 把人格垫成第一条 system；空的就是原样。
List<Map<String, Object?>> withPersona(
  List<Map<String, Object?>> messages,
  String? persona,
) {
  final text = (persona ?? '').trim();
  if (text.isEmpty) return messages;
  return [
    {'role': 'system', 'content': text},
    ...messages,
  ];
}
