// Tavern Lite: the app's mode key, reduced to the one mode this app has.
//
// DSH Go switched between 对话 (DSH chat), 酒馆 and 伙伴; the tavern's home and
// settings carry the key and a 启动 group that opened the switch sheet. With a
// single mode the key stays where it was, and the sheet explains itself.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../common/app_sheet.dart';
import '../common/sheet_title_bar.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';

enum AppMode { tavern }

class AppModeState {
  const AppModeState({this.startup = AppMode.tavern});

  /// Which mode the app opens in.
  final AppMode startup;
}

class AppModeController extends Notifier<AppModeState> {
  @override
  AppModeState build() => const AppModeState();
}

final appModeProvider = NotifierProvider<AppModeController, AppModeState>(AppModeController.new);

String appModeShortLabel(L10n l10n, AppMode mode) => l10n.tavernTitle;

/// The round key in the tavern home's header.
class ModeKey extends StatelessWidget {
  const ModeKey({super.key, required this.current, this.size = 44, this.tier = GlassTier.chrome});

  final AppMode current;
  final double size;
  final GlassTier tier;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: GlassSurface(
      tier: tier,
      circle: true,
      onTap: () => showModeSheet(context, current: current),
      child: const Center(child: Icon(AppIcons.tavern, size: 22)),
    ),
  );
}

/// Explains that this app is the tavern and nothing else.
Future<void> showModeSheet(BuildContext context, {required AppMode current}) => showAppSheet<void>(
  context,
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitleBar(appModeShortLabel(context.l10n, current)),
          const SizedBox(height: 12),
          Text(
            AppLocale.isEnglish
                ? 'This app is the tavern only: no DSH engine, no terminal, no companion room.'
                : '\u8fd9\u4e2a\u5e94\u7528\u53ea\u6709\u9152\u9986\uff1a\u6ca1\u6709 DSH \u5f15\u64ce\u3001\u7ec8\u7aef\uff0c\u4e5f\u6ca1\u6709\u4f34\u4fa3\u5c0f\u5c4b\u3002',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.l10n.commonDone)),
        ],
      ),
    ),
  ),
);
