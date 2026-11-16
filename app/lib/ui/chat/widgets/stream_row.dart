// Tavern Lite: the quiet detail line under a streaming reply ("思考了 3 秒").
// Only `StreamRow.detail` is used by the tavern page.

import 'package:flutter/material.dart';

import '../../theme/theme.dart';

class StreamRow extends StatelessWidget {
  const StreamRow({super.key, required this.child});

  final Widget child;

  /// The small, tertiary line used beside the thinking label.
  static TextStyle? detail(BuildContext context) => Theme.of(
    context,
  ).textTheme.labelSmall?.copyWith(color: DshColors.of(context).textTertiary, height: 1.2);

  @override
  Widget build(BuildContext context) => Align(alignment: Alignment.centerLeft, child: child);
}

/// The small dot between two runs of a streaming line.
class StreamDot extends StatelessWidget {
  const StreamDot({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: SizedBox.square(
      dimension: 3,
      child: DecoratedBox(
        decoration: BoxDecoration(color: DshColors.of(context).textTertiary, shape: BoxShape.circle),
      ),
    ),
  );
}
