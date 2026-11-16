# 构建

## 一、工具链（本机实测）

| 项 | 值 | 来源 |
|---|---|---|
| Flutter | **3.50.0 stable** | `flutter --version`：Flutter 3.50.0 / Dart 3.14.0 |
| Dart | 3.14.0 | 同上；`app/pubspec.yaml` 要求 `sdk: ^3.13.5` |
| JDK | 17.0.6 | `flutter build` 用 `JAVA_HOME`；AGP 要求 17+ |
| Android SDK | platforms;android-36，build-tools;36.0.0 | `%LOCALAPPDATA%\Android\Sdk` |
| NDK | 28.2.13676358 | 与 Flutter 3.50 默认 `flutter.ndkVersion` 一致 |
| Gradle | 9.5.0（wrapper） | Flutter 3.50 模板；本项目改用 `gradle-9.5.0-bin.zip` 复用本机缓存 |
| AGP / Kotlin | 9.3.1 / 2.4.20 | 同上模板 |
| minSdk / targetSdk / compileSdk | 26 / 36 / 36 | `app/android/app/build.gradle.kts` |

> 上游 `v1.0.16` 的 Android 工程用的是 Gradle 9.3.1 / AGP 9.1.0 / Kotlin 2.4.0，
> 且 **targetSdk = 28**（为 Termux 式可执行文件让路）。Tavern Lite 不带 rootfs，
> 用 Flutter 3.50 模板的默认 targetSdk 36。

## 二、安装工具

1. **Flutter 3.50.0**
   ```bash
   # 国内镜像
   export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
   export PUB_HOSTED_URL=https://pub.flutter-io.cn
   # Windows: flutter_windows_3.50.0-stable.zip；Linux: flutter_linux_3.50.0-stable.tar.xz
   ```
   本机解压到 `E:\dshgo\sdk\flutter`，`flutter --version` 确认 3.50.0 / Dart 3.14.0。
2. **Android SDK**：cmdline-tools + `platform-tools`、`platforms;android-36`、
   `build-tools;36.0.0`。
3. **JDK 17**（`JAVA_HOME` 指向它；Android Studio 自带的 JBR 25 也能跑，但 AGP 官方
   支持矩阵以 17 为准）。
4. **NDK 28.2.13676358**：`sqlite3 3.9.1` 走 native assets（`hooks` +
   `native_toolchain_c`），Android 构建时**现场编译 SQLite 的 C 源码**，没有 NDK 会
   直接失败。上游 `app/pubspec.yaml` 里没有 `sqlite3_flutter_libs` 就是这个原因。

## 三、命令

```bash
cd tavern-lite/app
flutter config --android-sdk "$LOCALAPPDATA/Android/Sdk"   # 或 android/local.properties 里写 sdk.dir
flutter pub get          # 会顺带跑 gen-l10n（pubspec 里 generate: true）
flutter analyze          # 本项目当前 0 error
flutter build apk --debug
# 产物：build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release
```

`android/local.properties` 需要两行（Flutter 会写 `flutter.sdk`，`sdk.dir` 要自己给）：

```properties
sdk.dir=C\:\\Users\\<你>\\AppData\\Local\\Android\\Sdk
flutter.sdk=E\:\\dshgo\\sdk\\flutter
```

## 四、会踩的坑（本机实际遇到的）

1. **NDK 必须有**。`sqlite3` 的 native assets 构建在 `flutter build apk` 阶段跑
   `native_toolchain_c`，NDK 缺失时报错发生在 Gradle 之后，日志很容易被忽略。
   两条路二选一：
   - 装 `NDK 28.2.13676358`（与上游一致，最稳）；
   - 或加 `sqlite3_flutter_libs` 并在启动时
     `open.overrideFor(OperatingSystem.android, open.overrideFor)` 指向预编译 `.so`
     （省 NDK，但要在真机上自己验，本项目没走这条路）。
2. **路径依赖只能留一个**。原 `app/pubspec.yaml` 里 `dsh_client`、`dsh_remote`、
   `dartssh2` 都是 `path:` 指向原仓库；Tavern Lite 里全删了，只剩
   `dsh_tavern: path: ../packages/dsh_tavern`，否则 `pub get` 直接报错。
3. **l10n 是生成物**。`app/l10n.yaml` + `generate: true`，`lib/l10n/gen/` 由
   `flutter gen-l10n` 从 `lib/l10n/app_zh.arb`（模板）与 `app_en.arb` 生成。
   本仓库里 gen 已提交，方便不跑生成的阅读；改文案请改 ARB，不要手改 gen。
4. **`package:flutter/material.dart` 在 3.50 已被标记 deprecated**，指向
   `package:material_ui/material_ui.dart`。本项目保留 `flutter/material.dart`
   （仍是完整 re-export），`flutter analyze` 只会给 100 多条 info 级提示，不影响构建。
5. **Gradle 慢**。`android/settings.gradle.kts` 里已把阿里云 google / central /
   gradle-plugin 三个镜像放在最前，后面接官方源兜底；wrapper 用 `-bin` 包而不是
   `-all`，能复用本机 `~/.gradle/wrapper/dists/gradle-9.5.0-bin`。
   构建机内存 16 GB 时 `org.gradle.jvmargs=-Xmx8G` 偏大，8 GB 机器请调到 `-Xmx3G`。
6. **首次构建要下 AGP 9.3.1 / Kotlin 2.4.x / 一堆 Maven 依赖**，本机约 6–10 分钟；
   第二次起 2 分钟内。

## 五、产物

```
app/build/app/outputs/flutter-apk/app-debug.apk     # 调试签名
app/build/app/outputs/flutter-apk/app-release.apk   # release（模板签名 = debug key，正式分发要换）
```

`flutter build apk` 默认出**通用 APK**（arm64-v8a + armeabi-v7a + x86_64），可直接装
雷电模拟器（x86_64）与真机。要分 ABI：`flutter build apk --split-per-abi`。

本次实际产物（已放进 `dist/`）：

| 文件 | 大小 |
|---|---|
| `tavern-lite-1.0.16-universal-release.apk` | 105.0 MB |
| `tavern-lite-1.0.16-arm64-v8a-release.apk` | 35.9 MB |
| `tavern-lite-1.0.16-x86_64-release.apk` | 37.5 MB（雷电用这个） |

## 六、测试

```bash
# 引擎：195 个测试文件 / 2111 个用例（Windows 上并行跑偶发一次临时目录改名失败，
# 单独重跑即过；见 docs/VERIFICATION.md）
cd packages/dsh_tavern
dart pub get
dart test

# App：设备上的 widget 级冒烟测试（需要一台已连接的真机 / 模拟器）
cd app
flutter test integration_test -d <device-id>
```

冒烟测试依次验证：首页四个分栏、我的（酒馆设置）的关键行、DeepSeek Key 页、
新的「API 配置」页，以及新增配置的编辑器字段。

## 七、本机实际踩到并已修掉的构建坑

写在这里，换机器时照抄 `android/gradle.properties` 即可少走一遍：

```properties
# Kotlin 2.4.20 的增量编译缓存关不掉（class-fq-name-to-source.tab 等），只能整体关掉
kotlin.incremental=false
# Gradle 会挑 Android Studio 的 JBR 25，固定到 17
org.gradle.java.home=C:/Program Files/Java/jdk-17
```

另外 `app/build.gradle.kts` 里 `lint { checkReleaseBuilds = false; checkDependencies = false }`：
AGP 9.3.1 的 lint 在 release 阶段对插件模块会抛
`NoSuchMethodError: JavaDocParser.parseDataItem`（lint 内置解析器与 Kotlin 2.4 不匹配），
关掉即可；代码检查用 `flutter analyze`。
