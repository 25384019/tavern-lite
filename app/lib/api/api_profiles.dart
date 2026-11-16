// 多 API 配置: the DeepSeek official endpoint plus any number of saved
// OpenAI-compatible endpoints, one of them active.
//
// The engine already speaks OpenAI Chat Completions: `TavernModelConfig` takes
// a base URL, a model name, its own key callback and a `deepseek` flag that
// only decides the `/beta` prefix and ST's DeepSeek post-processing. What the
// original app never had was a place to keep more than one of them: the model
// came from `tavern_settings.dart` and the key from one secure-storage slot.
// This file adds that store; `tavern_provider.dart` reads the active profile
// on every configuration change.
//
// Keys live in the Android Keystore-backed secure storage, one slot per
// profile, never in SharedPreferences and never in the exported JSON.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which wire dialect a profile speaks.
enum ApiKind {
  /// `https://api.deepseek.com`, `/beta` continuation, ST's DeepSeek
  /// post-processing, `thinking` field.
  deepseek,

  /// A plain OpenAI-compatible `/v1` (or any prefix) `chat/completions`.
  openai,
}

class ApiProfile {
  const ApiProfile({
    required this.id,
    required this.name,
    this.kind = ApiKind.openai,
    this.baseUrl = '',
    this.model = '',
    this.apiKey = '',
    this.thinking = false,
    this.stream = true,
    this.vision = false,
    this.contextWindow,
    this.maxOutput,
  });

  /// `deepseek` is reserved for the built-in official endpoint.
  final String id;
  final String name;
  final ApiKind kind;

  /// Root URL, with or without `/v1`; a full `.../chat/completions` is
  /// accepted too (the engine's `TavernModelConfig.endpoint` handles both).
  final String baseUrl;
  final String model;

  /// Held in memory only; the durable copy is [ApiProfileStore]'s secure
  /// storage slot. Never written to preferences or logs.
  final String apiKey;

  /// DeepSeek's thinking toggle (ignored by plain OpenAI endpoints).
  final bool thinking;

  /// Ask for a server-sent-event stream. Off: one non-streamed completion.
  final bool stream;

  /// What the chosen model said about itself when it was picked from the
  /// upstream catalogue: takes images, how much context, how much output.
  final bool vision;
  final int? contextWindow;
  final int? maxOutput;

  bool get isOfficial => id == officialId;

  ApiProfile copyWith({
    String? name,
    ApiKind? kind,
    String? baseUrl,
    String? model,
    String? apiKey,
    bool? thinking,
    bool? stream,
    bool? vision,
    int? contextWindow,
    int? maxOutput,
  }) => ApiProfile(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    apiKey: apiKey ?? this.apiKey,
    thinking: thinking ?? this.thinking,
    stream: stream ?? this.stream,
    vision: vision ?? this.vision,
    contextWindow: contextWindow ?? this.contextWindow,
    maxOutput: maxOutput ?? this.maxOutput,
  );

  /// Everything except the key: what SharedPreferences may hold.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'baseUrl': baseUrl,
    'model': model,
    'thinking': thinking,
    'stream': stream,
    'vision': vision,
    'contextWindow': contextWindow,
    'maxOutput': maxOutput,
  };

  static ApiProfile fromJson(Map<String, Object?> json) => ApiProfile(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    kind: ApiKind.values.where((k) => k.name == json['kind']).firstOrNull ?? ApiKind.openai,
    baseUrl: json['baseUrl'] as String? ?? '',
    model: json['model'] as String? ?? '',
    thinking: json['thinking'] as bool? ?? false,
    stream: json['stream'] as bool? ?? true,
    vision: json['vision'] as bool? ?? false,
    contextWindow: (json['contextWindow'] as num?)?.toInt(),
    maxOutput: (json['maxOutput'] as num?)?.toInt(),
  );

  /// The built-in official endpoint. Its key is the app's DeepSeek key
  /// (`settings_state.dart`), so existing installs keep working untouched.
  static const officialId = 'deepseek';

  static const official = ApiProfile(
    id: officialId,
    name: 'DeepSeek 官方',
    kind: ApiKind.deepseek,
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-flash',
  );

  /// Common presets offered by the editor; a value the user typed is never
  /// replaced by these.
  static const suggestions = <String>[
    'https://api.openai.com/v1',
    'https://api.deepseek.com/v1',
    'https://openrouter.ai/api/v1',
    'https://api.siliconflow.cn/v1',
    'https://api.moonshot.cn/v1',
    'http://10.0.2.2:11434/v1',
    'http://192.168.1.2:1234/v1',
  ];
}

class ApiProfilesState {
  const ApiProfilesState({this.custom = const [], this.activeId = ApiProfile.officialId, this.loaded = false});

  /// Saved non-official profiles, in the order the user added them.
  final List<ApiProfile> custom;

  /// [ApiProfile.officialId] or the id of one of [custom].
  final String activeId;
  final bool loaded;

  /// The profile in use; the official one when the active id went missing.
  ApiProfile get active => custom.where((p) => p.id == activeId).firstOrNull ?? ApiProfile.official;

  bool get usesOfficial => active.isOfficial;

  /// If a key is configured for the active profile: the official one reads
  /// `AppSettings.apiKey`, a custom one carries its own.
  bool hasKeyFor(String officialKey) => usesOfficial ? officialKey.trim().isNotEmpty : active.apiKey.trim().isNotEmpty;

  ApiProfilesState copyWith({List<ApiProfile>? custom, String? activeId, bool? loaded}) => ApiProfilesState(
    custom: custom ?? this.custom,
    activeId: activeId ?? this.activeId,
    loaded: loaded ?? this.loaded,
  );
}

/// Where profile metadata and keys are kept.
class ApiProfileStore {
  static const _listKey = 'api_profiles_v1';
  static const _activeKey = 'api_profile_active_v1';
  static const _keyPrefix = 'api_profile_key_';

  const ApiProfileStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  Future<(List<ApiProfile>, String)> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_listKey);
    final active = prefs.getString(_activeKey) ?? ApiProfile.officialId;
    if (raw == null || raw.isEmpty) return (const <ApiProfile>[], active);
    List<ApiProfile> list;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return (const <ApiProfile>[], active);
      list = [
        for (final item in decoded)
          if (item is Map<String, Object?>) ApiProfile.fromJson(item),
      ];
    } on FormatException {
      // A half-written or hand-edited file must not stop launch.
      return (const <ApiProfile>[], active);
    }
    final withKeys = <ApiProfile>[];
    for (final profile in list) {
      withKeys.add(profile.copyWith(apiKey: await readKey(profile.id)));
    }
    return (withKeys, active);
  }

  Future<String> readKey(String id) async {
    try {
      return (await _storage.read(key: '$_keyPrefix$id'))?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> writeKey(String id, String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: '$_keyPrefix$id');
    } else {
      await _storage.write(key: '$_keyPrefix$id', value: trimmed);
    }
  }

  Future<void> write(List<ApiProfile> profiles, String activeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_listKey, jsonEncode([for (final p in profiles) p.toJson()]));
    await prefs.setString(_activeKey, activeId);
  }

  Future<void> deleteKey(String id) => _storage.delete(key: '$_keyPrefix$id');
}

class ApiProfilesController extends Notifier<ApiProfilesState> {
  final ApiProfileStore _store = const ApiProfileStore();

  /// Resolves when the first read finishes.
  late Future<void> ready;

  @override
  ApiProfilesState build() {
    ready = _load();
    return const ApiProfilesState();
  }

  Future<void> _load() async {
    final (profiles, active) = await _store.read();
    if (!ref.mounted) return;
    final known = profiles.any((p) => p.id == active);
    state = ApiProfilesState(custom: profiles, activeId: known ? active : ApiProfile.officialId, loaded: true);
  }

  Future<void> upsert(ApiProfile profile) async {
    final rest = state.custom.where((p) => p.id != profile.id).toList();
    final next = [...rest, profile];
    await _store.writeKey(profile.id, profile.apiKey);
    final keyless = [for (final p in next) p.copyWith(apiKey: '')];
    await _store.write(keyless, state.activeId);
    state = state.copyWith(custom: next);
  }

  Future<void> remove(String id) async {
    if (id == ApiProfile.officialId) return;
    final next = state.custom.where((p) => p.id != id).toList();
    await _store.deleteKey(id);
    final active = state.activeId == id ? ApiProfile.officialId : state.activeId;
    await _store.write([for (final p in next) p.copyWith(apiKey: '')], active);
    state = state.copyWith(custom: next, activeId: active);
  }

  Future<void> setActive(String id) async {
    if (id != ApiProfile.officialId && !state.custom.any((p) => p.id == id)) return;
    await _store.write([for (final p in state.custom) p.copyWith(apiKey: '')], id);
    state = state.copyWith(activeId: id);
  }

  /// A new id for a profile the user is adding.
  static String newId() => 'p${DateTime.now().microsecondsSinceEpoch}';
}

final apiProfilesProvider = NotifierProvider<ApiProfilesController, ApiProfilesState>(ApiProfilesController.new);
