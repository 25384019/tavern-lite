// Tavern Lite: app settings, trimmed to what the tavern needs.
//
// The original file also carried DSH-only switches (local engine auto-start,
// phone storage, web layout). They are gone with the engine; what remains is
// the DeepSeek key, the theme, and the composer's Enter behaviour.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  const AppSettings({this.apiKey = '', this.themeMode = ThemeMode.system, this.hardwareEnterSends = false, this.loaded = false});

  /// The DeepSeek official API key. Custom OpenAI-compatible profiles keep
  /// theirs through `lib/api/api_profiles.dart`.
  final String apiKey;
  final ThemeMode themeMode;

  /// Hardware Enter sends; Shift+Enter and the software keyboard still insert
  /// newlines.
  final bool hardwareEnterSends;

  /// True once the stored values have been read.
  final bool loaded;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  AppSettings copyWith({String? apiKey, ThemeMode? themeMode, bool? hardwareEnterSends, bool? loaded}) => AppSettings(
    apiKey: apiKey ?? this.apiKey,
    themeMode: themeMode ?? this.themeMode,
    hardwareEnterSends: hardwareEnterSends ?? this.hardwareEnterSends,
    loaded: loaded ?? this.loaded,
  );
}

class SettingsController extends Notifier<AppSettings> {
  static const _apiKeyKey = 'deepseek_api_key';
  static const _themeKey = 'theme_mode';
  static const _hardwareEnterKey = 'hardware_enter_sends';
  static const _secure = FlutterSecureStorage();

  /// Resolves when the first read finishes; `main()` awaits it so the first
  /// frame already knows whether a key exists.
  late Future<void> ready;

  @override
  AppSettings build() {
    ready = _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    String apiKey = '';
    try {
      apiKey = (await _secure.read(key: _apiKeyKey))?.trim() ?? '';
    } catch (_) {
      // A locked or reset keystore must not stop the app: the tavern only
      // needs the key when a turn is sent, and the settings page can set it
      // again.
      apiKey = '';
    }
    final mode = ThemeMode.values.where((m) => m.name == prefs.getString(_themeKey)).firstOrNull ?? ThemeMode.system;
    if (!ref.mounted) return;
    state = AppSettings(
      apiKey: apiKey,
      themeMode: mode,
      hardwareEnterSends: prefs.getBool(_hardwareEnterKey) ?? false,
      loaded: true,
    );
  }

  Future<void> setApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await _secure.delete(key: _apiKeyKey);
    } else {
      await _secure.write(key: _apiKeyKey, value: trimmed);
    }
    state = state.copyWith(apiKey: trimmed);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setHardwareEnterSends(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hardwareEnterKey, value);
    state = state.copyWith(hardwareEnterSends: value);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
