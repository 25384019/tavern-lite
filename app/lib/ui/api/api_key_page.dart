// Tavern Lite: the key page the tavern pushes when a turn needs a model and
// none is configured. In DSH Go this was the onboarding's API key step; here it
// is the DeepSeek key plus the way to the multi-API list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/settings_state.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'api_profiles_page.dart';

class ApiKeyPage extends ConsumerStatefulWidget {
  const ApiKeyPage({super.key, this.onboarding = false});

  /// Kept for the call sites that came from onboarding; this app has no
  /// onboarding, so it only changes the title.
  final bool onboarding;

  @override
  ConsumerState<ApiKeyPage> createState() => _ApiKeyPageState();
}

class _ApiKeyPageState extends ConsumerState<ApiKeyPage> {
  late final _key = TextEditingController(text: ref.read(settingsProvider).apiKey);
  bool _shown = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = DshColors.of(context).textTertiary;
    return Scaffold(
      appBar: AppBar(title: Text(widget.onboarding ? t('开始使用', 'Get started') : t('API Key', 'API key'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(t('DeepSeek 官方', 'DeepSeek official'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _key,
            obscureText: !_shown,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'DeepSeek API Key',
              hintText: 'sk-…',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _shown = !_shown),
                icon: Icon(_shown ? Icons.visibility_off : Icons.visibility, size: 18),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              await ref.read(settingsProvider.notifier).setApiKey(_key.text);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('已保存', 'Saved'))));
            },
            icon: const Icon(AppIcons.save, size: 18),
            label: Text(t('保存', 'Save')),
          ),
          const SizedBox(height: 24),
          Text(t('其它接口', 'Other endpoints'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            t('OpenAI 兼容的自定义 API 可保存多份，填 Base URL、Key 和模型，随时切换。',
                'OpenAI-compatible endpoints can be saved as profiles with their own base URL, key and model, and switched at any time.'),
            style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ApiProfilesPage()),
            ),
            icon: const Icon(AppIcons.apiKey, size: 18),
            label: Text(t('打开 API 配置', 'Open API settings')),
          ),
        ],
      ),
    );
  }
}
