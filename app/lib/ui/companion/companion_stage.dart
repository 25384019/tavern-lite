// Tavern Lite: the visual novel's Live2D stage, reduced to its interface.
//
// The original drove DSH's companion Live2D runtime (a downloaded WebGL page
// with a model pack). This app ships no Live2D runtime, so the controller and
// the event bridge keep their surface and do nothing: the story falls back to
// the card's sprites, which are part of the card itself.

import 'dart:async';

import 'package:flutter/material.dart';

/// Commands the story sends to the model (mood, mouth, motion).
class CompanionStageController {
  void command(String type, Map<String, Object?> args) {}
}

/// What the stage tells the page back.
class CompanionStageEvents {
  CompanionStageEvents({
    this.onReady,
    this.onFailed,
    this.onTouch,
    this.onWake,
    this.onMood,
    this.onObject,
    this.onActivity,
  });

  final void Function()? onReady;
  final void Function(String why)? onFailed;
  final void Function(Object? x, Object? y)? onTouch;
  final void Function()? onWake;
  final void Function(Object? mood)? onMood;
  final void Function(Object? object)? onObject;
  final void Function(Object? activity)? onActivity;
}

/// Draws nothing: there is no model to draw.
class CompanionStage extends StatelessWidget {
  const CompanionStage({
    super.key,
    this.store,
    this.controller,
    this.events,
    this.bare = false,
  });

  final Object? store;
  final CompanionStageController? controller;
  final CompanionStageEvents? events;
  final bool bare;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Kept for callers that wait for a stage to settle.
Future<void> companionStageSettled() async {}
