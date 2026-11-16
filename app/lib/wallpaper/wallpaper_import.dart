// Tavern Lite: picking a picture from the system file picker and copying it
// into the app's own storage. The original (wallpaper/wallpaper_import.dart)
// also handled Android's "share to app" launch imports and the DSH native file
// channel; the tavern only ever needs a pick, a copy and a delete.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';

import 'custom_wallpaper.dart';

/// Why a picture was not taken.
enum LaunchImportProblem {
  cancelled,
  unreadable,
  tooLarge,
  unsupported,

  /// The picker never ran (no activity to open it in).
  unavailable,

  /// The card itself is over the import budget.
  overLimit,
}

/// Copies chosen pictures into [directory] and answers with what was stored.
class WallpaperImport {
  WallpaperImport({required this.directory});

  /// Where the copies go; created on demand.
  final Future<Directory> Function() directory;

  /// The system picker. [previous] is left alone when nothing is chosen.
  Future<(CustomWallpaper?, LaunchImportProblem?)> pick({CustomWallpaper? previous}) async {
    List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(type: FileType.image);
    } catch (_) {
      return (null, LaunchImportProblem.unreadable);
    }
    final path = picked.singleOrNull?.path;
    if (path == null) return (null, LaunchImportProblem.cancelled);
    final file = File(path);
    if (!file.existsSync()) return (null, LaunchImportProblem.unreadable);
    final size = file.lengthSync();
    if (size > CustomWallpaper.maxBytes) return (null, LaunchImportProblem.tooLarge);
    final bytes = await file.readAsBytes();
    final ui.Image image;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      image = (await codec.getNextFrame()).image;
    } catch (_) {
      return (null, LaunchImportProblem.unreadable);
    }
    try {
      final dir = await directory();
      final copy = File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}');
      await copy.writeAsBytes(bytes, flush: true);
      image.dispose();
      return (
        CustomWallpaper(
          path: copy.path,
          width: image.width,
          height: image.height,
          blur: previous?.blur ?? CustomWallpaper.defaultBlur,
          lighten: previous?.lighten ?? CustomWallpaper.defaultLighten,
          dim: previous?.dim ?? CustomWallpaper.defaultDim,
        ),
        null,
      );
    } catch (_) {
      image.dispose();
      return (null, LaunchImportProblem.unreadable);
    }
  }

  static Future<void> removeFile(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // A file already gone is the state we wanted.
    }
  }
}
