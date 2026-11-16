// Tavern Lite: images inside Markdown — web, `data:` and files on the phone.
//
// The original resolved workspace paths through the DSH session and could
// preview artifacts (966 lines). This app has no session workspace: a relative
// path is looked up under the chat's own folder, and anything unreadable is
// shown as the link it is.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Collects the images of one message so a tap can page through them.
class MarkdownGalleryScope extends StatelessWidget {
  const MarkdownGalleryScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The folder relative links resolve against, and the chat they belong to.
class MarkdownImageScope extends InheritedWidget {
  const MarkdownImageScope({super.key, required this.sessionId, this.baseDir, required super.child});

  final String sessionId;
  final String? baseDir;

  static MarkdownImageScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarkdownImageScope>();

  @override
  bool updateShouldNotify(MarkdownImageScope oldWidget) =>
      sessionId != oldWidget.sessionId || baseDir != oldWidget.baseDir;
}

/// The font size of the text around an image.
class MarkdownImageFont extends InheritedWidget {
  const MarkdownImageFont({super.key, required this.size, required super.child});

  final double size;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarkdownImageFont>()?.size ?? 16.0;

  @override
  bool updateShouldNotify(MarkdownImageFont oldWidget) => size != oldWidget.size;
}

/// `![alt](url)` for `gpt_markdown`.
Widget markdownImageBuilder(BuildContext context, String imageUrl, double? width, double? height) =>
    MarkdownImage(url: imageUrl, width: width, height: height);

class MarkdownImage extends StatelessWidget {
  const MarkdownImage({super.key, required this.url, this.width, this.height, this.alt});

  final String url;
  final double? width;
  final double? height;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final scope = MarkdownImageScope.maybeOf(context);
    final provider = _provider(scope?.baseDir);
    if (provider == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          alt == null || alt!.isEmpty ? url : alt!,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );
    }
    final size = MediaQuery.sizeOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width ?? size.width * 0.72,
            maxHeight: height ?? size.height * 0.6,
          ),
          child: Image(
            image: provider,
            width: width,
            height: height,
            fit: BoxFit.contain,
            errorBuilder: (context, _, _) => _Broken(url: url),
          ),
        ),
      ),
    );
  }

  ImageProvider? _provider(String? baseDir) {
    final url = this.url.trim();
    if (url.isEmpty) return null;
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma < 0) return null;
      try {
        return MemoryImage(Uint8List.fromList(base64Decode(url.substring(comma + 1))));
      } catch (_) {
        return null;
      }
    }
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) return NetworkImage(url);
    if (uri != null && uri.scheme == 'file') {
      final file = File(uri.toFilePath());
      return file.existsSync() ? FileImage(file) : null;
    }
    final String? path;
    if (url.startsWith('/')) {
      path = url;
    } else if (baseDir != null) {
      path = '$baseDir/$url';
    } else {
      path = null;
    }
    if (path == null) return null;
    final file = File(path);
    return file.existsSync() ? FileImage(file) : null;
  }
}

class _Broken extends StatelessWidget {
  const _Broken({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final dsh = DshColors.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: dsh.codeWellBg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported_outlined, size: 16, color: dsh.textTertiary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              url,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: dsh.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
