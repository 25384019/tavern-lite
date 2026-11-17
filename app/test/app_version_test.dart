// 版本号必须和 pubspec.yaml 对得上：改了 pubspec 忘了改 app_version.dart，
// 用户看到的版本就是假的。
//
//   flutter test test/app_version_test.dart

import 'dart:io';

import 'package:dsh_app/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app_version.dart 和 pubspec.yaml 一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*([0-9.]+)\+?([0-9]*)\s*$', multiLine: true)
        .firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml 里找不到 version:');
    final version = match!.group(1)!;
    final build = match.group(2) ?? '';
    expect(appVersion, version);
    expect(appBuildNumber, build.isEmpty ? '0' : build);
  });

  test('显示用的字符串是「版本 (构建)」', () {
    expect(appVersionLabel, '$appVersion ($appBuildNumber)');
    expect(appVersionLabel, matches(r'^\d+\.\d+\.\d+ \(\d+\)$'));
  });
}
