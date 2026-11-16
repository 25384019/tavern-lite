# 架构

## 一、两层

```
┌───────────────────────────── app/（Flutter） ─────────────────────────────┐
│  ui/tavern/*            47 个文件，原样搬运的酒馆页面                     │
│  tavern/*               36 个文件，页面与引擎之间的胶水                   │
│  ui/{theme,common,chat/render,settings,features,shell,bots,providers,...} │
│                         App 的视觉与通用件（裁剪后的子集）                │
│  state/settings_state   精简后的设置（Key / 主题 / 回车发送）             │
│  api/*                  ★ 多 API 配置（本项目新增）                       │
└──────────────────────────────────┬────────────────────────────────────────┘
                                   │ 只通过 Tavern 接口
┌────────────────────────── packages/dsh_tavern（纯 Dart） ─────────────────┐
│  api.dart               对外接口：Tavern / TavernModelConfig / 值类型     │
│  engine.dart            实现：卡片 IO、聊天存储、回合引擎                 │
│  prompt/*               预设、提示词装配、检视输入                        │
│  llm/model_client       唯一出口：OpenAI Chat Completions + SSE           │
│  director/*             自动导演                                          │
│  state/*                状态引擎（JSONLogic）                             │
│  worldinfo/*            世界书                                            │
│  regex/*                正则脚本与隔离 worker                             │
│  slash/*                ST 斜杠命令                                       │
│  store/*                角色 / 聊天 / 人设 / 正则库（sqlite3 + 文件）     │
└───────────────────────────────────────────────────────────────────────────┘
```

界面永远不直接发 HTTP：所有模型调用都经过 `TavernModelConfig` 交给引擎的
`TavernModelClient`，所以「换 API」只是换一份 `TavernModelConfig`。

## 二、启动

```
main()
 ├─ AppLocale.resolve(systemLocales)      → 中/英
 ├─ SystemChrome.setEnabledSystemUIMode(edgeToEdge)
 └─ runApp(ProviderScope(TavernLiteApp))
       └─ MaterialApp(theme: buildLightTheme/buildDarkTheme, home: TavernHomePage)
```

没有启动动画、没有引导页、没有 DSH 运行时。首个用到引擎的 provider 会异步打开它：

```dart
// app/lib/tavern/tavern_provider.dart
final tavern = DeferredTavern(() async {
  final support = await getApplicationSupportDirectory();
  return openTavern('${support.path}/tavern');   // <app support>/tavern
}());
```

`DeferredTavern` 在引擎就绪前把手上的调用排队，所以首页可以立刻画出来。

数据目录（与原版一致，换机拷过来能直接读）：

```
<app support>/tavern/
├── characters/     角色卡与头像
├── chats/          聊天 JSONL（一个分支一个文件）
├── presets/        预设
├── lorebooks/      世界书
├─�� personas/       人设
├── regex/          正则脚本
├── backgrounds/    聊天背景图
└── live2d/         角色 Live2D 包（本 App 不再读取）
```

## 三、多 API 是怎么接进去的

```
apiProfilesProvider (Notifier<ApiProfilesState>)
        │  active: ApiProfile
        ▼
tavernProvider ── tavernModelConfigFor(ref) ──► TavernModelConfig(
        │                                         apiKey: () async => key,
        │                                         baseUrl: …,
        │                                         model: …,
        │                                         deepseek: kind == deepseek,
        │                                         thinking: …,
        │                                         stream: …)
        ▼
tavern.configure(config)   // 激活项或酒馆设置变化时重配
        ▼
引擎下一回合调用 TavernModelClient.generate(...)
```

`TavernModelConfig.apiKey` 是**回调**而不是字符串：引擎每次调用才去取 Key，
Key 因此不需要进引擎内存，也不会被写进任何聊天文件。

## 四、裁剪是怎么算出来的

1. 以 `app/lib/ui/tavern/*` + `app/lib/tavern/*` 共 83 个文件为根，解析
   `import`/`export`/`part`，得到**原 App 内部 958 个文件**的传递闭包——也就是
   「照抄能编译」的规模，显然不是一个独立 App。
2. 按模块给白名单（只留酒馆真正用到的通用件），重算闭包 → 278 个文件、120 个边界
   导入点。
3. 对这 120 个边界逐个处理：能用 20–200 行重写的就重写（下表），能删功能的就删，
   需要原样的就从上游复制。
4. 结果：`app/lib` 186 个 Dart 文件 + 引擎 98 个，`flutter analyze` 0 error。

边界处理清单（这些文件都是本项目新写的，不是上游文件）：

| 文件 | 行数级别 | 作用 |
|---|---|---|
| `ui/bots/bot_format.dart` | 25 | 只留 `shortTime`（酒馆 8 个页面用它格式化时间） |
| `ui/bots/bot_chat_kit.dart` | 220 | 聊天页外壳 `BotChatFrame` + 顶栏 `BotChatHeader`（从上游同名文件摘出，去掉 bot 转写部分） |
| `ui/chat/composer.dart` | 240 | 输入区（上游 941 行，含附件/语音/桌宠/模型键） |
| `ui/chat/render/markdown_body.dart` | 上游 669 行，改 5 处 | 保留 Markdown 主题、代码块、表格、公式、图片；去掉工作区/工件/`dsh-ui` 分支 |
| `ui/chat/render/markdown_image.dart` | 150 | 网页 / `data:` / 本地文件三种图片 |
| `ui/chat/widgets/{thinking_pill,stream_row,notice_row}.dart` | 90 / 45 / 150 | 思考胶囊、流式细节行、错误条 |
| `ui/engine_settings/field_sheets.dart` | 60 | 骰子面板要的 `SheetCard` / `StepKey` |
| `ui/providers/provider_widgets.dart` | 150 | 表单件 `FormFieldGroup/Block/Label/SmallButton/BottomBar` |
| `ui/modes/mode_switch.dart` | 75 | 单模式的模式键与说明 |
| `ui/companion/{companion_stage,companion_log}.dart` | 70 / 130 | 视觉小说舞台空实现 + 回顾日志 |
| `ui/wallpaper/wallpaper_backdrop.dart` | 60 | 聊天背景绘制 |
| `ui/share/{share_export,share_gallery}.dart` | 50 / 2 | 故事书分享 |
| `ui/web/web_view_guard.dart` | 55 | WebView 守卫（降级） |
| `ui/shell/adaptive/adaptive_layout.dart` | 18 | 只留 `WindowClass.compactHeight` |
| `ui/chat/dsh_ui/dsh_ui_model.dart` | 65 | 卡片配色对比度算法 |
| `state/settings_state.dart` | 100 | 设置 |
| `links/app_links.dart` | 40 | 链接路由 |
| `state/attachments.dart` | 11 | `formatBytes` |
| `wallpaper/wallpaper_import.dart` | 80 | 背景图选区与复制 |
| `tavern/tavern_live2d.dart` | 90 | Live2D 空实现 + 情绪词表（立绘表情仍用） |
| `api/api_profiles.dart` + `ui/api/*` | 260 + 340 + 300 | 多 API 配置（新增） |

## 五、依赖

`app/pubspec.yaml` 只保留酒馆实际用到的包：

```
flutter, flutter_localizations, intl, cupertino_icons,
flutter_riverpod, shared_preferences, flutter_secure_storage, path_provider,
gpt_markdown, val_latex_flutter, re_highlight, url_launcher, file_picker,
http, html, archive, image, crypto, yaml, share_plus,
scrollable_positioned_list, webview_flutter, webview_flutter_android, image_picker,
dsh_tavern (path: ../packages/dsh_tavern)
```

原 `app/pubspec.yaml` 里的 `dsh_client`、`dsh_remote`、`dartssh2`、`flutter_webrtc`、
`mobile_scanner`、`xterm`、`pointycastle`、`cryptography`、`timezone`、
`connectivity_plus` 都随对应功能一起删掉了。

## 六、Android 工程

`app/android` 是 `flutter create` 生成的干净工程，只改了三处：

- `applicationId = "io.github.tavernlite.app"`（与原版 `io.github.ccch1mneyyy.dsh_app`
  不同，**可以并存安装**）；
- `minSdk = 26`；
- `settings.gradle.kts` 前面加了阿里云 Maven 镜像。

原版的 `runtime/out`（rootfs、proot）、Shizuku、libadb、ML Kit、XZ 这些 Gradle 依赖
全部没有，APK 体积因此从原版的上百 MB 降到十几 MB 量级（含 Flutter 引擎）。
