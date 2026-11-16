// Tavern Lite — DSH Go's 酒馆 module as a standalone app.
//
// The original `main.dart` booted the DSH runtime, the launch animation and the
// whole shell before ever showing a page. Nothing of that is here: the app is
// the tavern, opened straight onto its home.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'l10n/l10n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final locale = AppLocale.resolve(null, PlatformDispatcher.instance.locales);
  AppLocale.use(locale);
  // Edge-to-edge with transparent system bars; pages refine the icon
  // brightness through AnnotatedRegion(dshSystemOverlay(...)).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ProviderScope(child: TavernLiteApp()));
}
