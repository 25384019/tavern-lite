// Tavern Lite: colour readability for card UI fragments.
//
// The original lived in `ui/chat/dsh_ui/dsh_ui_plugin_styles_model.dart`, next
// to DSH's whole dsh-ui renderer. The tavern needs one function from it: given
// a colour a card asked for and the background it lands on, the nearest colour
// that keeps a 4.5:1 contrast.

import 'dart:math' as math;

double _channel(int value) {
  final c = (value & 0xFF) / 255.0;
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(int rgb) => 0.2126 * _channel(rgb >> 16) + 0.7152 * _channel(rgb >> 8) + 0.0722 * _channel(rgb);

double _contrast(int a, int b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

int _mix(int a, int b, double t) {
  int part(int shift) {
    final x = (a >> shift) & 0xFF;
    final y = (b >> shift) & 0xFF;
    return (x + (y - x) * t).round().clamp(0, 255);
  }

  return (part(16) << 16) | (part(8) << 8) | part(0);
}

double _distance(int a, int b) {
  final dr = ((a >> 16) & 0xFF) - ((b >> 16) & 0xFF);
  final dg = ((a >> 8) & 0xFF) - ((b >> 8) & 0xFF);
  final db = (a & 0xFF) - (b & 0xFF);
  return (dr * dr + dg * dg + db * db).toDouble();
}

/// [requested] when it already reaches [minimum] against [background];
/// otherwise the closest mix towards black or white that does.
int dshUiReadableColor(int requested, int background, {double minimum = 4.5}) {
  if (_contrast(requested, background) >= minimum) return requested;
  var best = requested;
  var bestDistance = double.infinity;
  for (final target in const [0x000000, 0xFFFFFF]) {
    if (_contrast(target, background) < minimum) continue;
    var low = 0.0;
    var high = 1.0;
    var passing = target;
    for (var step = 0; step < 16; step++) {
      final middle = (low + high) / 2;
      final candidate = _mix(requested, target, middle);
      if (_contrast(candidate, background) >= minimum) {
        high = middle;
        passing = candidate;
      } else {
        low = middle;
      }
    }
    final distance = _distance(passing, requested);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = passing;
    }
  }
  return best;
}
