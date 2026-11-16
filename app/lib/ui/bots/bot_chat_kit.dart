// Tavern Lite: the chat page's frame and header, lifted from the original
// `ui/bots/bot_chat_kit.dart` (only `BotChatFrame` and `BotChatHeader`; the
// transcript rows there belong to DSH's bot chat and are not used here).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../common/side_insets.dart';
import '../common/smooth_size.dart';
import '../common/status_dot.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';

class BotChatHeader extends StatelessWidget {
  const BotChatHeader({
    super.key,
    required this.face,
    required this.title,
    required this.status,
    required this.tone,
    required this.onDetails,
    this.scrolledUnder,
    this.action,
  });

  final Widget face;
  final String title;
  final String status;
  final StatusTone tone;
  final VoidCallback onDetails;
  final ValueNotifier<double>? scrolledUnder;

  /// The round key on the right, in place of ⓘ (which repeats the title's
  /// tap): its icon, label and what it does.
  final (IconData, String, VoidCallback)? action;

  static const barHeight = 56.0;
  static const key44 = 44.0;
  static const faceSize = 32.0;

  static double barHeightOf(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final small = Theme.of(context).textTheme.labelSmall!.fontSize!;
    return math.max(barHeight, scaler.scale(15) * 1.3 + scaler.scale(small) * 1.25 + 12);
  }

  static double heightOf(BuildContext context) => MediaQuery.paddingOf(context).top + barHeightOf(context) + 8;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final faceInset = (key44 - faceSize) / 2;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (scrolledUnder case final scrolled?)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: scrolled,
              builder: (context, t, child) => Opacity(opacity: t, child: child),
              child: TopFade(height: top + barHeightOf(context) + 12),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(12, top, 12, 0),
          child: BackdropGroup(
            child: SizedBox(
              height: barHeightOf(context),
              child: Row(
                children: [
                  _RoundKey(
                    key: const ValueKey('bot-back'),
                    icon: AppIcons.back,
                    tooltip: l10n.commonBack,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                        button: true,
                        hint: l10n.botsViewDetails,
                        child: GlassSurface(
                          key: const ValueKey('bot-title'),
                          tier: GlassTier.chrome,
                          stadium: true,
                          grouped: true,
                          onTap: onDetails,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: key44),
                            child: Padding(
                              padding: EdgeInsets.only(left: faceInset, right: 16),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox.square(key: const ValueKey('bot-face'), dimension: faceSize, child: face),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: SmoothSize(
                                      duration: AppMotion.of(context, AppMotion.standard),
                                      curve: AppMotion.std,
                                      alignment: Alignment.centerLeft,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleSmall?.copyWith(fontSize: 15, height: 1.3),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              StatusDot(tone: tone, size: 6),
                                              const SizedBox(width: 5),
                                              Flexible(
                                                child: Text(
                                                  status,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: theme.textTheme.labelSmall?.copyWith(
                                                    color: tone == StatusTone.warn ? dsh.warning : dsh.textTertiary,
                                                    height: 1.25,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (action case (final icon, final label, final onTap))
                    _RoundKey(key: const ValueKey('bot-action'), icon: icon, tooltip: label, onTap: onTap)
                  else
                    _RoundKey(
                      key: const ValueKey('bot-details'),
                      icon: AppIcons.info,
                      tooltip: l10n.commonDetails,
                      onTap: onDetails,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundKey extends StatelessWidget {
  const _RoundKey({super.key, required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    child: SizedBox.square(
      dimension: BotChatHeader.key44,
      child: GlassSurface(
        tier: GlassTier.chrome,
        circle: true,
        grouped: true,
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Center(child: Icon(icon, size: 22, color: Theme.of(context).colorScheme.onSurface)),
        ),
      ),
    ),
  );
}

/// The page: the transcript fills the space between the header (floating over
/// it) and the bottom column (cards, error, composer).
class BotChatFrame extends StatelessWidget {
  const BotChatFrame({
    super.key,
    required this.header,
    required this.body,
    required this.bottom,
    this.backdrop,
    this.endDrawer,
    this.scaffoldKey,
  });

  final Widget header;
  final Widget body;
  final List<Widget> bottom;

  /// What the page stands on, around [child]; null: the usual gradient.
  final Widget Function(Widget child)? backdrop;

  /// A panel that slides in from the right edge (opened through [scaffoldKey]).
  final Widget? endDrawer;
  final GlobalKey<ScaffoldState>? scaffoldKey;

  @override
  Widget build(BuildContext context) {
    final backdrop = this.backdrop ?? (child) => AppBackdrop(child: child);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dshSystemOverlay(Theme.of(context).brightness),
      child: backdrop(
        Scaffold(
          key: scaffoldKey,
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: true,
          endDrawer: endDrawer,
          body: SideSafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: body),
                      Positioned(left: 0, right: 0, top: 0, child: header),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: AppSpace.floatingWidth),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: bottom,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
