// 「现在能不能说话」：官方 Key 或当前激活的自定义 API 的 Key，有一个就算有。
//
// 聊天页原来只看 Official 那一个 Key，配了中转仍然被拦在「先填 API Key」；
// 这里把它统一成一处判断，页面只读这个 provider。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_profiles.dart';
import 'settings_state.dart';

/// True when the active endpoint has a key.
final modelAccessProvider = Provider<bool>((ref) {
  final official = ref.watch(settingsProvider.select((s) => s.apiKey));
  final profiles = ref.watch(apiProfilesProvider);
  return profiles.hasKeyFor(official);
});
