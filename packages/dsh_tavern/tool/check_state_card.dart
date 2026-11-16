// 验证一张卡的状态定义能不能被引擎接受、能不能落到聊天里。
//
//   dart run tool/check_state_card.dart <card.json>
//
// 打印：导入结果、状态定义是否可执行、初始化值、以及一次 setStateValue 的结果。

import 'dart:convert';
import 'dart:io';

import 'package:dsh_tavern/dsh_tavern.dart';

Future<void> main(List<String> args) async {
  final path = args.isEmpty ? 'E:/dshgo/state-test.json' : args.first;
  final dir = Directory.systemTemp.createTempSync('state-card');
  final tavern = await openTavern(dir.path);
  try {
    final bytes = File(path).readAsBytesSync();
    final character = await tavern.importCard(bytes, fileName: path.split(Platform.pathSeparator).last);
    print('imported: ${character.id} / ${character.name}');

    final chatId = await tavern.createChat(character.id);
    final before = await tavern.readState(chatId);
    print('legacy=${before.legacy} initialized=${before.initialized} '
        'valueExists=${before.valueExists} schema=${before.schema != null}');
    print('values=${jsonEncode(before.values)}');
    print('issues=${jsonEncode(before.issues)}');

    final edit = await tavern.setStateValue(chatId, '/affection', 35);
    print('edit applied=${edit.applied} changed=${edit.changed} issues=${jsonEncode(edit.issues)}');
    final after = await tavern.readState(chatId);
    print('after=${jsonEncode(after.values)}');
    print('changes=${jsonEncode(after.changes)}');
  } finally {
    await tavern.close();
  }
}
