// Tavern Lite: the thinking pill the story shows under a reply while the model
// reasons. The original lived in `ui/chat/widgets/thinking_pill.dart` and
// carried translation and engine-settings hooks; this keeps the look and the
// collapse, not the DSH plumbing.

import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../theme/app_icons.dart';
import '../../theme/theme.dart';

class ThinkingPill extends StatefulWidget {
  const ThinkingPill({super.key, required this.reasoning, this.active = false, this.streaming = false, this.meta});

  final String reasoning;

  /// Still thinking: the title says so and the pill pulses.
  final bool active;

  /// The text is still arriving; the pill keeps the last line in view.
  final bool streaming;

  /// A small trailing line (how long it has thought).
  final Widget? meta;

  @override
  State<ThinkingPill> createState() => _ThinkingPillState();
}

class _ThinkingPillState extends State<ThinkingPill> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            child: GlassSurface(
              tier: GlassTier.pill,
              stadium: true,
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _open ? AppIcons.expand : AppIcons.disclosure,
                      size: 16,
                      color: dsh.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.tavernThinking,
                      style: theme.textTheme.labelMedium?.copyWith(color: dsh.textTertiary),
                    ),
                    if (widget.meta case final meta?) ...[const SizedBox(width: 8), meta],
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 6),
              child: Text(
                widget.reasoning,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.45),
              ),
            ),
        ],
      ),
    );
  }
}

