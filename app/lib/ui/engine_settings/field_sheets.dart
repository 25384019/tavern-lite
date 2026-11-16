// Tavern Lite: the sheet card and stepper key the dice sheet borrows from
// DSH's engine settings. The originals sat in a 1500-line settings file.

import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/theme.dart';

/// A rounded block inside a sheet.
class SheetCard extends StatelessWidget {
  const SheetCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GlassSurface(
    tier: GlassTier.card,
    onTap: onTap,
    child: Padding(padding: padding, child: child),
  );
}

/// The round 鈭?+ key beside a number.
class StepKey extends StatelessWidget {
  const StepKey({super.key, required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    enabled: onPressed != null,
    child: SizedBox.square(
      dimension: 40,
      child: GlassSurface(
        tier: GlassTier.pill,
        circle: true,
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: Center(
            child: Icon(
              icon,
              size: 20,
              color: onPressed == null ? DshColors.of(context).textDisabled : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    ),
  );
}

/// A step key that decrements; kept for the dice sheet's symmetry.
IconData get decrementIcon => AppIcons.decrement;

