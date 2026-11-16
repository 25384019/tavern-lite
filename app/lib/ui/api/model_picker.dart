// 选模型：问上游要一份清单，带上下文、识图、思考，点一个就用它。
//
// 官方端点与自定义端点共用这一个面板：传进来的只是一个 baseUrl 和 key。

import 'package:flutter/material.dart';

import '../../api/model_catalog.dart';
import '../../l10n/l10n.dart';
import '../common/app_sheet.dart';
import '../common/sheet_title_bar.dart';
import '../theme/theme.dart';
import 'api_profiles_page.dart' show t;

/// Returns the chosen model, or null when the sheet was closed.
Future<ModelInfo?> showModelPicker(
  BuildContext context, {
  required String baseUrl,
  required String apiKey,
  String? current,
}) => showAppSheet<ModelInfo>(
  context,
  isScrollControlled: true,
  builder: (context) => ModelPicker(baseUrl: baseUrl, apiKey: apiKey, current: current),
);

class ModelPicker extends StatefulWidget {
  const ModelPicker({super.key, required this.baseUrl, required this.apiKey, this.current});

  final String baseUrl;
  final String apiKey;
  final String? current;

  @override
  State<ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<ModelPicker> {
  Future<List<ModelInfo>>? _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = fetchModelCatalog(baseUrl: widget.baseUrl, apiKey: widget.apiKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: SheetTitleBar(t('选择模型', 'Choose a model'))),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: t('重新获取', 'Refresh'),
                ),
              ],
            ),
            Text(
              t('列表来自 ${widget.baseUrl}/models', 'Fetched from ${widget.baseUrl}/models'),
              style: theme.textTheme.bodySmall?.copyWith(color: DshColors.of(context).textTertiary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            TextField(
              onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: t('筛选', 'Filter'),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
              child: FutureBuilder<List<ModelInfo>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return _Error(error: snapshot.error!, onRetry: _load);
                  }
                  final models = (snapshot.data ?? const <ModelInfo>[])
                      .where((m) => _query.isEmpty || m.id.toLowerCase().contains(_query) || (m.name ?? '').toLowerCase().contains(_query))
                      .toList();
                  if (models.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text(t('没有模型', 'No models'), textAlign: TextAlign.center),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: models.length,
                    itemBuilder: (context, index) {
                      final model = models[index];
                      return _ModelRow(
                        model: model,
                        selected: model.id == widget.current,
                        onTap: () => Navigator.of(context).pop(model),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.model, required this.selected, required this.onTap});

  final ModelInfo model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final meta = <String>[
      if (model.contextWindow case final window?) '${_tokens(window)} 上下文',
      if (model.maxOutput case final output?) '${_tokens(output)} 输出',
    ];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? theme.colorScheme.primary : dsh.textTertiary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(model.label, style: theme.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (model.vision) _Badge(t('识图', 'vision'), tone: theme.colorScheme.primary),
                      if (model.thinking) _Badge(t('思考', 'thinking'), tone: dsh.info),
                      if (model.efforts.isNotEmpty)
                        _Badge(model.efforts.join('/'), tone: dsh.textTertiary),
                      if (meta.isNotEmpty)
                        Text(meta.join(' · '), style: theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary)),
                      if (model.guessed)
                        Text(t('（按名字判断）', '(guessed)'),
                            style: theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tone)),
  );
}

class _Error extends StatelessWidget {
  const _Error({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Text(
            t('取不到模型列表', 'Could not fetch the model list'),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 6),
          Text(
            '$error',
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: DshColors.of(context).textTertiary),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text(context.l10n.commonRetry)),
        ],
      ),
    );
  }
}

String _tokens(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(value % 1000000 == 0 ? 0 : 1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}K';
  return '$value';
}
