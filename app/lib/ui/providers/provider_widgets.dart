// Tavern Lite: the form anatomy shared by the tavern's edit pages.
//
// The original (`ui/providers/provider_widgets.dart`) was the 模型渠道 pages'
// kit: provider health dots, model summaries and these form pieces. The
// tavern uses only the form pieces, so only they are here.

import 'package:flutter/material.dart';

import '../common/smooth_size.dart';
import '../settings/settings_widgets.dart' show SettingsMetrics;
import '../theme/theme.dart';

class FormFieldGroup extends StatelessWidget {
  const FormFieldGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(SettingsMetrics.inset, 12, SettingsMetrics.inset, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );
}

class FormFieldLabel extends StatelessWidget {
  const FormFieldLabel(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  static const indent = 4.0;
  static const gap = 4.0;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 28),
    child: Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: indent),
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class FormFieldBlock extends StatelessWidget {
  const FormFieldBlock({
    super.key,
    required this.label,
    required this.child,
    this.helper,
    this.error,
    this.trailing,
    this.below,
  });

  final String label;
  final Widget child;
  final String? helper;
  final String? error;
  final Widget? trailing;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormFieldLabel(label, trailing: trailing),
          const SizedBox(height: FormFieldLabel.gap),
          child,
          SmoothSize(
            duration: AppMotion.of(context, AppMotion.standard),
            alignment: Alignment.topLeft,
            child: AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.standard),
              child: error == null && helper == null
                  ? const SizedBox.shrink()
                  : SizedBox(
                      key: ValueKey((error != null, error ?? helper)),
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                        child: Semantics(
                          liveRegion: error != null,
                          child: Text(
                            error ?? helper!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: error != null ? DshColors.of(context).danger : DshColors.of(context).textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          if (below case final below?) ...[const SizedBox(height: 10), below],
        ],
      ),
    );
  }
}

class FormSmallButton extends StatelessWidget {
  const FormSmallButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: const Size(0, 28),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      textStyle: Theme.of(context).textTheme.labelMedium,
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}

class FormBottomBar extends StatelessWidget {
  const FormBottomBar({super.key, required this.child});

  final Widget child;

  /// Room to leave at the end of the page so nothing hides under the bar.
  static const height = 88.0;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom > 0 ? 0.0 : MediaQuery.viewPaddingOf(context).bottom;
    final base = DshSurfaces.of(context).backdropBottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [base.withValues(alpha: 0), base.withValues(alpha: 0.96), base.withValues(alpha: 0.98)],
          stops: const [0, 0.26, 1],
        ),
      ),
      child: Padding(padding: EdgeInsets.fromLTRB(16, 24, 16, 12 + bottom), child: child),
    );
  }
}
