# 世界书工坊 · 预设工坊 开发任务书（v1）

> 读者：接下来写代码的人（Codex / DeepSeek）。
> 范围：**只有这两个工坊**。角色卡工坊正在开发，本任务书不允许改它的任何文件。
> 目标：写完就能用——生成的条目直接进「资源库 › 世界书」，生成的预设直接进「资源库 › 预设」，
> 不挂靠在某张角色卡上。

---

## 0. 边界（先看这一节，违反就别合）

### 0.1 不许改的文件

```
app/lib/ui/tavern/tavern_card_studio_page.dart      ← AI 角色工坊（快速/高级）
app/lib/ui/tavern/tavern_studio_page.dart           ← 专业创作（九模块）
app/lib/tavern/tavern_studio_*.dart                 ← 草稿 / 字段表 / 转换器
app/lib/tavern/tavern_card_studio.dart
app/tool/gen_studio_schema.py
app/lib/l10n/parts/studio_*.arb
app/lib/l10n/parts/tavern_*.arb 里 tavernCardStudio* / tavernCardTrait* 那段
app/test/tavern_studio_test.dart
integration_test/app_studio_test.dart
integration_test/app_card_studio_test.dart
```

确实需要在那儿加一行（比如首页加个入口），**单独一个 commit，只加入口那一行**，不改别的。

### 0.2 只许通过这几条接口碰数据

| 用途 | 接口（`Tavern` 上已有） |
|---|---|
| 列世界书 | `listLorebooks()` |
| 读一本 | `lorebook(id)` |
| 写一本（新建/覆盖） | `putLorebook(id, json)` |
| 导出 | `exportLorebook(id)` |
| 导入 | `importLorebook(text, fileName:)` |
| 删除 | `deleteLorebook(id)` |
| 绑定 | `bindLorebooks(ids, source:, chatId:, characterId:, personaId:)` |
| 列预设 | `listPresets()` / `watchPresets()` |
| 读预设 | `preset(id)` |
| 新建预设 | `importPreset(text, fileName:)` |
| 改预设 | `updatePreset(id, patch, name:)` |
| 改单条提示词 | `updatePresetPrompt(id, identifier, patch)` |
| 排序 / 开关 | `setPresetOrder(id, ids)` / `setPresetPromptEnabled(id, id, on)` |
| 导出预设 | `exportPreset(id)` |
| 默认 / 绑定 / 删 | `setDefaultPreset` / `bindPreset(chatId, id)` / `deletePreset(id)` |

卡片的接口（`importCard` / `updateCharacterFields` / `addCharacterBookEntry` …）**一律不碰**；
只有「把世界书绑到某个角色」这一个动作允许调 `bindLorebooks(characterId: …)`。

### 0.3 一个字都不许自己造的地方

- 世界书 JSON 结构：**ST 原生格式**（`entries` 是以 `uid` 为键的对象）。引擎的 intake 也吃
  CC v3 的 `entries` 数组，但**写回统一用原生格式**，否则用户导出到 SillyTavern 会变形。
- 预设 JSON 结构：**ST 原生**（`prompts` 数组 + 顶层采样参数）。不要发明"我们的预设格式"。
- 一切界面文字走 `lib/l10n/parts/`，新增一个 part：`lorebook_{zh,en}.arb`、`preset_{zh,en}.arb`。

---

## 1. 现状盘点（先把这些读一遍再动手）

| 已有 | 文件 | 能复用吗 |
|---|---|---|
| 独立世界书列表 | `ui/tavern/tavern_lorebooks_page.dart` | ✅ 列表骨架、导入、导出、删除、绑定都在 |
| 卡内世界书 | `ui/tavern/tavern_lorebook_page.dart` | ⚠️ 只对卡片的 `character_book`，别改，另写 |
| 世界书测试 | `ui/tavern/tavern_lorebook_test_page.dart` | ⚠️ 只测卡内书（`previewCharacterBook`） |
| 预设列表 / 预设详情 | `ui/tavern/tavern_presets_page.dart`、`tavern_preset_page.dart` | ✅ 列表、导出、删除、默认、绑定、单条开关都在 |
| 一次性模型调用 | `tavern/tavern_provider.dart` 的 `tavernModelClientProvider` + `tavernModelConfigProvider` | ✅ AI 生成直接用这一对，别再建连接层 |
| 制卡的解析兜底 | `tavern/tavern_card_studio.dart` 的 `tavernCardParse` | ✅ 抄一份 `lorebookParseJson`（围栏/散文/包裹都能救） |

### 1.1 缺口（这些要新建，不要硬拼）

| 缺口 | 影响 | 建议 |
|---|---|---|
| **独立世界书没有预览/调试 API** | 「07 调试器」做不了 | 引擎加 `previewLorebook(id, text, {chatId, seed})`，照 `previewCharacterBook` 抄；这是唯一一处允许动 `packages/dsh_tavern` 的地方，单独 PR |
| 没有 Token 计数 API | 「Token 分析」只能估 | 先按 `字数/1.6` 估算并标注"估算"；引擎侧暴露计数放 P3 |
| 没有版本历史存储 | 「版本历史」无处落 | 存本地：`<app support>/studio/history/<kind>-<id>-<ts>.json`，只留最近 20 份 |
| 没有 AI 服务抽象 | 两个工坊各写一套提示 | 新建 `tavern_studio_ai.dart`：`askJson(messages, schemaHint)` → 解析后的 Map |

---

## 2. 架构（逻辑分层，对应到文件）

```
ui/lorebook/  ─────────────┐
  workshop_home.dart        │  页面层：只画、只转发
  blueprint_wizard.dart     │
  entry_editor.dart         │
  trigger_editor.dart       │
  graph_page.dart           │
  timeline_page.dart        │
  debug_page.dart           │
                            ▼
tavern/lorebook_draft.dart ──── 数据层：ST 原生 JSON 的读写、校验、版本
tavern/lorebook_build.dart ──── 转换层：草稿 → 可 putLorebook 的 JSON（纯函数，全单测）
tavern/studio_ai.dart  ──────── AI 服务：提示组装、JSON 解析、失败兜底
```

预设同构：`ui/preset/`、`tavern/preset_draft.dart`、`tavern/preset_build.dart`。

**六个"服务"就是这四层里的一组纯函数**，不要求建同名目录：

| 用户文档里的名字 | 这里落在哪 |
|---|---|
| `LorebookRepository` | `Tavern` 的 lorebook 接口 + 本地历史文件 |
| `LorebookEngine` | 引擎（已有；本任务书只加 `previewLorebook`） |
| `PresetRepository` | `Tavern` 的 preset 接口 |
| `PromptAssembler` | 引擎（已有，别碰） |
| `AiCreationService` | `studio_ai.dart` |
| `PromptInspector` | 引擎已有 `inspectTurn`（聊天页在用）；世界书侧用新的 `previewLorebook` |

---

## 3. 世界书工坊

### 3.0 首页 `lorebook/workshop_home.dart`

- 标题「世界书工坊」，副标题「创造世界，让每个设定都有意义」。
- 三张卡：**AI 创作**（进四阶段向导）、**导入世界书**（吃 JSON）、**新建空白**。
- 下面「我的世界书」列表：一行一本，`名称 · 类型 · N 个条目 · 绑定数`。
  数据来自 `listLorebooks()`；`entryCount` 现成有；绑定数要自己数（`bindLorebooks` 的读侧没有查询接口，
  P1 先显示"—"，P2 再补）。
- 点一本进 **条目管理器**（3.2），长按出：导出 / 复制 / 删除 / 设为某角色绑定。

### 3.1 世界观设计器（四阶段向导）`blueprint_wizard.dart`

不要让模型一次吐几十条。四个阶段，每阶段是一屏、一个 JSON 输出、可单独重跑：

| 阶段 | 输入 | 输出（JSON） | 用户能改什么 |
|---|---|---|---|
| **1 世界蓝图** | 一句创意 + 类型（奇幻/现代/校园/星际…）+ 基调 | `{name, overview, rules[], factions[], places[], conflicts[]}` | 逐条删改、锁定 |
| **2 条目规划** | 蓝图 + 期望规模（小 5-10 / 中 15-30 / 大 40-80） | `{entries:[{title, kind, whyNeeded}]}` | 删/加/锁定；只出标题和用途，不出正文 |
| **3 分批生成** | 蓝图 + 规划里**未锁定**的 3~8 条 | 每批 `{entries:[{title, content, keys[], secondaryKeys[], constant, position, note}]}` | 每批生成完先预览，逐条改或丢 |
| **4 一致性审查** | 蓝图 + 已生成的条目 | `{issues:[{path, level, issue, suggest}]}` | 逐条跳转修 |

硬规则：

- 阶段 3 每批**不超过 8 条**，超了分批；一批失败只重跑这一批，不推翻前面的。
- 阶段 3 的每条必须带 `keys`（2~6 个）；没带的一律不落库，提示补。
- 阶段 4 的 `issues` 必须指到具体 `entries[i].content` 或蓝图字段，说不清位置的整改建议直接丢。

规模 → Token 预算的建议（在页面上显示，别藏）：

```
小：总字数 ~1500，常驻条目 ≤ 2
中：总字数 ~4500，常驻条目 ≤ 3
大：总字数 ~12000，常驻条目 ≤ 5
```

### 3.2 条目管理器 `entry_manager.dart`

- 顶部：搜索（标题/正文/关键词）+ 类型筛选（地点/人物/势力/规则/事件/物品）+ 只看常驻 / 只看禁用。
- 列表行：`标题 · 关键词前3个 · 字数 · 触发方式（常驻/关键词/正则）· 开关`。
- 批量：多选 → 启用/禁用、改触发方式、导出选中、删除（要二次确认，删了不回来）。
- 行内动作：编辑（进 3.4 触发编辑器）、复制、AI 扩写/AI 精简、移到别的世界书。
- 排序：按 `order` 升序，手工拖拽改 order（调 `putLorebook` 整本写回）。

### 3.3 AI 世界书助手（条目级）

固定六个动作，都走 `studio_ai.dart`：

| 动作 | 输入 | 输出 | 落点 |
|---|---|---|---|
| 补全 | 标题 + 一句要求 + 世界蓝图摘要 | `{content, keys[]}` | 当前条目 |
| 扩写 | 现有正文 | `{content}`（变长，不改设定） | 当前条目候选 |
| 精简 | 现有正文 | `{content}`（压到 70%） | 当前条目候选 |
| 重写 | 现有正文 + 指令 | `{content}` | 当前条目候选 |
| 拆条 | 一段长文 | `{entries:[{title, content, keys[]}]}` | 新条目批量 |
| 冲突检查 | 本条目 + 相关条目摘要 | `{issues:[…]}` | 只提示，不改 |

"候选"= 先展示 diff，用户点「采用」才写回；同时把旧值存进版本历史（§5.1）。

### 3.4 触发规则编辑器 `trigger_editor.dart`

这是世界书的专业核心。字段全部用 **ST 原生名**，写回时不要翻译：

| 分组 | 字段 | 控件 | 说明 |
|---|---|---|---|
| 基本 | `comment`（标题）、`content`（正文） | line / block | 正文有字数提示 |
| 激活 | `constant` | 开关 | 常驻 |
| | `key`（主关键词） | 逗号分隔的标签输入 | 支持多个 |
| | `keysecondary`（次关键词） | 同上 | |
| | `selectiveLogic` | 四选一 | 0 与任一 / 1 非全 / 2 非任一 / 3 全 |
| | `selective` | 开关 | 关掉后次关键词不生效 |
| | `useRegex`（引擎侧 `use_regex`/`useRegex`） | 开关 | 正则触发 |
| | `probability` + `useProbability` | 滑块 + 开关 | 0~100 |
| 位置 | `position` | 四选一 | before_char / after_char / before_an / after_an |
| | `depth` | 数字 | 插入深度 |
| | `order` | 数字 | 优先级 |
| 递归 | `excludeRecursion` / `preventRecursion` / `delayUntilRecursion` | 三个开关 | 默认关，说明写清楚谁触发谁 |
| 分组 | `group` / `groupOverride` / `groupWeight` | 文本 + 开关 + 数字 | 互斥组 |
| 其他 | `matchWholeWords` / `caseSensitive` / `scanDepth` / `sticky` / `cooldown` / `delay` / `disable` | 开关/数字 | **默认折叠** |

交互约定：

- 一屏只露「基本 / 激活 / 位置」三组；递归、分组、其他收进「高级（默认折叠）」。
- 底部常显示：**这条现在会不会被触发**（用 `previewLorebook(id, 测试文本)`，P2 之前显示"—"）。
- 保存只写这一条的字段（整本读 → 改一条 → 整本 `putLorebook`），不要并发写整本。

### 3.5 世界关系图谱 `graph_page.dart`

```jsonc
// 存在书级 extensions.tavernlite.graph，不动 ST 字段
{"nodes":[{"id":"n1","label":"星辉学院","kind":"place","entryUid":3}],
 "edges":[{"from":"n1","to":"n2","label":"隶属","weight":1}]}
```

- 节点可以「一键生成条目」（调 3.3 补全）和「跳到条目」。
- 保存前校验：`edges` 里出现的 id 必须存在；`entryUid` 必须指向本书现有条目，否则拒绝保存并高亮那条边。
- 展示：径向布局即可，**不要引第三方图库**，用 `CustomPainter` 画线和圆点。

### 3.6 世界时间线 `timeline_page.dart`

```jsonc
// 书级 extensions.tavernlite.timeline
{"events":[{"at":"纪元 412 年","title":"学院建立","cause":"…","effect":"…","entryUid":5}]}
```

- 竖排时间轴；「因果检查」：`effect` 里提到的事件必须在它之前出现，否则标黄。
- 每个事件可「生成条目」。

### 3.7 世界书调试器 `debug_page.dart`

- 输入一段测试文本 → `previewLorebook(id, text)` → 显示：命中的条目（按注入顺序）、每条命中的原因
  （主关键词/次关键词/常驻/递归）、注入位置与深度、总 token 估算。
- 顶部三个开关：**这次扫描的深度**、**是否跑递归**、**是否计入常驻**。
- 这是唯一需要改引擎的地方（见 1.1）；接口没合入之前，这个页面先不写，别用假数据糊。

### 3.8 世界书资产库

- 多本书并存（已有）。
- 导入导出：JSON（ST 原生）；导出文件名用书名。
- 复制一本书（新 id，名字加"副本"）。
- 版本历史：见 §5.1。
- 绑定：`bindLorebooks(ids, source:, chatId/characterId/personaId:)`；UI 只做「绑到全局 / 绑到某角色」，
  聊天级绑定先不做（P3）。

---

## 4. 预设工坊

### 4.1 首页与 AI 预设生成器 `preset/workshop_home.dart`、`preset_ai_page.dart`

问卷（照参考图）：

| 字段 | 控件 | 备注 |
|---|---|---|
| 预设用途 | 单选 ×4 | 沉浸式角色扮演 / 互动小说 / 日常陪伴 / 多角色群像 |
| 描写细腻程度 | 滑块 0-100 | 只影响生成的文字，不映射 temperature |
| 剧情推进速度 | 滑块 0-100 | 同上 |
| 期望回复长度 | 三段 | 简短 / 适中 / 长篇 → 影响 `openai_max_tokens` 的建议值 |
| 额外要求 | 多行文本 | 直通 |

产出：一份 **ST 预设 JSON**，走 `importPreset(text)` 直接进「资源库 › 预设」。
生成前必须显示「将新建一个预设，约 N 字」，别默默花钱。

### 4.2 提示词编辑器 `prompt_editor.dart`

每条提示词（ST 原生字段）：

| 字段 | 控件 | 说明 |
|---|---|---|
| `identifier` | 只读 | 稳定身份，别让用户改 |
| `name` | line | 显示名 |
| `content` | block | 正文，支持 `{{char}}` `{{user}}` 等宏 |
| `role` | 四选一 | system / user / assistant / developer（引擎按能力映射） |
| `enabled` | 开关 | |
| `injection_position` | 两选一 | 0 相对 / 1 按深度 |
| `injection_depth` | 数字 | |
| `marker` | 只读徽标 | 有 marker 的条目是**占位标记**，不渲染正文 |

必须写清楚的那句话，原样进页面说明：

> **提示词模块的顺序不等于最终 API 请求的顺序。** 聊天历史、角色资料、深度注入、
> 世界书插件都会改变最终消息结构。真实顺序以「请求检视」里看到的为准。

所以这个页面右上角要有一个「查看实际请求」的入口——复用引擎已有的 `inspectTurn`
（它检视的是最近一次真实请求），**不要自己模拟一个假请求**。

其余动作：新增（从内置模板选一个起步）、删除、复制、启用/禁用、拖拽排序（`setPresetOrder`）、
单条 AI 重写、与上一版的 diff（§5.1）、单条 token 估算。

### 4.3 叙事风格设计器

人称（第一/第二/第三人称）、描写密度、对话与叙述比例、节奏（慢/中/快）、回复长度。
产出的是**提示词正文**，不是采样参数——这一点在 UI 上要写明，免得用户以为拖了滑块就会变。

### 4.4 角色扮演规则

人物自主性、玩家控制权、角色一致性、越界处理。产出同样是提示词条目。

### 4.5 剧情导演系统

冲突、配角出场、事件推进、剧情方向。可以和「世界书」联动：把导演条目写进预设，或写成世界书常驻条目——
二选一，**默认写进预设**（不污染世界书）。

### 4.6 模型参数中心

`temperature` / `top_p` / `frequency_penalty` / `presence_penalty` / `openai_max_tokens`。
每个参数：一个滑块 + 一个「恢复默认」。范围和默认值取 ST 的常规值，写进页面 helper 文案。

### 4.7 预设测试实验室

- 场景：固定 3 个测试开局（被搭话 / 冲突 / 独处），可自定义。
- 同一场景跑 A、B 两个预设，并排显示输出。
- **记录真实请求与真实用量**（模型返回的 usage），不要只让 AI 给自己打分。
- 这个页面花钱，默认折叠，跑之前显示预计 token。

### 4.8 预设资产库

列表 / 导入 / 导出 / 复制 / 重命名 / 删除 / 设为默认 / 绑定到聊天（已有）。
版本历史同 §5.1。

---

## 5. 共同底座

### 5.1 锁定与版本历史

- **锁定**：字段级 `locked`（世界书按 `entryUid + 字段名`，预设按 `identifier + 字段名`）。
  AI 动作一律跳过锁定字段，并把锁定内容作为约束喂进提示。
- **版本快照**：每次 AI 生成、批量修改、导入前，写一份
  `<app support>/studio/history/<lorebook|preset>-<id>-<毫秒时间戳>.json`，只留最近 20 份。
- **恢复**：列表页 →「版本」→ 挑一份 → 显示与当前的 diff →「恢复这一版」（恢复本身也先存一份快照）。
- **冲突**：AI 生成期间用户改了原字段 → 丢弃 AI 结果并提示「原内容已经变了，重跑一次」。

### 5.2 Token 分析

- 世界书：每条字数 → 估算 token；书级显示「常驻条目 tokens / 全部 tokens / 触发时才注入的 tokens」。
- 预设：每条提示词 tokens + 顶层参数的影响（只标，不精确）。
- 一律标注「估算」，真实用量看聊天里的 usage。

### 5.3 落点（用户明确要求的）

- 世界书：生成条目 → `putLorebook(id, json)` → 列表页立即可见（`listLorebooks()` 重新拉）。
- 预设：生成 → `importPreset(text)` → 预设列表立即可见。
- **不写进角色卡**，不调 `importCard` / `updateCharacterFields`。

---

## 6. 数据契约（给角色卡工坊留的口）

角色卡那边以后要"把这本书绑给我"，只需要：

```dart
await tavern.bindLorebooks([bookId], source: WorldInfoSource.character, characterId: id);
```

本任务书负责的是：**每本书都有稳定的 `id`，导出/导入不丢 ST 字段，绑定接口可用**。
反过来，世界书工坊**不读**卡片的任何字段（除了显示"绑定到哪些角色"需要时，才用
`bindLorebooks` 的写侧记录，P2 再说）。

---

## 7. 分阶段

| 阶段 | 交付 | 验收 |
|---|---|---|
| **P0 数据与列表** | `lorebook_draft` / `preset_draft` 纯函数层 + 单测；世界书列表页加「新建空白」「AI 创作（占位）」；预设列表页加「AI 生成（占位）」 | 新建一本空书 → 存 → 列表有 → 导出再导入 → 字段逐字节相同 |
| **P1 编辑器** | 条目管理器 + 触发编辑器（基本/激活/位置，高级折叠）；预设提示词编辑器（改/开关/排序/宏） | 改一条命中规则 → 保存 → 导出 JSON 与预期一致；预设改顺序后 `exportPreset` 顺序跟着变 |
| **P2 AI** | 四阶段向导 + 六个条目动作 + AI 预设生成器 + 落点直连列表 | 从一句创意跑到「4 条条目进书」，全程只用 `putLorebook`；生成预设后出现在预设列表并可直接绑定 |
| **P3 专业功能** | 调试器（需引擎 `previewLorebook`）、关系图谱、时间线、测试实验室、版本历史 UI | 调试器能说出"这条为什么被触发"；A/B 能并排显示并带真实 usage |

### 7.1 进度（2026-11-16）

**P0 已做一半**（只做了世界书这一侧，预设没动）：

- ✅ 世界书列表右上角 `+` 现在是二选一：**导入世界书 / 新建空白书**。
- ✅ `app/lib/tavern/lorebook_new.dart`：`newLorebookId()`（32 位十六进制，文件名安全）、
  `emptyLorebookJson(name)`（ST 原生形状，不写 scan_depth / token_budget，缺省跟全局设置）、
  `createEmptyLorebook(tavern, name:)`。
- ✅ **`putLorebook` 可以当 create 用**——engine.dart 里 `_readBookNow` 读不到只返回 null，
  紧接着 `_writeBookNow` 照写。这条已经用真引擎在宿主上测过（`app/test/lorebook_new_test.dart`，
  5 例：id 规则、空名兜底、新建即出现在列表、新书加条目读回 1 条、删一本另一本还在）。
- ✅ 设备上跑通整条链（`integration_test/app_lorebook_new_test.dart`）：
  资源库 → 世界书 → ＋ → 新建空白书 → 起名「雨港」 → 空条目页 → 加一条「码头」+ 关键词 → 保存 → 列表里能看到。
- ❌ 没做：`preset_draft`、预设那边的任何入口、AI 占位（**不摆点不动的按钮**，等 P2 真做）。


---

## 8. 测试

| 层 | 方式 | 必须覆盖 |
|---|---|---|
| 纯函数 | `flutter test test/lorebook_build_test.dart` 等 | 草稿↔ST JSON 往返、关键词/正则/常驻的写入、非法字段拒绝、条目上限、Token 估算 |
| 页面 | integration_test | 新建书 → 加一条 → 改触发 → 绑定 → 导出；预设：生成 → 改一条 → 排序 → 导出 |
| 落点 | integration_test | **AI 生成后不刷新页面也能在列表里看到**（这条最容易漏） |
| 回归 | 现有 `app_tavern_flow_test` / `app_studio_test` 必须继续过 | 证明没碰坏角色卡那边 |

---

## 9. 风险

| 风险 | 处理 |
|---|---|
| 一次生成几十条 → 又慢又贵又乱 | 四阶段 + 每批 ≤8 条 + 失败只重跑一批 |
| 世界书条目爆炸，每回合扫描变慢 | 常驻条目上限（小 2 / 中 3 / 大 5），超出就拒绝并提示 |
| ST 字段写坏，导入回 SillyTavern 打不开 | 写回只写原生字段名；导出前后各跑一次 intake 校验 |
| AI 把用户手改的内容覆盖掉 | 锁定 + 版本快照 + 版本冲突检查 |
| 两个工坊各写一套 AI | 统一走 `studio_ai.dart`，提示模板集中在一个文件里 |

---

## 10. 明确不做

- 不做云端同步、不做协作。
- 不做向量检索/embedding 世界书（ST 有，我们这版不做）。
- 不做聊天级世界书绑定（P3 之后再说）。
- 不给世界书做富文本编辑器，正文就是纯文本。
- 不引第三方图/表库。
