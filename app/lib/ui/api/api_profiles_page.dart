// API 配置: the DeepSeek official key and any number of saved
// OpenAI-compatible endpoints.
//
// This page is the app's replacement for DSH Go's onboarding key page: same
// job (put a key in), plus the list the original never had — several profiles,
// one active, each with its own base URL, model, key and stream setting.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_profiles.dart';
import '../../l10n/l10n.dart';
import '../../state/settings_state.dart';
import '../common/app_sheet.dart';
import '../common/sheet_title_bar.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'api_profile_editor.dart';

String t(String zh, String en) => AppLocale.isEnglish ? en : zh;

class ApiProfilesPage extends ConsumerWidget {
  const ApiProfilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(apiProfilesProvider);
    final settings = ref.watch(settingsProvider);
    final officialKey = settings.apiKey;
    return Scaffold(
      appBar: AppBar(title: Text(t('API 配置', 'API settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _OfficialCard(active: profiles.usesOfficial, hasKey: officialKey.trim().isNotEmpty, onActivate: () {
            ref.read(apiProfilesProvider.notifier).setActive(ApiProfile.officialId);
          }),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  t('自定义 API（OpenAI 兼容）', 'Custom APIs (OpenAI-compatible)'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: () => _add(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: Text(t('新增', 'Add')),
              ),
            ],
          ),
          if (profiles.custom.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                t('还没有自定义 API。可保存多个 Base URL / Key / 模型，随时切换。',
                    'No custom API yet. Save as many base URLs, keys and models as you like and switch between them.'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: DshColors.of(context).textTertiary),
              ),
            )
          else
            for (final profile in profiles.custom)
              _ProfileCard(
                profile: profile,
                active: profiles.activeId == profile.id,
                onActivate: () => ref.read(apiProfilesProvider.notifier).setActive(profile.id),
                onEdit: () => _edit(context, ref, profile),
                onDelete: () => _delete(context, ref, profile),
              ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final profile = await showApiProfileEditor(context, ref, ApiProfile(id: ApiProfilesController.newId(), name: ''));
    if (profile != null) {
      await ref.read(apiProfilesProvider.notifier).upsert(profile);
      await ref.read(apiProfilesProvider.notifier).setActive(profile.id);
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, ApiProfile profile) async {
    final next = await showApiProfileEditor(context, ref, profile);
    if (next != null) await ref.read(apiProfilesProvider.notifier).upsert(next);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, ApiProfile profile) async {
    final ok = await showAppSheet<bool>(
      context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetTitleBar(t('删除这个 API？', 'Delete this API?')),
              const SizedBox(height: 12),
              Text(profile.name.isEmpty ? profile.baseUrl : profile.name),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(t('取消', 'Cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(t('删除', 'Delete')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok ?? false) await ref.read(apiProfilesProvider.notifier).remove(profile.id);
  }
}

class _OfficialCard extends ConsumerWidget {
  const _OfficialCard({required this.active, required this.hasKey, required this.onActivate});

  final bool active;
  final bool hasKey;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return _Card(
      active: active,
      onTap: onActivate,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ApiProfile.official.name,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (active) _ActiveChip(),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'https://api.deepseek.com · deepseek-flash / deepseek-v4-pro',
              style: theme.textTheme.bodySmall?.copyWith(color: DshColors.of(context).textTertiary),
            ),
            const SizedBox(height: 12),
            _KeyField(initial: ref.watch(settingsProvider).apiKey, hasKey: hasKey),
          ],
        ),
      ),
    );
  }
}

class _KeyField extends ConsumerStatefulWidget {
  const _KeyField({required this.initial, required this.hasKey});

  final String initial;
  final bool hasKey;

  @override
  ConsumerState<_KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends ConsumerState<_KeyField> {
  late final _controller = TextEditingController(text: widget.initial);
  bool _shown = false;
  bool _saved = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            obscureText: !_shown,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: t('DeepSeek API Key', 'DeepSeek API key'),
              hintText: 'sk-…',
              isDense: true,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _shown = !_shown),
                icon: Icon(_shown ? Icons.visibility_off : Icons.visibility, size: 18),
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _save,
          child: Text(_saved ? t('已保存', 'Saved') : t('保存', 'Save')),
        ),
      ],
    );
  }

  Future<void> _save() async {
    await ref.read(settingsProvider.notifier).setApiKey(_controller.text);
    if (!mounted) return;
    setState(() => _saved = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _saved = false);
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.active,
    required this.onActivate,
    required this.onEdit,
    required this.onDelete,
  });

  final ApiProfile profile;
  final bool active;
  final VoidCallback onActivate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = DshColors.of(context).textTertiary;
    final model = profile.model.trim().isEmpty ? t('未填模型', 'no model') : profile.model;
    return _Card(
      active: active,
      onTap: onActivate,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile.name.trim().isEmpty ? profile.baseUrl : profile.name,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (active) ...[const SizedBox(width: 8), _ActiveChip()],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${profile.baseUrl} · $model${profile.stream ? ' · SSE' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (profile.apiKey.trim().isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        t('没有 Key', 'no key'),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(onPressed: onEdit, icon: const Icon(AppIcons.edit, size: 20), tooltip: t('编辑', 'Edit')),
            IconButton(onPressed: onDelete, icon: const Icon(AppIcons.delete, size: 20), tooltip: t('删除', 'Delete')),
          ],
        ),
      ),
    );
  }
}

class _ActiveChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      t('使用中', 'In use'),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, required this.active, required this.onTap});

  final Widget child;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: GlassSurface(
      tier: GlassTier.card,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6) : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: child,
      ),
    ),
  );
}
