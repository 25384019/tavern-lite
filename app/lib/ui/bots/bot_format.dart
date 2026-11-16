// Tavern Lite: the one time formatter the tavern used from the bots pages.
// The rest of `ui/bots` (bots, rooms, memory cards) belongs to DSH's chat and
// is not part of this app.

import '../../l10n/l10n.dart';

/// 「刚刚」「14:05」「昨天」「10月3日」.
String shortTime(DateTime? time, {DateTime? now}) {
  if (time == null) return '';
  final at = now ?? DateTime.now();
  final diff = at.difference(time);
  if (diff.inSeconds.abs() < 60) return appL10n.botsJustNow;
  final today = DateTime(at.year, at.month, at.day);
  final day = DateTime(time.year, time.month, time.day);
  final hm = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  if (day == today) return hm;
  if (day == today.subtract(const Duration(days: 1))) return appL10n.commonYesterday;
  if (time.year == at.year) return appL10n.monthDay(time);
  return '${time.year}/${time.month}/${time.day}';
}
