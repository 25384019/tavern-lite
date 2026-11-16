// Tavern Lite: handing a file to another app (the storybook's share keys).
//
// The original went through DSH's share gallery (native image rendering and a
// slot ledger). share_plus does the same job for a file we already wrote.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ShareExporter {
  const ShareExporter();

  /// Writes [bytes] beside the app's temporary files and answers with the file.
  Future<File> write(Uint8List bytes, {String extension = 'png'}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/tavern-${DateTime.now().millisecondsSinceEpoch}.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// The system share sheet.
  Future<void> share(File file, {String? text}) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: text));
  }

  /// "Save": the share sheet with a save-to-files target, as Android offers.
  Future<void> save(File file) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: file.uri.pathSegments.last),
    );
  }
}

final shareExporterProvider = Provider<ShareExporter>((ref) => const ShareExporter());

/// Waits until the boundary under [context] has no pending frame, so the
/// picture captured just after it is complete: images inside the card have
/// decoded and the layout has settled.
Future<void> shareImagesSettled(BuildContext context) async {
  final binding = WidgetsBinding.instance;
  for (var i = 0; i < 4 && binding.hasScheduledFrame; i++) {
    await binding.endOfFrame;
  }
}
