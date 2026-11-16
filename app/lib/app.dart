import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/l10n.dart';
import 'state/settings_state.dart';
import 'ui/tavern/tavern_home_page.dart';
import 'ui/theme/theme.dart';

class TavernLiteApp extends ConsumerStatefulWidget {
  const TavernLiteApp({super.key});

  @override
  ConsumerState<TavernLiteApp> createState() => _TavernLiteAppState();
}

class _TavernLiteAppState extends ConsumerState<TavernLiteApp> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    // Text read through `appL10n` has no dependency to notify; switching the
    // language rebuilds the tree from here, as the original app did.
    AppLocale.use(AppLocale.current);
    return MaterialApp(
      title: 'Tavern Lite',
      debugShowCheckedModeBanner: false,
      locale: AppLocale.current,
      supportedLocales: AppLocale.supported,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildLightTheme(glyphLocale: AppLocale.current),
      darkTheme: buildDarkTheme(glyphLocale: AppLocale.current),
      themeMode: settings.themeMode,
      home: const TavernHomePage(),
    );
  }
}
