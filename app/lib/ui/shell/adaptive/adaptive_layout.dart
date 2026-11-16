// Tavern Lite: the one layout fact the sheet code needs.
//
// The original `ui/shell/adaptive/adaptive_layout.dart` sized the whole shell
// for phones, tablets and foldables; only the height below which a sheet must
// not grow is used by `app_sheet.dart`.

import 'package:flutter/widgets.dart';

abstract final class WindowClass {
  /// Below this height a bottom sheet gives up its tall form.
  static const compactHeight = 720.0;

  /// The width from which the shell showed two panes.
  static const wideWidth = 840.0;

  static bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).height < compactHeight;

  static bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wideWidth;
}
