// A real turn against the configured provider, on the device, through the real
// engine and transport — no UI, no fake client.
//
//   flutter test integration_test/live_model_test.dart -d <device> \
//     --dart-define=TAVERN_TEST_KEY=sk-... \
//     --dart-define=TAVERN_TEST_MODEL=deepseek-flash
//
// The key comes from the command line and is never written to the repo; with no
// key the test skips itself. Two turns are sent so the second one shows what the
// provider reports for a cached prefix — the number the tavern prints under a
// reply.

import 'dart:convert';

import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _key = String.fromEnvironment('TAVERN_TEST_KEY');
const _model = String.fromEnvironment('TAVERN_TEST_MODEL', defaultValue: 'deepseek-flash');
const _thinking = bool.fromEnvironment('TAVERN_TEST_THINKING');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two real replies from the configured model', (tester) async {
    if (_key.isEmpty) {
      markTestSkipped('TAVERN_TEST_KEY is not set');
      return;
    }
    final dir = await getApplicationSupportDirectory();
    final root = '${dir.path}/tavern-live-${DateTime.now().millisecondsSinceEpoch}';
    final tavern = await openTavern(root);
    addTearDown(tavern.close);

    tavern.configure(TavernModelConfig(apiKey: () async => _key, model: _model, thinking: _thinking));

    final bytes = await rootBundle.load('assets/tavern/sample_innkeeper.json');
    final character = await tavern.importCard(bytes.buffer.asUint8List(), fileName: 'sample_innkeeper.json');
    final chatId = await tavern.createChat(character.id);

    final lines = <Map<String, Object?>>[];
    for (final prompt in ['你好，用一句话回应我。', '再说一句，换个说法。']) {
      final replyText = StringBuffer();
      final reasoningText = StringBuffer();
      TavernTurnDone? done;
      TavernTurnFailed? failed;
      await for (final event in tavern.send(chatId, prompt).timeout(const Duration(minutes: 3))) {
        switch (event) {
          case TavernTextDelta(text: final delta):
            replyText.write(delta);
          case TavernReasoningDelta(text: final delta):
            reasoningText.write(delta);
          case TavernTurnDone():
            done = event;
          case TavernTurnFailed():
            failed = event;
          default:
            break;
        }
      }
      if (failed != null) fail('turn failed: ${failed.kind.name} ${failed.detail ?? ''}');
      expect(done, isNotNull, reason: 'no TavernTurnDone');
      final reply = done!.message;
      expect(reply.text.trim(), isNotEmpty, reason: 'empty reply');
      final usage = reply.usage;
      expect(usage, isNotNull, reason: 'the provider reported no usage');
      expect(usage!.promptTokens, greaterThan(0));
      expect(usage.completionTokens, greaterThan(0));
      lines.add({
        'model': _model,
        'thinking': _thinking,
        'chars': reply.text.length,
        'reasoningChars': reasoningText.length,
        'promptTokens': usage.promptTokens,
        'cacheHitTokens': usage.cacheHitTokens,
        'completionTokens': usage.completionTokens,
        'finishReason': done.finishReason,
      });
    }

    final path = await tavern.path(chatId);
    expect(path.where((m) => m.role == TavernRole.character).length, greaterThanOrEqualTo(2));

    // ignore: avoid_print
    print(jsonEncode(lines));
  });
}
