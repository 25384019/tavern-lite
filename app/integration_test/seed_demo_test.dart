// Puts the app on the device into a usable state: the DeepSeek key in secure
// storage and the sample card in the tavern library, in the same directories the
// app itself uses.
//
//   flutter test integration_test/seed_demo_test.dart -d <device> \
//     --dart-define=TAVERN_TEST_KEY=sk-...
//
// Afterwards the installed app opens on a character and can answer. The key is
// only written to the device's secure storage, never to the repo.

import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_tavern/dsh_tavern.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _key = String.fromEnvironment('TAVERN_TEST_KEY');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seed the key and the sample card', (tester) async {
    if (_key.isEmpty) {
      markTestSkipped('TAVERN_TEST_KEY is not set');
      return;
    }

    // The app's own settings store (Android Keystore-backed entry).
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).setApiKey(_key);
    expect(container.read(settingsProvider).hasApiKey, isTrue);

    // The app's own library: <app support>/tavern.
    final support = await getApplicationSupportDirectory();
    final tavern = await openTavern('${support.path}/tavern');
    addTearDown(tavern.close);

    final existing = await tavern.watchCharacters().first;
    if (!existing.any((c) => c.name.isNotEmpty)) {
      final bytes = await rootBundle.load('assets/tavern/sample_innkeeper.json');
      final character = await tavern.importCard(bytes.buffer.asUint8List(), fileName: 'sample_innkeeper.json');
      // ignore: avoid_print
      print('seeded character: ${character.id}');
    }
    final characters = await tavern.watchCharacters().first;
    expect(characters, isNotEmpty);
  });
}
