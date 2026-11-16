# 核查与验证记录

所有数字都是在这台机器上跑出来的，不是照抄需求描述。

## 一、源码核查

| 项目 | 结果 | 依据 |
|---|---|---|
| 仓库 | `https://github.com/ccch1mneyyy/dsh-Go` | `git ls-remote --tags` |
| tag / commit | `v1.0.16` → `ddaff424b9fa1ed1d0cca389823facc046135dae` | `git log -1`，与需求给的 `ddaff42` 一致 |
| LICENSE | **AGPL-3.0** | 仓库根 `LICENSE` 首行 "GNU AFFERO GENERAL PUBLIC LICENSE Version 3" |
| 引擎 | `packages/dsh_tavern`，**98 个 lib Dart 文件** | `Get-ChildItem -Recurse -Filter *.dart` |
| 引擎测试 | **195 个测试文件 / 2111 个 `test(`** | 正则计数（需求里写的「215 个测试」与实际不符，实际是两个数量级都更大） |
| 酒馆 UI | `app/lib/ui/tavern`，**47 个 Dart 文件**（需求写 48） | 同上 |
| 胶水层 | `app/lib/tavern`，**36 个 Dart 文件** | 同上 |
| 数据目录 | `<app support>/tavern/`（characters / chats / presets / lorebooks / personas / regex / backgrounds） | `lib/src/engine.dart`、`tavern_storage.dart` |

### 依赖闭包（用来决定「拆得动拆不动」）

以 83 个酒馆文件（47 UI + 36 胶水）为根，解析 `import`/`export`/`part`：

- 原 App 内部传递闭包：**958 个文件**（几乎是整个 `app/lib`）；
- 按模块白名单重算：**278 个文件 + 120 个边界导入点**；
- 逐个处理边界后，Tavern Lite 的 `app/lib` = **186 个 Dart 文件**。

需求里「83 个文件只伸出 86 个外部依赖、DSH 部分可以整块删」的估计偏乐观：
酒馆 UI 通过 `ui/common`、`ui/chat/render`、`ui/settings` 这些通用件，间接碰到
终端 / 远程 / 桌宠 / 论坛 / 工坊的页面与状态。真正的边界是**模块级**的，不是文件级。

## 二、构建环境（本机实测）

```
Flutter 3.50.0 • channel stable • revision ab2912035e
Dart 3.14.0
JDK 17.0.6
Android SDK: platforms;android-36（构建时又自动装了 android-35）、build-tools;36.0.0
NDK 28.2.13676358
Gradle 9.5.0 / AGP 9.3.1 / Kotlin 2.4.20（Flutter 3.50 模板）
```

需求里「Flutter 3.50.0 / Dart 3.14.0 / NDK 28.2.13676358 / JDK 17」全部对上；
compileSdk 36 对上；**targetSdk 不是 36 而是 28**——上游为了让 Termux 式可执行文件
跑起来特意降到 28（`app/android/app/build.gradle.kts` 注释写明）。Tavern Lite 不带
rootfs，用模板默认的 36。

Gradle / AGP / Kotlin 上游是 9.3.1 / 9.1.0 / 2.4.0，本项目用 3.50 模板的
9.5.0 / 9.3.1 / 2.4.20。

## 三、静态检查

```
$ flutter analyze --no-pub
124 issues found: 0 error, 7 warning, 117 info
```

117 条 info 里绝大多数是 `package:flutter/material.dart` 在 3.50 的弃用提示
（官方改名 `package:material_ui/material_ui.dart`），仍有完整 re-export，不影响构建。
7 条 warning 是未使用的私有字段/参数（多为为了保持上游签名而留下的）。

## 四、引擎测试

```
$ dart test
00:48 +2730 ~6 -1: Some tests failed.
```

- **2730 通过，6 跳过，1 失败**；
- 失败的是 `test/t16_appearance_test.dart`：`PathAccessException: Rename failed
  ... (OS Error: 拒绝访问, errno = 5)` —— Windows 上临时目录改名被占用，
  单独重跑该文件 **17/17 全过**（`dart test test\t16_appearance_test.dart`）。
  与本次改动无关，属于并行跑测试时的 Windows 文件锁问题。

引擎与上游的差异：`git` 级别逐字节比对，**96/98 个文件完全相同**，只有
`lib/src/api.dart`、`lib/src/llm/model_client.dart` 各加了一个 `stream` 字段。

## 五、构建产物

| 产物 | 大小 | 说明 |
|---|---|---|
| `app-debug.apk` | 189.7 MB | 3 ABI + Vulkan 校验层 + 调试符号 |
| `app-release.apk`（通用） | 105.0 MB | arm64-v8a + armeabi-v7a + x86_64 |
| `app-arm64-v8a-release.apk` | 35.9 MB | 真机 |
| `app-armeabi-v7a-release.apk` | 36.0 MB | 老 32 位机 |
| `app-x86_64-release.apk` | 37.5 MB | 雷电 / 其它模拟器 |

`libsqlite3.so` 三个 ABI 都有（1.65–1.67 MB），证明 `sqlite3 3.9.1` 的 native
assets 路径在 NDK 28.2.13676358 下真的把 C 源码编出来了——这是需求里标为「必然会踩」
的第 1 个坑，实测确实需要 NDK。

构建过程中实际踩到并修掉的：

1. **Kotlin 2.4.20 增量编译缓存在 Windows 上关不掉**：
   `Could not close incremental caches ... class-fq-name-to-source.tab`，
   在 `:android_file_picker` / `:image_picker_android` 上必现。
   解决：`android/gradle.properties` 加 `kotlin.incremental=false`。
2. **AGP 9.3.1 的 lint 在 release 阶段崩**：`NoSuchMethodError:
   JavaDocParser.parseDataItem`（lint 内置解析器与 Kotlin 2.4 不匹配）。
   解决：模块 `lint { checkReleaseBuilds = false; checkDependencies = false }`。
3. **Gradle 默认挑了 Android Studio 的 JBR 25** 而不是 JDK 17：
   在 `android/gradle.properties` 固定 `org.gradle.java.home=C:/Program Files/Java/jdk-17`。
4. Gradle wrapper 用 `-bin` 复用了本机已有的 9.5.0 缓存，省掉一次 200 MB 下载。

## 六、装机实测（雷电模拟器 9，x86_64，Android 9）

```
$ adb install -r app-debug.apk        → Success
$ adb shell am start -n io.github.tavernlite.app/.MainActivity
Displayed io.github.tavernlite.app/...MainActivity: +4s618ms
$ adb shell run-as io.github.tavernlite.app ls files/tavern
characters  tavern.sqlite3  tavern.sqlite3-shm  tavern.sqlite3-wal
```

- 首页正常：标题「酒馆」、四个分栏（书架 / 对话 / 资源库 / 我的）、空状态
  「还没有角色 / 导入一张角色卡：PNG、JSON 或 CHARX」、导入 / 试试示范卡 / 自己写一个角色；
- 「我的」页正常：模型（Flash / V4 Pro）、思考开关、DeepSeek API Key、默认预设、
  上下文上限（4K–128K）、回复上限、温度、单回合费用提醒——全是原版设置项；
- 交互有效：分栏可切换、开关可切换、`+` 能弹出导入方式面板（从文件导入 / 从链接导入 /
  自己写一个角色）；
- 引擎真的起来了：`files/tavern/tavern.sqlite3` 及 WAL 文件已生成，说明
  sqlite3 native 库在设备上加载成功。

（截图见 `docs/screenshots/`。）

### 用 widget 级测试补上「点不到」的部分

雷电把 `adb shell input tap` 的坐标映射得不对（点 A 处、动 B 处），所以改了条路：
在设备上跑 `integration_test`，直接驱动真实的 widget 树，不经过宿主坐标。

```
$ flutter test integration_test -d emulator-5554
00:00 +0: the tavern home, settings and the API pages open
00:10 +1: All tests passed!
```

`integration_test/app_smoke_test.dart` 依次走：

1. 首页：`酒馆` 标题 + 书架 / 对话 / 资源库 / 我的 四个分栏都在；
2. 「我的」：模型、思考、DeepSeek API Key、上下文上限、温度都在；
3. 点 `DeepSeek API Key` → 出现「DeepSeek 官方」和「打开 API 配置」；
4. 点「打开 API 配置」→ 出现「API 配置」「新增」「自定义 API（OpenAI 兼容）」；
5. 点「新增」→ 编辑器打开，名称 / 模型 / 用 SSE 流式返回 / 测试连接 都在。

这一步把新增的多 API 界面从「代码通过分析」提升到「在设备上真的渲染、真的能点」。

第二个测试走完整条故事链路：

```
$ flutter test integration_test/app_tavern_flow_test.dart -d emulator-5554
00:00 +0: the sample card opens a chat with the stage panel
00:48 +1: All tests passed!
```

`integration_test/app_tavern_flow_test.dart`：点「试试示范卡」→ 角色卡真的导入并打开角色页
→ 点「开始」进入聊天 → 宽屏右侧的舞台面板「本局 / 状态 / 导演 / 本回合」四个标签都在。
也就是说：角色卡导入、角色页、聊天页、舞台四标签这条主线在设备上是通的。


## 七、真机与真实模型调用（后续补测）

### 装机

Redmi `2312DRAABC`（Android 15 / SDK 35 / arm64-v8a），无线调试配对后安装
`app-arm64-v8a-release.apk`（35.9 MB）：`Success`，启动
`io.github.tavernlite.app/io.github.tavernlite.app.MainActivity` 正常。
首页、设置页、角色页、导入方式面板都渲染正常；点「试试示范卡」导入林晚，书架里出现
卡片（`示范 · 悬疑 · 日常`），角色页有开场白 `开场白 1/2` 和「开始」键。

### 真实模型调用（这是之前缺的那块）

用真实 Key 在真机上跑引擎，不经 UI、不 mock：

```
$ flutter test integration_test/live_model_test.dart -d <phone> \
    --dart-define=TAVERN_TEST_KEY=sk-... --dart-define=TAVERN_TEST_MODEL=deepseek-flash
[{"model":"deepseek-flash","thinking":false,"chars":36,"reasoningChars":0,
  "promptTokens":403,"cacheHitTokens":256,"completionTokens":24,"finishReason":"stop"},
 {"model":"deepseek-flash","thinking":false,"chars":43,"reasoningChars":0,
  "promptTokens":400,"cacheHitTokens":128,"completionTokens":29,"finishReason":"stop"}]
All tests passed!
```

证明：流式 SSE、`thinking: disabled` 生效（reasoning 0 字）、两回合连续对话、
`usage` 与**缓存命中**都真的从服务端回来（第二条 128 的 cacheHit 就是「本回合」面板
显示的那个数）。

自定义 OpenAI 兼容档（`deepseek: false` + `stream: false`，非流式分支）：

```
{"base":"https://api.deepseek.com","model":"deepseek-flash","deepseek":false,"stream":false,
 "chars":58,"promptTokens":427,"cacheHitTokens":0,"completionTokens":147,"finishReason":"stop"}
All tests passed!
```

`https://api.deepseek.com/models` 实测返回两个模型：`deepseek-flash`
（DeepSeek-V4.1-Flash，1M 上下文，支持图像输入）与 `deepseek-v4-pro`（1M 上下文），
与应用里写死的模型列表一致。

### 一个环境限制

这台 MIUI 机器上 `adb shell input tap` 的落点和截图坐标并不稳定对齐（点 A 处、
动 B 处；`Test-NetConnection` 与 `input keyevent` 都正常，说明不是注入被禁）。
应用本身的点击是好的——`integration_test` 直接走 widget 命中测试，在这台机器上
两条测试都通过。所以这不是 App 的 bug，是 adb 注入在这台 ROM 上的怪癖；截图里的
手动点按有些能中、有些偏，不能当作功能验证。

## 八、仍然没能验证的部分

1. **真实模型调用**：没有可用的 API Key，DeepSeek 官方与自定义端点都只做了
   「代码路径 + URL 拼接 + 打码」层面的检查与 `flutter analyze`，没有发出真实请求。
2. **第三方 OpenAI 兼容服务的实际兼容性**：只按标准 Chat Completions 字段对接，
   OpenRouter / SiliconFlow / Ollama 等未逐一实测。
3. **完整 UI 走查**：模拟器里点按坐标与画面存在偏移（雷电的输入映射问题），只点通了
   首页、我的、导入方式面板；聊天页 / 舞台四标签 / 提示词检视 / 缓存统计 **没有**
   用鼠标逐页点过。这些页面代码来自上游且 `flutter analyze` 通过，但没有运行期证据。
4. **角色卡导入**：示例卡与文件导入没有在模拟器里完成（需要文件选择器交互）。
5. **真机**：只在 x86_64 模拟器上装过，arm64 真机未测。
6. **Live2D / 语音 / 故事书分享 / WebView 沙箱**：分别是空实现、已删除、
   改用 share_plus、降级守卫，均未实测。
7. **release 签名**：release APK 用的是 Flutter 模板的 debug 签名，正式分发要换
   自己的 keystore。
