/// 应用版本号，显示在「我的 › 关于」里。
///
/// 必须和 `pubspec.yaml` 的 `version:` 一致——`test/app_version_test.dart`
/// 会读 pubspec 来盯着，改了那边忘了这边，测试就会红。
library;

const appVersion = '1.0.16';

/// `version: 1.0.16+1` 里 `+` 后面那个。
const appBuildNumber = '1';

/// 例如 `1.0.16 (1)`。
const appVersionLabel = '$appVersion ($appBuildNumber)';
