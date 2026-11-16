// 资源库 › 内置内容：随包带来的世界书和角色卡，一键装进库里。
//
// 只读 AssetBundle，不联网；同名跳过，所以点几次都不会重复。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../tavern/bundled_content.dart';
import '../../tavern/tavern_provider.dart';
import '../common/brief_notice.dart';
import '../features/feature_kit.dart';
import '../settings/settings_widgets.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'tavern_lorebooks_page.dart';

/// 随包内容的清单。
final bundledManifestProvider =
    FutureProvider.autoDispose<
      ({List<BundledItem> books, List<BundledItem> cards})
    >((ref) => bundledContent());

class BundledContentPage extends ConsumerStatefulWidget {
  const BundledContentPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const BundledContentPage());

  @override
  ConsumerState<BundledContentPage> createState() => _BundledContentPageState();
}

class _BundledContentPageState extends ConsumerState<BundledContentPage> {
  var _busy = false;
  var _done = 0;
  var _total = 0;

  Future<void> _install() async {
    final l10n = context.l10n;
    final tavern = ref.read(tavernProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      final books = await tavern.listLorebooks();
      final cards = await tavern.watchCharacters().first;
      final result = await installBundledContent(
        tavern,
        existingBooks: {for (final b in books) b.name},
        existingCards: {for (final c in cards) c.name},
        onProgress: (done, total) {
          if (mounted)
            setState(() {
              _done = done;
              _total = total;
            });
        },
      );
      if (!mounted) return;
      if (result.failed.isNotEmpty) {
        messenger?.showBriefNotice(
          l10n.bundledFailed(result.failed.length, result.failed.join('；')),
        );
      } else if (result.books == 0 && result.cards == 0) {
        messenger?.showBriefNotice(l10n.bundledNothing);
      } else {
        messenger?.showBriefNotice(
          l10n.bundledDone(result.books, result.cards),
        );
      }
      // 装完要让列表看见：世界书和角色卡各自是独立的 provider。
      ref.invalidate(tavernLorebooksProvider);
      ref.invalidate(tavernCharactersProvider);
    } on Object {
      if (mounted) messenger?.showBriefNotice(l10n.bundledInstallFailed);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _done = 0;
          _total = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final manifest = ref.watch(bundledManifestProvider).value;
    final books = manifest?.books ?? const <BundledItem>[];
    final cards = manifest?.cards ?? const <BundledItem>[];

    return AppPage.list(
      title: l10n.bundledTitle,
      subtitle: Text(l10n.bundledSubtitle(books.length, cards.length)),
      children: [
        if (manifest == null)
          const QuietSpinner()
        else ...[
          SettingsSection(
            title: l10n.bundledBooks,
            children: [
              for (final item in books)
                SettingsTile(
                  key: ValueKey('bundled-book-${item.asset}'),
                  icon: AppIcons.lorebook,
                  tinted: false,
                  title: item.name,
                  chevron: false,
                ),
            ],
          ),
          SettingsSection(
            title: l10n.bundledCards,
            children: [
              for (final item in cards)
                SettingsTile(
                  key: ValueKey('bundled-card-${item.asset}'),
                  icon: AppIcons.tavern,
                  tinted: false,
                  title: item.name,
                  chevron: false,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FilledButton(
              key: const ValueKey('bundled-install'),
              onPressed: _busy ? null : () => unawaited(_install()),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(
                _busy
                    ? l10n.bundledInstalling(_done, _total)
                    : l10n.bundledInstall,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Text(
              l10n.bundledNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: DshColors.of(context).textTertiary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
