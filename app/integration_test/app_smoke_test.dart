// On-device smoke test: the pages a user meets first, driven through the real
// widget tree (no emulator coordinates, no taps through the host OS).
//
//   flutter test integration_test -d <device>
//
// It proves the release-critical surfaces render and respond: the tavern home,
// the 我的 settings page, the DeepSeek key page and the new multi-API page.

import 'package:dsh_app/app.dart';
import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final container = ProviderContainer();
    await container.read(settingsProvider.notifier).ready;
    container.dispose();
  });

  testWidgets('the tavern home, settings and the API pages open', (tester) async {
    AppLocale.use(AppLocale.zhCN);
    await tester.pumpWidget(const ProviderScope(child: TavernLiteApp()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 首页
    expect(find.text('酒馆'), findsWidgets);
    expect(find.text('书架'), findsOneWidget);
    expect(find.text('对话'), findsOneWidget);
    expect(find.text('资源库'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    // 我的 = 酒馆设置
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('模型'), findsOneWidget);
    expect(find.text('思考'), findsOneWidget);
    expect(find.text('DeepSeek API Key'), findsOneWidget);
    expect(find.text('上下文上限'), findsOneWidget);
    expect(find.text('温度'), findsOneWidget);

    // API Key 页
    await tester.tap(find.text('DeepSeek API Key'));
    await tester.pumpAndSettle();
    expect(find.text('DeepSeek 官方'), findsOneWidget);
    expect(find.text('打开 API 配置'), findsOneWidget);

    // 新的多 API 页
    await tester.tap(find.text('打开 API 配置'));
    await tester.pumpAndSettle();
    expect(find.text('API 配置'), findsWidgets);
    expect(find.text('新增'), findsOneWidget);
    expect(find.text('自定义 API（OpenAI 兼容）'), findsOneWidget);

    // 新增一张配置：编辑器打开，字段齐全
    await tester.tap(find.text('新增'));
    await tester.pumpAndSettle();
    expect(find.text('名称'), findsOneWidget);
    expect(find.text('模型'), findsWidgets);
    expect(find.text('用 SSE 流式返回'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
  });
}
