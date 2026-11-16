// Tavern Lite: every WebView of the app survives its renderer.
//
// The original guard talked to DSH's islands plugin, which wrapped the
// WebView's client on the Android side so a killed renderer could be reported
// instead of taking the process with it. That plugin is not part of this app,
// so the guard keeps the same surface and only tracks the WebView: the pages
// that carry card HTML still build, and a renderer loss is Android's own
// behaviour rather than something this file can intercept.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewGuard {
  WebViewGuard({required this.onGone});

  /// The renderer is gone ([crashed]: crashed rather than killed).
  final void Function(bool crashed) onGone;

  int? _id;

  /// webview_flutter_android's `AndroidWebViewController.webViewIdentifier`,
  /// without depending on the platform package. Null off Android.
  static int? identifierOf(WebViewController controller) {
    try {
      final Object? id = (controller.platform as dynamic).webViewIdentifier;
      return id is int ? id : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> attach(WebViewController controller, {required bool dark, required int textZoom}) async {
    _id = identifierOf(controller);
    try {
      await controller.setBackgroundColor(dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF));
    } catch (_) {
      // A controller whose platform view is not ready yet: nothing to set.
    }
  }

  Future<void> setDark(bool dark) async {}

  Future<void> setTextZoom(int percent) async {}

  Future<void> destroy() async {
    _id = null;
  }

  void dispose() {}
}
