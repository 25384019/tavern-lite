// The app's one [Tavern]: the engine (packages/dsh_tavern) opened on
// `<app support>/tavern`. It opens asynchronously, so the screens get a
// [DeferredTavern] that queues calls until it is ready. It follows 酒馆设置
// and reads the app's DeepSeek key on every call; the key is never stored
// by the engine. Tests swap in the preview stand-in (tavern_preview.dart).

import 'dart:io';

import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_profiles.dart';
import '../state/settings_state.dart';
import 'deferred_tavern.dart';
import 'state_templates.dart';
import 'studio_store.dart';
import 'version_store.dart';
import 'tavern_script_host.dart';
import 'tavern_settings.dart';

/// The model endpoint in use: the built-in DeepSeek official one (the app's
/// DeepSeek key, the model picked in 酒馆设置) or the saved OpenAI-compatible
/// profile the user made active.
TavernModelConfig tavernModelConfigFor(Ref ref) {
  final settings = ref.read(tavernSettingsProvider);
  final profiles = ref.read(apiProfilesProvider);
  final active = profiles.active;
  if (active.isOfficial) {
    return TavernModelConfig(
      apiKey: () async {
        final key = ref.read(settingsProvider).apiKey.trim();
        return key.isEmpty ? null : key;
      },
      model: settings.model,
      thinking: settings.thinking,
    );
  }
  return TavernModelConfig(
    apiKey: () async {
      final key = active.apiKey.trim();
      return key.isEmpty ? null : key;
    },
    baseUrl: active.baseUrl.trim().isEmpty
        ? 'https://api.openai.com/v1'
        : active.baseUrl.trim(),
    model: active.model.trim().isEmpty ? 'gpt-4o-mini' : active.model.trim(),
    deepseek: false,
    thinking: active.thinking,
    stream: active.stream,
  );
}

/// The endpoint in use, as a value: the same sources [tavernProvider] feeds the
/// engine, for the one-off calls that do not go through a chat (AI 制卡).
final tavernModelConfigProvider = Provider<TavernModelConfig>(
  (ref) => tavernModelConfigFor(ref),
);

/// The transport for those one-off calls. A plain [TavernModelClient]: no
/// preset, no history, no engine state — the caller supplies the body. Tests
/// override it to answer without a network.
final tavernModelClientProvider = Provider<TavernModelClient>(
  (ref) => TavernModelClient(),
);

/// 专业草稿的本地存放（还没存成卡的那份）。测试可以换成临时目录。
final studioDraftStoreProvider = FutureProvider<StudioDraftStore>((ref) async {
  final support = await getApplicationSupportDirectory();
  return StudioDraftStore(Directory('${support.path}/studio'));
});

/// 状态模板的存放（资源库 › 状态模板），和工作室草稿分开放。
/// ??????????? / ????????????????
final versionStoreProvider = FutureProvider<VersionStore>((ref) async {
  final support = await getApplicationSupportDirectory();
  return VersionStore(Directory('${support.path}/versions'));
});

final stateTemplateStoreProvider = FutureProvider<StateTemplateStore>((
  ref,
) async {
  final support = await getApplicationSupportDirectory();
  return StateTemplateStore(Directory('${support.path}/state_templates'));
});

final tavernProvider = Provider<Tavern>((ref) {
  final tavern = DeferredTavern(() async {
    final support = await getApplicationSupportDirectory();
    return openTavern('${support.path}/tavern');
  }());
  ref.onDispose(tavern.close);
  void configure() => tavern.configure(tavernModelConfigFor(ref));
  configure();
  ref.listen(tavernSettingsProvider, (_, _) => configure());
  ref.listen(apiProfilesProvider, (_, _) => configure());
  return tavern;
});

/// The app's host for card scripts, one per tavern: what the engine delivers
/// to a canvas page's script context goes to that page.
final tavernScriptPagesProvider = Provider<TavernScriptPages>((ref) {
  ref.watch(tavernProvider);
  return TavernScriptPages();
});

/// Every character, as the library lists them.
final tavernCharactersProvider = StreamProvider<List<TavernCharacter>>(
  (ref) => ref.watch(tavernProvider).watchCharacters(),
);

/// One character in full. The list carries only what a card in the grid
/// shows; greetings, the definition and the creator's notes come from here,
/// read again whenever the list changes (an edit, a re-import).
final tavernCharacterDetailProvider = FutureProvider.autoDispose
    .family<TavernCharacter?, String>((ref, id) {
      ref.watch(tavernCharactersProvider);
      return ref.watch(tavernProvider).character(id);
    });

/// Chats, newest first; one character's when the argument is its id.
final tavernChatsProvider =
    StreamProvider.family<List<TavernChatSummary>, String?>(
      (ref, characterId) =>
          ref.watch(tavernProvider).watchChats(characterId: characterId),
    );

/// Saved personas (人设).
///
/// 预设列表没有在这里另开一份：`ui/tavern/tavern_presets_page.dart` 的
/// `tavernPresetsProvider` 就是它，重名会在别处变成 ambiguous_import。
final tavernPersonasProvider = StreamProvider<List<TavernPersona>>(
  (ref) => ref.watch(tavernProvider).watchPersonas(),
);

/// Who you are in a chat (null: outside any chat, just the default). Read
/// again whenever the personas notify, which default and binding changes do.
final tavernPersonaSelectionProvider =
    FutureProvider.family<PersonaSelection, String?>((ref, chatId) {
      ref.watch(tavernPersonasProvider);
      return ref.watch(tavernProvider).personaSelection(chatId: chatId);
    });
