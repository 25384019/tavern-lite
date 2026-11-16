// Tavern Lite: the stage under a chat — a chosen picture, softened, with the
// page's own colour laid over it so text keeps its contrast. Lifted from
// `ui/wallpaper/wallpaper_backdrop.dart`, minus the app-wide wallpaper state
// and the chat header's colour probe.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../wallpaper/custom_wallpaper.dart';
import '../theme/theme.dart';

class WallpaperBackdrop extends StatelessWidget {
  const WallpaperBackdrop({super.key, required this.picture, required this.child});

  /// A chat's own picture, if it has one.
  const WallpaperBackdrop.scene({super.key, required this.picture, required this.child});

  final CustomWallpaper? picture;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final picture = this.picture;
    if (picture == null) return child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final overlay = dark
        ? Colors.black.withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.35);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: picture.blur * 24, sigmaY: picture.blur * 24),
            child: Image.file(
              File(picture.path),
              fit: BoxFit.cover,
              alignment: Alignment(picture.alignX, picture.alignY),
              errorBuilder: (context, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        Positioned.fill(child: ColoredBox(color: overlay)),
        child,
      ],
    );
  }
}
