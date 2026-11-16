// The other transport path: a profile that is NOT DeepSeek's dialect.
//
//   flutter test integration_test/live_custom_api_test.dart -d <device> \
//     --dart-define=TAVERN_TEST_KEY=sk-... \
//     --dart-define=TAVERN_TEST_BASE=https://api.deepseek.com \
//     --dart-define=TAVERN_TEST_MODEL=deepseek-flash
//
// `deepseek: false` is what every saved OpenAI-compatible profile uses: no
// `/beta` prefix, no `thinking` field. `stream: false` exercises the
// non-streamed branch of the model client. A key from the same account is used
// here only because it is the one endpoint we can reach; what is under test is
// the custom-profile path, not DeepSeek.

import 'dart:convert';

import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _key = String.fromEnvironment('TAVERN_TEST_KEY');
const _base = String.fromEnvironment('TAVERN_TEST_BASE', defaultValue: 'https://api.deepseek.com');
const _model = String.fromEnvironment('TAVERN_TEST_MODEL', defaultValue: 'deepseek-flash');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a reply through an OpenAI-compatible profile, non-streamed', (tester) async {
    if (_key.isEmpty) {
      markTestSkipped('TAVERN_TEST_KEY is not set');
      return;
    }
    final dir = await getApplicationSupportDirectory();
    final root = '${dir.path}/tavern-custom-${DateTime.now().millisecondsSinceEpoch}';
    final tavern = await openTavern(root);
    addTearDown(tavern.close);

    // Exactly what app/lib/tavern/tavern_provider.dart builds for a saved
    // custom profile.
    tavern.configure(
      TavernModelConfig(apiKey: () async => _key, baseUrl: _base, model: _model, deepseek: false, stream: false),
    );

    final bytes = await rootBundle.load('assets/tavern/sample_innkeeper.json');
    final character = await tavern.importCard(bytes.buffer.asUint8List(), fileName: 'sample_innkeeper.json');
    final chatId = await tavern.createChat(character.id);

    TavernTurnDone? done;
    TavernTurnFailed? failed;
    final replyText = StringBuffer();
    await for (final event in tavern.send(chatId, '你好，用一句话回应我。').timeout(const Duration(minutes: 3))) {
      switch (event) {
        case TavernTextDelta(text: final delta):
          replyText.write(delta);
        case TavernTurnDone():
          done = event;
        case TavernTurnFailed():
          failed = event;
        default:
          break;
      }
    }
    if (failed != null) fail('turn failed: ${failed.kind.name} ${failed.detail ?? ''}');
    expect(done, isNotNull);
    expect(replyText.toString().trim(), isNotEmpty);
    final usage = done!.message.usage;
    expect(usage, isNotNull);

    // ignore: avoid_print
    print(
      jsonEncode({
        'base': _base,
        'model': _model,
        'deepseek': false,
        'stream': false,
        'chars': replyText.length,
        'promptTokens': usage!.promptTokens,
        'cacheHitTokens': usage.cacheHitTokens,
        'completionTokens': usage.completionTokens,
        'finishReason': done.finishReason,
      }),
    );
  });
}
