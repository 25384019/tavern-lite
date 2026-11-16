// Tavern Lite: where a character's Live2D model would live.
//
// The original stored a model pack per character under `<support>/tavern/live2d`
// and borrowed the companion room's runtime to draw it. This app ships no
// Live2D runtime, so the provider always answers "none" and the story keeps the
// card's sprites; the folder is still the one the original used, so a data
// directory carried over from DSH Go loses nothing.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final tavernLive2dRootProvider = Provider<Future<Directory> Function()>(
  (ref) => () async => Directory('${(await getApplicationSupportDirectory()).path}/tavern/live2d'),
);

/// The character's installed pack; null for none.
final tavernLive2dProvider = FutureProvider.autoDispose.family<Object?, String>((ref, characterId) async => null);

/// Lets a deleted character's model go.
Future<void> forgetTavernLive2d(Future<Directory> Function() root, String characterId) async {
  try {
    final dir = Directory('${(await root()).path}/$characterId');
    if (dir.existsSync()) await dir.delete(recursive: true);
  } on Object {
    // Nothing there, or no storage: nothing to let go.
  }
}

/// What the stage would do for one page of the story. The commands reach a
/// stage this app does not draw, but the cue list is still what the original
/// sent, so a later runtime can pick it up unchanged.
List<(String, Map<String, Object?>)> tavernStageCues({required bool you, required String text, String? marker}) {
  if (you) return const [('mood', {'mood': 'listening'})];
  return [
    const ('mood', {'mood': 'idle'}),
    ('say', {'chars': text.runes.length}),
    if ((marker == null
                ? null
                : (_emotionWords.containsKey(marker.toLowerCase()) ? marker.toLowerCase() : tavernEmotionIn(marker))) ??
            tavernEmotionIn(text)
        case final emotion?)
      ('emotion', {'name': emotion}),
  ];
}

/// The feeling a paragraph names first, as one of the stage's emotions; null
/// when it names none. Words for a cold or bitter smile don't count as happy.
String? tavernEmotionIn(String text) {
  final plain = text.replaceAll(RegExp('冷笑|嘲笑|苦笑|讥笑|干笑|皮笑肉不笑|sneer', caseSensitive: false), '');
  int? first;
  String? found;
  for (final MapEntry(key: emotion, value: words) in _emotionWords.entries) {
    final at = RegExp(words, caseSensitive: false).firstMatch(plain)?.start;
    if (at != null && (first == null || at < first)) {
      first = at;
      found = emotion;
    }
  }
  return found;
}

const _emotionWords = {
  'happy': r'笑|开心|高兴|欢喜|雀跃|\bsmil|\blaugh|\bgrin|\bgiggl',
  'shy': r'害羞|脸红|羞|腼腆|羞涩|\bblush',
  'surprised': r'惊讶|吃惊|愣|一惊|震惊|\bgasp|\bsurprised|\bstartled',
  'angry': r'生气|愤怒|怒|恼火|瞪|\bangry|\bglare',
  'sad': r'悲|难过|伤心|泪|哭泣|\bcr(y|ies|ied)\b|\btears|\bsob',
  'worried': r'担心|紧张|忧虑|不安|\bworr|\bnervous|\banxious',
  'confused': r'疑惑|困惑|皱眉|迷茫|\bconfus|\bpuzzl|\bfrown',
};
