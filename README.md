# Tavern Lite — DSH Go 酒馆模块的独立 Android 应用

DSH Go（<https://github.com/ccch1mneyyy/dsh-Go>，tag `v1.0.16`，commit
`ddaff424b9fa1ed1d0cca389823facc046135dae`，AGPL-3.0）里的「酒馆」是完整的一套
SillyTavern 兼容角色扮演：角色卡 / 预设 / 世界书 / 聊天记录 / 舞台四标签 / 自动导演 /
提示词检视 / 缓存统计，引擎是纯 Dart 的 `packages/dsh_tavern`。

这个仓库把它单独拆出来做成一个 App：**没有 DSH 引擎、没有终端、没有 SSH / 远程、
没有桌宠 / 论坛 / 工坊**，卡片与故事的全部功能照原样，并在原来只有 DeepSeek 一家
接口的基础上，加了「可保存多份、随时切换的 OpenAI 兼容自定义 API」。

```
tavern-lite/
├── app/                     Flutter 应用（Android）
│   ├── lib/
│   │   ├── main.dart        直接进酒馆首页
│   │   ├── app.dart         主题 / 语言 / MaterialApp
│   │   ├── api/             ★ 多 API 配置（新增）
│   │   ├── tavern/          原 app/lib/tavern（36 个文件）——引擎之上的胶水层
│   │   ├── ui/tavern/       原 app/lib/ui/tavern（47 个文件）——酒馆 UI
│   │   ├── ui/{theme,common,chat/render,settings,features,shell,bots,providers,...}
│   │   │                    原 App 里酒馆真正用到的那部分（裁剪后）
│   │   ├── state/           设置（精简到酒馆需要的字段）
│   │   ├── wallpaper/       聊天背景图
│   │   └── l10n/            与原文一致的 ARB + 生成的 L10n
│   └── android/             本项目自己的 Android 工程（applicationId 独立）
├── packages/dsh_tavern/     引擎，**98 个 lib 文件与上游逐字节相同**
├── docs/                    架构 / API 配置 / 兼容性 / 构建 / 核查记录
├── LICENSE                  AGPL-3.0（与原仓库一致）
└── THIRD_PARTY_NOTICES.md   与原仓库一致
```

## 与上游的差异（全部可核对）

| 改动 | 位置 | 说明 |
|---|---|---|
| 只加了 `stream` 字段 | `packages/dsh_tavern/lib/src/api.dart`、`lib/src/llm/model_client.dart` | 其余 96 个引擎文件与 `v1.0.16` 逐字节相同；默认 `stream = true` 时行为与上游完全一致 |
| 新增多 API 配置 | `app/lib/api/api_profiles.dart` 等 | DeepSeek 官方 + 任意个 OpenAI 兼容端点，Base URL / Key / 模型 / SSE / 思考开关，保存并切换 |
| 精简设置 | `app/lib/state/settings_state.dart` | 原文件里的 DSH 引擎开关随引擎一起删掉，只留 DeepSeek Key、主题、回车发送 |
| 新增 API 页 | `app/lib/ui/api/` | 列表 / 编辑 / 连接测试 / 激活 |
| 移除 | `ui/bots` 的聊天部分、`ui/onboarding`、`ui/plugins`、`ui/terminal`、`remote`、`pets`、`forum`、`workshop`、`companion` 运行时、`share_code`、`ui_config` 等 | 见 `docs/COMPATIBILITY.md` 的逐项说明 |

## 快速开始

```bash
cd app
flutter pub get
flutter analyze          # 0 error
flutter build apk --debug     # 或 --release
```

要求：Flutter 3.50.0（Dart 3.14.0）、JDK 17、Android SDK 36 + build-tools 36.0.0、
NDK 28.2.13676358（sqlite3 走 native assets，构建时会现场编译 C 源码）。
细节与踩坑见 [docs/BUILD.md](docs/BUILD.md)。

**已经编好的 APK** 在 `dist/`：

| 文件 | 用在哪 |
|---|---|
| `tavern-lite-1.0.16-universal-release.apk`（105 MB） | 任意设备，含三种 ABI |
| `tavern-lite-1.0.16-arm64-v8a-release.apk`（35.9 MB） | 绝大多数真机 |
| `tavern-lite-1.0.16-x86_64-release.apk`（37.5 MB） | 雷电 / 其它 x86_64 模拟器 |

applicationId 是 `io.github.tavernlite.app`，可以和 DSH Go 并存安装。
release 用的是模板的 debug 签名，正式分发请换自己的 keystore。

实测记录（含哪些没验）见 [docs/VERIFICATION.md](docs/VERIFICATION.md)，
截图在 [docs/screenshots/](docs/screenshots/)。

## 给接手的人 / 给 AI 查 bug

这个仓库的用途之一是**在别的机器上（或没有开发环境时）把代码交给 AI 读、定位问题**。
按这个顺序读最省事：

1. **[HANDOFF.md](HANDOFF.md)** —— 唯一的现状文档。每轮改了什么、为什么改、
   哪些验过哪些没验、已知问题，都在里面（末尾几节是最新的一轮）。
2. `docs/` 里的 `ARCHITECTURE.md`（分层）、`API_CONFIGURATION.md`（多 API）、
   `COMPATIBILITY.md`（相对上游删了什么）、`BUILD.md`（构建踩坑）。
   `docs/*.md` 有些是早期记录，判断现状以 HANDOFF 为准。
3. 代码分三层，别混：
   - `packages/dsh_tavern/` —— 引擎（会话、世界书激活、预设组装、导入导出），
     基本与上游逐字节相同，改它要慎重；
   - `app/lib/tavern/` —— 胶水层（AI 制卡、世界书工坊、预设、状态模板、存储）；
   - `app/lib/ui/tavern/` —— 界面。约 50 个文件，按功能命名，一眼能找到。

### 不装设备也能跑的东西

```bash
cd app
dart analyze                 # 只要包已解析好，不需要设备；本项目要求 0 error
flutter test                 # 纯 Dart 单测（不需要设备）
flutter test test/lorebook_kind_persona_test.dart   # 单跑一组
python tool/l10n_merge.py    # 改了 lib/l10n/parts/*.arb 之后必须跑，它会合并并重生成 L10n
```

- 界面文案**不要写死**：改 `app/lib/l10n/parts/<area>_zh.arb` 和 `_en.arb`，
  再跑 `python tool/l10n_merge.py`；`app/lib/l10n/gen/` 是生成物，不要手改。
- `app/build/`、`.dart_tool/`、`dist/*.apk` 都不在本仓库里（见 `.gitignore`）：
  这些是几个 GB 的产物，重建即可。

### 环境要求（与 `app/pubspec.yaml` 一致）

Flutter 3.50.0 / Dart 3.14.0、JDK 17、Android SDK 36 + build-tools 36.0.0、
NDK 28.2.13676358（sqlite3 走 native assets，构建时现场编译 C）。

`app/pubspec.yaml` 声明的是 `sdk: ^3.13.5`；**Dart 低于这个版本时
`flutter pub get` / `flutter test` / `flutter build` 都会直接
`version solving failed`**，而 `dart analyze` 在包已解析的情况下仍可用。
遇到这种情况先升 SDK，别改代码去迁就。

## 使用

1. 装好后打开就是酒馆首页，导入角色卡（PNG / JSON / CHARX）。
2. 首页右上「设置 › API Key」填 DeepSeek 官方 Key；要接中转或本地模型，进
   「API 配置 › 新增」，填 Base URL、Key、模型，保存后点选即切换。
3. 舞台面板（聊天页右上或宽屏右侧）四标签：本局 / 状态 / 导演 / 本回合。
4. 提示词检视在「本回合」，缓存命中与 token 统计同页；`酒馆设置 › 显示` 里可开关
   每条回复下的用量行。

## 许可

AGPL-3.0，与上游一致。分发本应用或其修改版时必须提供源码；引擎部分（`packages/dsh_tavern`）
的版权归上游作者。详见 `LICENSE` 与 `THIRD_PARTY_NOTICES.md`。
