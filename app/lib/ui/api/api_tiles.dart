// 设置里那两行：现在走哪个接口、用哪个模型。
//
// 酒馆设置（我的）和对话里的「本局」都用这一对，点接口去配置页，点模型
// 问上游要一份清单来选。识图 / 思考 / 上下文是选模型时上游自己说的。
//
// 本局面板很窄：`compact` 时不显示副标题，值也限宽省略，否则长 URL 会把
// 一行撑出卡片。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_profiles.dart';
import '../../l10n/l10n.dart';
import '../../state/model_access.dart';
import '../../state/settings_state.dart';
import '../../tavern/tavern_settings.dart';
import '../settings/settings_widgets.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'api_profiles_page.dart';
import 'model_picker.dart';

/// 当前生效的接口：官方或某个自定义 profile。
ApiProfile activeApiProfile(WidgetRef ref) => ref.watch(apiProfilesProvider).active;

/// 这个接口的 Key：官方读 AppSettings，自定义读 profile。
String apiKeyOf(WidgetRef ref) {
  final active = activeApiProfile(ref);
  return active.isOfficial ? ref.read(settingsProvider).apiKey.trim() : active.apiKey.trim();
}

String apiBaseOf(WidgetRef ref) {
  final active = activeApiProfile(ref);
  return active.isOfficial ? ApiProfile.official.baseUrl : active.baseUrl.trim();
}

/// The model id the next turn will use.
String currentModelOf(WidgetRef ref) {
  final active = activeApiProfile(ref);
  return active.isOfficial ? ref.watch(tavernSettingsProvider).model : active.model.trim();
}

class ApiProviderTile extends ConsumerWidget {
  const ApiProviderTile({super.key, this.tinted = true, this.compact = false});

  final bool tinted;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = activeApiProfile(ref);
    final name = active.name.trim();
    final base = active.baseUrl.trim();
    final label = active.isOfficial ? ApiProfile.official.name : (name.isEmpty ? t('自定义', 'Custom') : name);
    // A profile saved without a name took its URL as one; don't print it twice.
    final subtitle = compact || active.isOfficial
        ? null
        : (base.isEmpty || base == name ? null : base);
    return SettingsTile(
      key: const ValueKey('api-provider'),
      icon: AppIcons.providers,
      tinted: tinted,
      title: t('接口', 'Provider'),
      subtitle: subtitle,
      value: _Value(label, maxWidth: compact ? 150 : 240),
      onTap: () => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ApiProfilesPage()))),
    );
  }
}

class ApiModelTile extends ConsumerWidget {
  const ApiModelTile({super.key, this.tinted = true, this.enabled = true, this.compact = false});

  final bool tinted;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = activeApiProfile(ref);
    final model = currentModelOf(ref);
    final vision = !active.isOfficial && active.vision;
    final contextLabel = !active.isOfficial && active.contextWindow != null ? _tokens(active.contextWindow!) : null;
    final bits = [
      if (vision) t('识图', 'vision'),
      if (active.thinking || (active.isOfficial && ref.watch(tavernSettingsProvider).thinking)) t('思考', 'thinking'),
      if (contextLabel != null) '$contextLabel 上下文',
    ];
    return SettingsTile(
      key: const ValueKey('api-model'),
      icon: AppIcons.model,
      tinted: tinted,
      title: t('模型', 'Model'),
      subtitle: compact || bits.isEmpty ? null : bits.join(' · '),
      value: _Value(model.isEmpty ? t('未选择', 'not set') : model, maxWidth: compact ? 150 : 240),
      onTap: enabled ? () => unawaited(pickApiModel(context, ref)) : null,
    );
  }
}

/// A right-aligned value that never widens its row past [maxWidth].
class _Value extends StatelessWidget {
  const _Value(this.text, {required this.maxWidth});

  final String text;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
  );
}

/// 问上游要模型清单，选一个写回：官方写进酒馆设置，自定义写进 profile。
Future<void> pickApiModel(BuildContext context, WidgetRef ref) async {
  final active = activeApiProfile(ref);
  final key = apiKeyOf(ref);
  if (key.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          active.isOfficial
              ? t('先在「接口」里填 DeepSeek 官方 Key', 'Add the DeepSeek API key first')
              : t('先在这个接口里填 Key', 'Add a key for this provider first'),
        ),
      ),
    );
    return;
  }
  final info = await showModelPicker(
    context,
    baseUrl: apiBaseOf(ref),
    apiKey: key,
    current: currentModelOf(ref),
  );
  if (info == null) return;
  if (active.isOfficial) {
    await ref.read(tavernSettingsProvider.notifier).setModel(info.id);
  } else {
    await ref.read(apiProfilesProvider.notifier).upsert(
      active.copyWith(
        model: info.id,
        vision: info.vision,
        contextWindow: info.contextWindow,
        maxOutput: info.maxOutput,
      ),
    );
  }
}

/// A quiet line when the active endpoint has no key yet.
class ApiMissingKeyNotice extends ConsumerWidget {
  const ApiMissingKeyNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(modelAccessProvider)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        t('这个接口还没有 Key，点「接口」填一个。', 'This provider has no key yet — open Provider to add one.'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DshColors.of(context).warning),
      ),
    );
  }
}

String _tokens(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(value % 1000000 == 0 ? 0 : 1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}K';
  return '$value';
}
