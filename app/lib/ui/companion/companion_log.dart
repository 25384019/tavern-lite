// Tavern Lite: the visual novel's backlog, in the story's own look.
//
// Lifted from `ui/companion/companion_log.dart` (a full-screen log with a
// scrim, her lines and yours). Only the parts the tavern's 视觉小说 uses.

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// One line of the backlog.
class CompanionLogEntry {
  const CompanionLogEntry(this.text, {this.who, this.tone, this.mine = false});

  /// Your line, prefixed as the chat shows it.
  factory CompanionLogEntry.you(String text) => CompanionLogEntry(text, mine: true);

  /// Her line, or a group member's when [who] is given.
  factory CompanionLogEntry.her(String text, {String? who, Color? tone}) =>
      CompanionLogEntry(text, who: who, tone: tone);

  final String text;
  final String? who;
  final Color? tone;
  final bool mine;
}

/// Fades and slides the backlog in.
class CompanionLogTransition extends StatelessWidget {
  const CompanionLogTransition({super.key, required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: AppMotion.of(context, AppMotion.standard),
    switchInCurve: AppMotion.std,
    switchOutCurve: AppMotion.std,
    child: child ?? const SizedBox.shrink(),
  );
}

/// The backlog itself: a scrim, the lines, and a close key.
class CompanionLog extends StatelessWidget {
  const CompanionLog({
    super.key,
    required this.entries,
    required this.name,
    required this.onClose,
    this.scrim = const [Color(0xEE000000), Color(0xF2000000)],
    this.herTone,
    this.youTone,
  });

  final List<CompanionLogEntry> entries;
  final String name;
  final VoidCallback onClose;
  final List<Color> scrim;
  final Color? herTone;
  final Color? youTone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: scrim),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(name, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close, size: 22),
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final tone = entry.mine ? (youTone ?? dsh.textTertiary) : (entry.tone ?? herTone ?? theme.colorScheme.primary);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (entry.who case final who?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            who,
                            style: theme.textTheme.labelMedium?.copyWith(color: tone, fontWeight: FontWeight.w600),
                          ),
                        ),
                      Text(
                        entry.text,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                      ),
                    ],
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
