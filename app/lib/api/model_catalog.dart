// 上游模型目录：问 <baseUrl>/models 要一份列表，连同能力一起读出来。
//
// 标准 OpenAI 只给 id；DeepSeek 会多给 context_window / max_output_tokens /
// input_modalities / effort，正好是模型设置里要显示的三件事：上下文、识图、
// 思考。拿不到就按名字猜，并且标明是猜的。

import 'dart:convert';

import 'package:http/http.dart' as http;

class ModelInfo {
  const ModelInfo({
    required this.id,
    this.name,
    this.contextWindow,
    this.maxOutput,
    this.vision = false,
    this.thinking = false,
    this.efforts = const [],
    this.ownedBy,
    this.guessed = false,
  });

  final String id;
  final String? name;

  /// Tokens; null when the endpoint does not say.
  final int? contextWindow;
  final int? maxOutput;

  /// Takes images as input.
  final bool vision;

  /// Reasons before answering (a thinking/reasoning model).
  final bool thinking;

  /// The effort levels the endpoint advertises, cheapest first.
  final List<String> efforts;

  final String? ownedBy;

  /// True when [vision]/[thinking] came from the name, not from the endpoint.
  final bool guessed;

  String get label => (name == null || name!.isEmpty || name == id) ? id : '$name · $id';
}

/// `{base}/models`, tolerant of the shapes providers actually return and of a
/// base URL that already ends in `/chat/completions`.
Uri modelsUri(String baseUrl) {
  final uri = Uri.parse(baseUrl.trim());
  if (!uri.hasAuthority) {
    throw const FormatException('invalid_base_url');
  }
  var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  if (path.endsWith('/chat/completions')) {
    path = path.substring(0, path.length - '/chat/completions'.length);
  }
  return uri.replace(path: '$path/models');
}

Future<List<ModelInfo>> fetchModelCatalog({required String baseUrl, required String apiKey}) async {
  final uri = modelsUri(baseUrl);
  final response = await http
      .get(uri, headers: {'Authorization': 'Bearer $apiKey', 'Accept': 'application/json'})
      .timeout(const Duration(seconds: 20));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw ModelCatalogException(response.statusCode, _redact(response.body, apiKey));
  }
  final decoded = jsonDecode(utf8.decode(response.bodyBytes));
  final list = _rows(decoded);
  final models = [
    for (final row in list)
      if (_id(row) case final id when id.isNotEmpty) _parse(id, row),
  ]..sort((a, b) => a.id.compareTo(b.id));
  return models;
}

List<Map<String, Object?>> _rows(Object? decoded) {
  if (decoded is! Map<String, Object?>) return const [];
  for (final key in const ['data', 'models']) {
    final value = decoded[key];
    if (value is List) {
      return [
        for (final item in value)
          if (item is Map<String, Object?>) item,
      ];
    }
  }
  return const [];
}

String _id(Map<String, Object?> row) {
  final id = row['id'] ?? row['name'] ?? row['model'];
  return id is String ? id.trim() : '';
}

ModelInfo _parse(String id, Map<String, Object?> row) {
  final name = row['name'];
  final context = _int(row['context_window'] ?? row['context_length'] ?? row['max_context_tokens']);
  final output = _int(row['max_output_tokens'] ?? row['max_tokens']);

  final modalities = row['input_modalities'];
  final declaredVision = modalities is List && modalities.any((m) => '$m'.toLowerCase().contains('image'));
  final efforts = _efforts(row);
  final declaredThinking = efforts.isNotEmpty || row['reasoning'] == true || row['thinking'] == true;

  final guessed = !declaredVision && !declaredThinking;
  return ModelInfo(
    id: id,
    name: name is String ? name : null,
    contextWindow: context,
    maxOutput: output,
    vision: declaredVision || (!declaredVision && _nameSaysVision(id)),
    thinking: declaredThinking || (!declaredThinking && _nameSaysThinking(id)),
    efforts: efforts,
    ownedBy: row['owned_by'] is String ? row['owned_by'] as String : null,
    guessed: guessed,
  );
}

List<String> _efforts(Map<String, Object?> row) {
  final effort = row['effort'];
  if (effort is Map<String, Object?>) {
    final levels = effort['supported_levels'];
    if (levels is List) return [for (final level in levels) '$level'];
  }
  final levels = row['reasoning_efforts'] ?? row['efforts'];
  if (levels is List) return [for (final level in levels) '$level'];
  return const [];
}

int? _int(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v),
  _ => null,
};

bool _nameSaysVision(String id) {
  final lower = id.toLowerCase();
  return lower.contains('vision') ||
      lower.contains('4o') ||
      lower.contains('omni') ||
      lower.contains('multimodal') ||
      RegExp(r'(^|[-_/])vl($|[-_/0-9])').hasMatch(lower) ||
      lower.contains('llava') ||
      lower.contains('qwen2.5-vl') ||
      lower.contains('gemini');
}

bool _nameSaysThinking(String id) {
  final lower = id.toLowerCase();
  return lower.contains('reason') ||
      lower.contains('thinking') ||
      lower.contains('deepseek-v4') ||
      RegExp(r'(^|[-_/])r1($|[-_/])').hasMatch(lower) ||
      RegExp(r'(^|[-_/])o[13]($|[-_/])').hasMatch(lower) ||
      lower.contains('qwq');
}

class ModelCatalogException implements Exception {
  const ModelCatalogException(this.status, this.detail);

  final int status;
  final String detail;

  @override
  String toString() => 'HTTP $status: $detail';
}

String _redact(String body, String key) {
  var text = key.isEmpty ? body : body.replaceAll(key, '[redacted]');
  text = text.replaceAll(RegExp(r'Bearer\s+[^\s"<>]+', caseSensitive: false), 'Bearer [redacted]');
  return text.length > 300 ? text.substring(0, 300) : text;
}
