// The editor behind API 配置: one profile's name, base URL, model, key and the
// two transport switches, plus a connection test that says what the endpoint
// answered — the same request shape the tavern sends, one short message.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../api/api_profiles.dart';
import '../../l10n/l10n.dart';
import '../common/app_sheet.dart';
import '../common/sheet_title_bar.dart';
import '../theme/theme.dart';
import 'api_profiles_page.dart' show t;
import 'model_picker.dart';

/// Opens the editor; null when closed without saving.
Future<ApiProfile?> showApiProfileEditor(BuildContext context, WidgetRef ref, ApiProfile profile) => showAppSheet<ApiProfile>(
  context,
  isScrollControlled: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: ApiProfileEditor(profile: profile),
  ),
);

class ApiProfileEditor extends ConsumerStatefulWidget {
  const ApiProfileEditor({super.key, required this.profile});

  final ApiProfile profile;

  @override
  ConsumerState<ApiProfileEditor> createState() => _ApiProfileEditorState();
}

class _ApiProfileEditorState extends ConsumerState<ApiProfileEditor> {
  late final _name = TextEditingController(text: widget.profile.name);
  late final _baseUrl = TextEditingController(text: widget.profile.baseUrl);
  late final _model = TextEditingController(text: widget.profile.model);
  late final _key = TextEditingController(text: widget.profile.apiKey);
  late ApiKind _kind = widget.profile.kind;
  late bool _thinking = widget.profile.thinking;
  late bool _stream = widget.profile.stream;
  late bool _vision = widget.profile.vision;
  late int? _contextWindow = widget.profile.contextWindow;
  late int? _maxOutput = widget.profile.maxOutput;
  bool _showKey = false;
  bool _testing = false;
  String? _test;

  @override
  void dispose() {
    for (final c in [_name, _baseUrl, _model, _key]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(t('自定义 API', 'Custom API')),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: t('名称', 'Name'), hintText: t('例如 我的中转', 'e.g. my relay')),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ApiKind>(
              segments: [
                ButtonSegment(value: ApiKind.openai, label: Text(t('OpenAI 兼容', 'OpenAI-compatible'))),
                ButtonSegment(value: ApiKind.deepseek, label: Text(t('DeepSeek 方言', 'DeepSeek dialect'))),
              ],
              selected: {_kind},
              onSelectionChanged: (value) => setState(() => _kind = value.first),
            ),
            const SizedBox(height: 4),
            Text(
              _kind == ApiKind.deepseek
                  ? t('按 DeepSeek 的 /beta 前缀与 thinking 字段发送。', 'Sends the /beta prefix and thinking field DeepSeek uses.')
                  : t('请求发往 Base URL + /chat/completions。', 'Requests go to Base URL + /chat/completions.'),
              style: theme.textTheme.bodySmall?.copyWith(color: DshColors.of(context).textTertiary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _baseUrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://api.openai.com/v1',
                suffixIcon: PopupMenuButton<String>(
                  tooltip: t('常见地址', 'Common URLs'),
                  icon: const Icon(Icons.expand_more, size: 20),
                  onSelected: (value) => setState(() => _baseUrl.text = value),
                  itemBuilder: (context) => [
                    for (final url in ApiProfile.suggestions) PopupMenuItem(value: url, child: Text(url)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _model,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: t('模型', 'Model'),
                hintText: 'gpt-4o-mini / deepseek-chat / …',
                suffixIcon: IconButton(
                  onPressed: _pickModel,
                  icon: const Icon(Icons.list_alt, size: 18),
                  tooltip: t('从上游获取模型', 'Fetch models from the provider'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: 'sk-…',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _showKey = !_showKey),
                  icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility, size: 18),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _stream,
              onChanged: (value) => setState(() => _stream = value),
              title: Text(t('用 SSE 流式返回', 'Stream with SSE')),
              subtitle: Text(t('关掉则等整段回复一次返回', 'Off: wait for the whole reply')),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              value: _thinking,
              onChanged: (value) => setState(() => _thinking = value),
              title: Text(t('思考模式', 'Thinking')),
              subtitle: Text(t('只有 DeepSeek 官方/方言端点会读这个字段', 'Only DeepSeek endpoints read this field')),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _testing ? null : _runTest,
                  icon: _testing
                      ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bolt, size: 18),
                  label: Text(t('测试连接', 'Test connection')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _test ?? '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: (_test ?? '').startsWith('OK')
                          ? DshColors.of(context).success
                          : DshColors.of(context).danger,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t('取消', 'Cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: Text(t('保存', 'Save')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ApiProfile _collect() => widget.profile.copyWith(
    name: _name.text.trim().isEmpty ? _baseUrl.text.trim() : _name.text.trim(),
    kind: _kind,
    baseUrl: _baseUrl.text.trim(),
    model: _model.text.trim(),
    apiKey: _key.text.trim(),
    thinking: _thinking,
    stream: _stream,
    vision: _vision,
    contextWindow: _contextWindow,
    maxOutput: _maxOutput,
  );

  /// 问上游要模型清单，选一个把 id 与能力一起带回来。
  Future<void> _pickModel() async {
    final base = _baseUrl.text.trim();
    final key = _key.text.trim();
    if (base.isEmpty || key.isEmpty) {
      setState(() => _test = t('先填 Base URL 和 Key，再去获取模型。', 'Fill the base URL and key first.'));
      return;
    }
    final info = await showModelPicker(context, baseUrl: base, apiKey: key, current: _model.text.trim());
    if (info == null || !mounted) return;
    setState(() {
      _model.text = info.id;
      _vision = info.vision;
      _contextWindow = info.contextWindow;
      _maxOutput = info.maxOutput;
      _thinking = info.thinking || _thinking;
    });
  }

  void _save() {
    final profile = _collect();
    if (profile.baseUrl.isEmpty) {
      setState(() => _test = t('先填 Base URL。', 'Fill in the Base URL first.'));
      return;
    }
    Navigator.of(context).pop(profile);
  }

  Future<void> _runTest() async {
    final profile = _collect();
    if (profile.baseUrl.isEmpty || profile.apiKey.isEmpty) {
      setState(() => _test = t('Base URL 和 Key 都要填。', 'Base URL and key are both required.'));
      return;
    }
    setState(() {
      _testing = true;
      _test = null;
    });
    final started = DateTime.now();
    try {
      final uri = _endpoint(profile);
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${profile.apiKey}'},
            body: jsonEncode({
              'model': profile.model.isEmpty ? 'gpt-4o-mini' : profile.model,
              'messages': [
                {'role': 'user', 'content': 'ping'},
              ],
              'max_tokens': 8,
              'stream': false,
              if (profile.kind == ApiKind.deepseek) 'thinking': {'type': 'disabled'},
            }),
          )
          .timeout(const Duration(seconds: 25));
      final ms = DateTime.now().difference(started).inMilliseconds;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() => _test = 'OK · ${response.statusCode} · $ms ms');
      } else {
        final body = _redact(response.body, profile.apiKey);
        setState(() => _test = 'HTTP ${response.statusCode} · $ms ms\n$body');
      }
    } on TimeoutException {
      setState(() => _test = t('超时（25 秒）', 'Timed out (25 s)'));
    } catch (error) {
      setState(() => _test = _redact('$error', profile.apiKey));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// The same URL rule the engine applies (`TavernModelConfig.endpoint`).
  Uri _endpoint(ApiProfile profile) {
    final uri = Uri.parse(profile.baseUrl.trim());
    var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (!path.endsWith('/chat/completions')) path = '$path/chat/completions';
    return uri.replace(path: path);
  }

  static String _redact(String text, String key) {
    var out = key.isEmpty ? text : text.replaceAll(key, '[redacted]');
    out = out.replaceAll(RegExp(r'Bearer\s+[^\s"<>]+', caseSensitive: false), 'Bearer [redacted]');
    return out.length > 400 ? out.substring(0, 400) : out;
  }
}
