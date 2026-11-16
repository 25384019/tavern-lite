import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// A soft rose and blue setting for the tavern's reading surfaces.
class TavernRomanceTheme extends StatelessWidget {
  const TavernRomanceTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.brightness == Brightness.dark) return child;
    final surfaces = DshSurfaces.of(context).copyWith(
      backdropTop: const Color(0xffffedf3),
      backdropBottom: const Color(0xffeaf0fc),
      glowPrimary: const Color(0x55e2a4c3),
      glowSecondary: const Color(0x559ebce6),
    );
    return Theme(
      data: theme.copyWith(
        extensions: [
          ...theme.extensions.values.where(
            (extension) => extension is! DshSurfaces,
          ),
          surfaces,
        ],
      ),
      child: child,
    );
  }
}
