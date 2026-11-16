// Tavern Lite: an inline notice row (the chat's quiet "no key" line, and the
// engine's own notices). The original also had a retry action and DSH's error
// mapping; here it is only text.

import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../theme/app_icons.dart';
import '../../theme/theme.dart';

class NoticeRow extends StatelessWidget {
  const NoticeRow({super.key, required this.text, this.icon, this.action, this.tone = NoticeTone.quiet});

  final String text;
  final IconData? icon;
  final Widget? action;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final dsh = DshColors.of(context);
    final color = switch (tone) {
      NoticeTone.warn => dsh.warning,
      NoticeTone.danger => dsh.danger,
      NoticeTone.quiet => dsh.textTertiary,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (icon case final icon?) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 8)],
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color, height: 1.4)),
          ),
          if (action case final action?) ...[const SizedBox(width: 8), action],
        ],
      ),
    );
  }
}

enum NoticeTone { quiet, warn, danger }

/// A word and what it does, beside a notice.
typedef NoticeAction = ({String label, VoidCallback onPressed});

/// The last turn's error over the composer: the reason, and the way on.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.message,
    this.onDismiss,
    this.info = false,
    this.action,
    this.maxLines = 3,
  });

  final String message;
  final VoidCallback? onDismiss;
  final bool info;
  final NoticeAction? action;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final container = info ? dsh.infoContainer : dsh.dangerContainer;
    final accent = info ? dsh.info : dsh.danger;
    final onContainer = info ? dsh.onInfoContainer : dsh.onDangerContainer;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(container.withValues(alpha: 0.92), theme.colorScheme.surface),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.3), width: 0.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Icon(info ? AppIcons.info : AppIcons.error, size: 17, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  maxLines: maxLines,
                  overflow: maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: onContainer),
                ),
              ),
              if (action case final action?)
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: onContainer),
                  onPressed: action.onPressed,
                  child: Text(action.label),
                ),
              if (onDismiss != null)
                IconButton(
                  tooltip: l10n.commonClose,
                  onPressed: onDismiss,
                  iconSize: 18,
                  style: IconButton.styleFrom(minimumSize: const Size(40, 40), foregroundColor: onContainer),
                  icon: const Icon(AppIcons.close),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "no key yet" line over the composer.
class NoApiKeyNotice extends StatelessWidget {
  const NoApiKeyNotice({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => NoticeRow(
    text: context.l10n.tavernComposerNoKey,
    icon: Icons.key_outlined,
    tone: NoticeTone.warn,
    action: TextButton(onPressed: onOpenSettings, child: Text(context.l10n.commonSettings)),
  );
}
