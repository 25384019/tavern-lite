# 兼容性：保留了什么、去掉了什么

对照上游 `v1.0.16`（`app/lib/ui/tavern` 47 个文件、`app/lib/tavern` 36 个文件、
`packages/dsh_tavern` 98 个文件）逐项说明。

## 一、引擎（`packages/dsh_tavern`）——全保留

98 个 lib 文件里 **96 个与上游逐字节相同**，只有两处为「自定义 API 的 SSE 开关」加了
一个字段：

- `lib/src/api.dart`：`TavernModelConfig` 增加 `final bool stream`，默认 `true`；
- `lib/src/llm/model_client.dart`：`stream == false` 时把请求体里的 `stream` 强制为
  `false`，`true` 时沿用上游的 `putIfAbsent('stream', () => true)`。

因此上游的 195 个测试文件（2111 个 `test(`）照旧可跑，默认路径行为不变。

保留的能力：角色卡（PNG / JSON / CHARX / ST 导出）、世界书、预设（含 ST 预设导入）、
正则脚本（含 `regex_worker` 隔离）、卡片脚本、ST 宏与旧宏、斜杠命令解析与执行、
状态引擎（JSONLogic）、导演（director / direct_tool）、提示词装配与检视、
`TavernTurnInspection`（token 与缓存统计）、聊天 JSONL 存储与分支、群聊、备份。

## 二、酒馆 UI（`app/lib/ui/tavern`）——全保留

47 个文件全部在，页面清单：

| 页面 / 组件 | 文件 | 状态 |
|---|---|---|
| 酒馆首页（角色网格、搜索、标签、最近对话） | `tavern_home_page.dart` | 保留 |
| 聊天页（气泡 / 小说 / 视觉小说三种版式） | `tavern_chat_page.dart` | 保留；去掉语音输入（见§四） |
| 舞台面板（本局 / 状态 / 导演 / 本回合 四标签） | `tavern_stage_panel.dart` | 保留 |
| 角色页 / 编辑页 / 导入报告 | `tavern_character_page.dart`、`tavern_character_edit_page.dart`、`tavern_report_page.dart` | 保留；Live2D 区块变空 |
| 预设 / 预设编辑 | `tavern_presets_page.dart`、`tavern_preset_page.dart` | 保留 |
| 世界书 / 编辑 / 测试 | `tavern_lorebooks_page.dart`、`tavern_lorebook_page.dart`、`tavern_lorebook_test_page.dart` | 保留 |
| 正则 / 编辑 / 测试 | `tavern_regex_page.dart`、`tavern_regex_edit_page.dart`、`tavern_regex_test_page.dart` | 保留 |
| 人设 | `tavern_personas.dart` | 保留 |
| 分支 / 书签 / 搜索 | `tavern_branches_page.dart`、`tavern_bookmarks_page.dart`、`tavern_search_page.dart` | 保留 |
| 消息编辑 / 重新生成 | `tavern_message_edit_page.dart` | 保留 |
| 群聊（新建 / 群页） | `tavern_group_new_page.dart`、`tavern_group_page.dart` | 保留 |
| 画布 / 海岛 / WebView 沙箱 | `tavern_canvas_view.dart`、`tavern_island.dart`、`tavern_live_display.dart` | 保留（WebView 崩溃守卫降级，见§四） |
| 快捷回复 / 骰子 / 组件 | `tavern_quick_replies_page.dart`、`tavern_dice_sheet.dart`、`tavern_component_view.dart` | 保留 |
| 故事书（导出图片 / 分享） | `tavern_storybook_page.dart` | 保留，改用 share_plus |
| 用量 / 运行记录 | `tavern_usage_page.dart`、`tavern_runs_page.dart` | 保留 |
| 设置 | `tavern_settings_page.dart` | 保留，模型列表随 API 配置走 |
| 互动视图 / 阅读层 / 墨色 / 精灵 | `tavern_interact_view.dart`、`tavern_reading.dart`、`tavern_ink.dart`、`tavern_widgets.dart` | 保留 |

## 三、胶水层（`app/lib/tavern`）——全保留

36 个文件全在：`tavern_provider`（唯一引擎实例，改成读 API 配置）、
`tavern_settings`、`tavern_storage`、`tavern_card_*`、`tavern_canvas*`、
`tavern_script_host/wire`、`tavern_session_usage`、`tavern_state_hints`、
`tavern_jump/bookmarks/pinned/quick_replies/shelf/slash/sprites/st_theme/storybook` 等。

## 四、明确去掉的（及原因）

| 去掉的东西 | 上游位置 | 原因 / 影响 |
|---|---|---|
| DSH 引擎、会话、工作区、SSH / 远程、终端 | `runtime/`、`remote/`、`ssh/`、`ui/terminal`、`engine_settings/` | 与酒馆无关；`dsh_client`/`dsh_remote`/`dartssh2` 三个路径依赖随之删除 |
| 桌宠、伙伴小屋、Live2D 运行时 | `pets/`、`companion/`、`ui/pets`、`ui/companion` | 需要额外下载的运行时与常驻悬浮窗；视觉小说的 Live2D 舞台变成空实现，改用角色卡自带的立绘（`tavern_sprites`） |
| DSH 机器人 / 房间 | `ui/bots` 的聊天部分 | 只留 `bot_format.shortTime` 与聊天页外壳 `BotChatHeader`/`BotChatFrame`（重写为 200 行） |
| 论坛、工坊、分享码、托管链接 | `forum/`、`workshop/`、`share_code/`、`share_hosted/` | 社交与云端功能，与酒馆无关 |
| 手机控制（无障碍 / Shizuku / ADB） | `phone/`、`ui/phone` | 权限模型完全不同，不属于本 App |
| 内置网页（DSH Web） | `ui/web`、`assets/web` | 没有引擎可连 |
| `dsh-ui` 视图渲染 | `ui/chat/dsh_ui` 的 26 个文件 | 只保留 `dshUiReadableColor` 的等价实现（`ui/chat/dsh_ui/dsh_ui_model.dart`，对比度算法重写）；正文里的 ` ```dsh-ui ` 代码块按普通代码块显示 |
| 语音输入 / TTS 控制 | `ui/chat/voice`、`state/voice_*` | 依赖 DSH 语音栈；输入框保留文字发送、帮我写、接着写、快捷回复 |
| 启动动画 / 引导页 / 更新器 / 诊断 | `launch/`、`onboarding/`、`update/`、`diagnostics/` | 打开即酒馆首页 |
| 界面自定义（`ui_config`） | `ui_config/` | 只保留主题、语言 |

## 五、降级实现（保留接口，行为变简）

| 模块 | 上游 | 现在 |
|---|---|---|
| WebView 崩溃守卫 `WebViewGuard` | 通过 DSH 原生 islands 插件接管 renderer | 只记录 id、设置背景色；renderer 被杀时没有回执（Android 默认行为） |
| 聊天背景图导入 `WallpaperImport` | 原生选区 + 分享导入 | `file_picker` + 复制到 `<support>/tavern/backgrounds` |
| 故事书分享 `ShareExporter` | DSH 分享面板与图片槽 | `share_plus` 直接分享；「保存」走系统分享里的保存目标 |
| 链接路由 `LinkRouter` | `dshgo://` 与文件打开意图 | 只有内存里的扩展名 → 处理函数表；`VIEW`/`SEND` 意图未接（酒馆内导入不受影响） |
| 卡片 Live2D 区块 | 模型包导入与预览 | 空组件（`SizedBox.shrink`） |
| 提示词里的 `dsh-ui` 修复 | 裸 JSON 自动补围栏 | 关掉（`repairBareViews` 参数仍在，不生效） |

## 六、没有验证的部分

见 `docs/VERIFICATION.md` 末尾的清单（真机 UI 走查、各家第三方 API 的实际兼容性、
Live2D / 语音 / 分享在具体 ROM 上的表现等）。
