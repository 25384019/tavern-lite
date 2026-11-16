// Tavern Lite: the story's composer — a glass pill with the persona key on the
// left, the line in the middle, 帮我写 / 接着写 (accessory) and send on the right,
// and the quick-reply tray above it.
//
// The original (`ui/chat/composer.dart`, 941 lines) carried attachments, voice
// dictation, model and pet keys, and DSH session plumbing. Those are not part of
// this app; the shape, the keys and the Enter behaviour are.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    this.footer,
    this.keyboardInset = 0,
    required this.controller,
    required this.connected,
    required this.running,
    required this.onSend,
    required this.onStop,
    this.focusNode,
    this.accessory,
    this.leading,
    this.tray,
    this.onSendOptions,
    this.placeholder,
    this.hardwareEnterSends = false,
    this.sendWhenEmpty = false,
    this.emptySendLabel,
    this.maxLines = 6,
    this.voice,
  });

  /// Under the pill (attachments, hints).
  final Widget? footer;
  final double keyboardInset;
  final TextEditingController controller;
  final FocusNode? focusNode;

  /// A model is set up: with none, a line can be typed but not sent.
  final bool connected;
  final bool running;
  final VoidCallback onSend;
  final VoidCallback onStop;

  /// The round key on the right while the box is empty (帮我写 / 接着写).
  final Widget? accessory;

  /// The round key on the left (人设).
  final Widget? leading;

  /// The row above the pill (quick replies, slash commands).
  final Widget? tray;

  /// Long-press on send: another way to send the line.
  final VoidCallback? onSendOptions;

  final String? placeholder;
  final bool hardwareEnterSends;

  /// With nothing written, send still means something: the character speaks
  /// next.
  final bool sendWhenEmpty;

  /// The accessibility label of that empty send.
  final String? emptySendLabel;
  final int maxLines;

  /// Kept for the call sites that still pass one; unused here.
  final Object? voice;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() => setState(() {});

  bool get _canSend => widget.running || widget.controller.text.trim().isNotEmpty || widget.sendWhenEmpty;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (keyboard.isShiftPressed) return KeyEventResult.ignored;
      if (widget.hardwareEnterSends || !keyboard.isControlPressed) {
        if (_canSend) widget.onSend();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final empty = widget.controller.text.trim().isEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.tray case final tray?) tray,
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: GlassSurface(
            tier: GlassTier.card,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.leading case final leading?) ...[leading, const SizedBox(width: 2)],
                  Expanded(
                    child: Focus(
                      onKeyEvent: _onKey,
                      child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        minLines: 1,
                        maxLines: widget.maxLines,
                        textInputAction: widget.hardwareEnterSends ? TextInputAction.send : TextInputAction.newline,
                        onSubmitted: widget.hardwareEnterSends ? (_) => widget.onSend() : null,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: widget.placeholder,
                          hintStyle: theme.textTheme.bodyLarge?.copyWith(color: dsh.textTertiary),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  if (empty && !widget.running && widget.accessory != null) ...[
                    widget.accessory!,
                    const SizedBox(width: 2),
                  ],
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2, right: 2),
                    child: _SendKey(
                      running: widget.running,
                      enabled: _canSend,
                      emptySendLabel: widget.emptySendLabel,
                      onSend: widget.onSend,
                      onStop: widget.onStop,
                      onLongPress: widget.onSendOptions,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.footer case final footer?) footer,
      ],
    );
  }
}

class _SendKey extends StatelessWidget {
  const _SendKey({
    required this.running,
    required this.enabled,
    required this.onSend,
    required this.onStop,
    this.emptySendLabel,
    this.onLongPress,
  });

  final bool running;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final String? emptySendLabel;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = running ? theme.colorScheme.error : theme.colorScheme.primary;
    final label = running ? context.l10n.commonStop : (emptySendLabel ?? context.l10n.commonSend);
    return Semantics(
      button: true,
      enabled: running || enabled,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          onLongPress: running ? null : onLongPress,
          child: InkResponse(
            onTap: running ? onStop : (enabled ? onSend : null),
            radius: 24,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (running || enabled) ? color.withValues(alpha: 0.14) : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                running ? AppIcons.stop : AppIcons.send,
                size: 22,
                color: (running || enabled) ? color : DshColors.of(context).textDisabled,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
