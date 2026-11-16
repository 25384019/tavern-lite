// Tavern Lite: the app's link router, reduced to the one route the tavern uses.
//
// In DSH Go this routed `dshgo://` and file-open intents to the right page. This
// app has a single page tree, so the router only remembers a context for the
// file handlers and keeps the registration surface the tavern's intake host
// calls; Android's `VIEW`/`SEND` intents are not wired here.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef FileLinkHandler = Future<bool> Function(Uri uri);

class LinkRouter {
  /// A context to push pages with, when one is mounted.
  BuildContext? context;

  final _handlers = <String, FileLinkHandler>{};

  /// Registers a handler for [extension] (without the dot); returns its
  /// unregister function.
  VoidCallback registerFileHandler(String extension, FileLinkHandler handler) {
    _handlers[extension.toLowerCase()] = handler;
    return () => _handlers.remove(extension.toLowerCase());
  }

  /// Offers [uri] to the handler for its extension; false when none took it.
  Future<bool> openFile(Uri uri) async {
    final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    final handler = _handlers[name.substring(dot + 1).toLowerCase()];
    if (handler == null) return false;
    return handler(uri);
  }
}

final linkRouterProvider = Provider<LinkRouter>((ref) => LinkRouter());
