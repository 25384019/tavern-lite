# AI 角色工坊 · 字段级开发规格（v1）

> 目标读者：接下来真正写代码的人（Codex / DeepSeek / 人）。
> 这份文档只讲**怎么实现**，不再讨论概念。每个模块的字段、控件、AI 动作、数据结构、
> 以及"这段文字最后去哪"都写死了；照着做就不会退化成几个大文本框。
>
> 基线：`app/lib/ui/tavern/tavern_card_studio_page.dart` 已经有一个可用的
> 单页版（快速 / 高级两档、一次生成整张卡、存进书架）。本规格是在它之上做**分层**，
> 不是推倒重来：`tavernCardWish` / `tavernCardParse` / `tavernCardJson` 三个纯函数
> 继续复用，编辑器把它们的入参从"一句灵感"扩成"一份草稿"。

---

## 0. 三层架构（这是整份规格的地基）

```
创作层 StudioDraft      所有字段、所有细节，随便写多少，不心疼 token
        │
        ▼ 转换器 buildCard(draft)
卡片层 CCv3 card        description / personality / scenario / first_mes /
        │              mes_example / system_prompt / character_book / extensions
        ▼
聊天层 引擎             读的是卡片，不是草稿
```

三条铁律，任何实现都不要违反：

1. **创作层不是卡片**。九个模块的字数加起来轻松过万，全塞进 `description` 会让每回合都烧钱。
   转换器有明确的裁剪顺序（见 §11）。
2. **卡片是唯一真相**。草稿只存在卡片的 `extensions.dshgo.studio` 里（外加一份本地未保存草稿），
   导出 PNG/JSON 时跟着走，导入回来还能继续编辑。
3. **AI 是字段级的，不是整卡级的**。现有"一句灵感 → 整张卡"保留为快速创作；
   专业模式里每个字段都能单独让 AI 补/改/查，锁定字段永不被覆盖。

---

## 1. 通用数据模型

### 1.1 草稿结构（存 `extensions.dshgo.studio`）

```jsonc
{
  "v": 1,                                  // 结构版本，以后迁移用
  "updatedAt": 1731700000,                 // Unix 秒
  "modules": {
    "profile": { "fields": { "name": {...}, "age": {...} } },
    "mind":    { "fields": { ... } },
    "bond":    { ... }, "history": { ... }, "world": { ... },
    "voice":   { ... }, "scene": { ... }, "rules": { ... }, "soul": { ... }
  },
  "graph": { "nodes": [], "edges": [] },
  "engineering": { "tokenBudget": 1200, "format": "ccv3", "bookId": null }
}
```

### 1.2 单个字段

```jsonc
{
  "text": "二十四岁，短发，左手腕有一道旧疤。",   // 主文本，字符串或字符串数组（按字段声明）
  "locked": false,                                // 锁定：AI 不能改
  "source": "manual",                             // manual | ai | ai-edited
  "history": ["上一版", "上上版"],                 // 撤销栈，最多 10 条，只存文本
  "updatedAt": 1731700000
}
```

- `locked` 的字段在**任何** AI 动作里都是只读输入（作为上下文），不是可写目标。
- `history` 是"撤销修改"的唯一实现，不搞全局 undo 栈：字段级撤销更符合直觉。
- 数组型字段（标签、时间线、关系边）用 `List<String>` 或 `List<Object>`，规则同上。

### 1.3 字段的控件类型（前端只需要这六种）

| 类型 | 控件 | 用于 |
|---|---|---|
| `line` | 单行 TextField | 姓名、年龄、职业、口头禅 |
| `block` | 多行 TextField（min 2 / max 8） | 外貌、性格、背景 |
| `tags` | 可输入的多选胶囊（现有 `CapsuleChoiceChip` + 自定义项） | 爱好、性格标签、关键词 |
| `list` | 可增删的行（每行 = `line` 或 `block`） | 重要事件、开场白、示例对话 |
| `pair` | 左右两栏（窄屏上下） | 字段成对出现时（年龄+性别） |
| `readonly` | 只读展示 + 复制 | 转换器产出的预览、token 统计 |

### 1.4 每个字段行固定有四个动作

```
┌ 字段名 ────────────────────────────────  🔒  ↺  ✨ ┐
│ [ 文本……                                      ] │
└──────────────────────────────────────────────────┘
   🔒 锁定（锁上后 ✨ 变灰，撤销仍然可用）
   ↺ 撤销（history 非空才可点，一步退回上一版）
   ✨ AI（按住弹出五个动作：补全 / 扩写 / 精简 / 重写 / 检查）
```

- **补全**：字段为空时用。按模块上下文写一版。
- **扩写**：在原文基础上变长，保留已有设定，不推翻。
- **精简**：压到原来的 50%~70%，只留能进卡的内容。
- **重写**：弹一行输入框收指令（"更冷一点""改成第一人称"），按指令重写。
- **检查**：不改文本，返回问题列表（见 §1.6），点条目跳到对应字段。

### 1.5 AI 调用协议（一个函数覆盖全部）

```dart
Future<StudioAiResult> studioAsk({
  required StudioDraft draft,
  required String moduleKey,      // profile / mind / ...
  required String fieldKey,       // 目标字段；null 表示整模块
  required StudioAiAction action, // fill|expand|trim|rewrite|check|generateModule
  String instruction = '',        // 重写时的指令
});
```

- 一次调用 = 一次 `TavernModelClient.generate`（现有 `tavernModelClientProvider`），
  不新建连接层、不走聊天引擎。
- 输出的 JSON 结构固定：

  ```jsonc
  // fill / expand / trim / rewrite / generateModule
  { "fields": { "appearance": "…", "habits": ["…"] } }

  // check
  { "issues": [ { "path": "mind.fear", "level": "warn",
                  "issue": "写的是怕黑，但人生经历里说她从不怕黑",
                  "suggest": "改成怕被留下" } ] }
  ```

- 提示里必须带：**当前模块已填内容 + 锁定字段 + 全局摘要（姓名/世界观/关系各一行）**。
  不带全局摘要，模块之间就会互相打架。
- 返回的 `fields` 只写**未锁定**且**在本次目标范围内**的键；多余的键丢弃，
  缺的键保持原值（部分成功比整体失败好）。
- 解析失败 → 原文弹窗 + 不落库（沿用现有"不猜"策略）。

### 1.6 字段级校验（本地，不花 token）

在任何 AI 之前先跑一遍规则，能挡掉一半的常见错：

| 检查 | 规则 | 提示 |
|---|---|---|
| 必填缺失 | `name` 为空 | 存卡前必须填 |
| 超长 | 单字段超过它的 `budget` | 显示"预计 N 字，建议压到 M 字" |
| 与锁定冲突 | AI 返回覆盖了锁定字段 | 直接丢弃，记一条日志 |
| 关系断裂 | 关系图谱里的人名在世界书里没有对应条目 | 提示补条目 |

---

## 2. 模块 01 人物档案 `profile`

**目标**：把"这个人是谁"填满，且每个字段都能单独让 AI 写。

**子页面**：`StudioProfilePage`，三组卡片：基本信息 / 外观 / 能力与弱点。

| 字段 key | 中文名 | 类型 | 必填 | 预算(字) | 去向 |
|---|---|---|---|---|---|
| `name` | 姓名 | line | ✅ | 12 | 卡片 `name`（直通） |
| `nickname` | 昵称 | line | | 12 | 卡片 `nickname` |
| `age` | 年龄 | line | | 8 | description（"二十四岁"） |
| `gender` | 性别 | tags(单选) | | 4 | description |
| `species` | 种族 | line | | 12 | description（非人类才写） |
| `appearance` | 外貌 | block | ✅ | 160 | description 第一段 |
| `body` | 体态细节 | block | | 120 | description（表情/体味/习惯动作） |
| `identity` | 身份职业 | line | | 20 | description 第二段开头 |
| `likes` | 爱好 | tags | | 60 | personality 或 description |
| `habits` | 生活习惯 | block | | 120 | personality |
| `ability` | 能力 | block | | 120 | 世界书条目「能力：X」 |
| `weakness` | 弱点 | block | | 100 | personality / 世界书 |

**AI 动作**
- 整模块「补全」：输入只有姓名+一句灵感时，生成上面除 name 外的全部。
- 单字段「补全/扩写」：常用在外貌、习惯。
- 「随机设定」：一次生成 3 组互不相同的 `likes`+`habits`，让用户挑（卡片式三选一）。

**去向说明**：`ability`/`weakness` 不进 description，避免开局就把底牌亮出来；
做成世界书条目，关键词触发时才注入。

---

## 3. 模块 02 深度人格 `mind`

**目标**：让模型"知道她为什么会这样"，而不是只会背性格标签。

| 字段 key | 中文名 | 类型 | 预算 | 去向 |
|---|---|---|---|---|
| `surface` | 表层性格 | tags(多选) | 40 | personality |
| `inner` | 内在性格 | block | 160 | personality 后半 |
| `values` | 价值观 | block | 100 | description 尾段 / 系统提示 |
| `desire` | 欲望 | block | 80 | 灵魂档案 |
| `fear` | 恐惧 | block | 80 | 灵魂档案 |
| `flaw` | 缺陷 | block | 80 | personality |
| `trigger` | 情绪触发 | list | 120 | 行为规则条目 |
| `defense` | 防御机制 | block | 100 | 行为规则条目 |

**AI 动作**
- 「心理逻辑推演」：给 `surface` + `fear`，让 AI 反推 `inner`/`defense`，并说明推导链（只展示，不落库）。
- 「性格矛盾检查」：对比 `surface` 与 `inner`，输出可能是刻意反差（OK）还是写崩了（要改）。

**联动**：`fear`/`desire` 会喂给模块 07 的剧情方向与模块 08 的行为规则。

---

## 4. 模块 03 玩家关系 `bond`

| 字段 key | 中文名 | 类型 | 预算 | 去向 |
|---|---|---|---|---|
| `initial` | 初始关系 | line（现成项 + 自填） | 20 | scenario |
| `impression` | 彼此印象 | block | 120 | scenario |
| `trust` | 信任度 | 滑块 0-100 | — | 元数据 + 状态初始值 |
| `intimacy` | 亲密边界 | tags | 60 | 行为规则 |
| `conflict` | 关系冲突 | block | 120 | 剧情背景 |
| `growth` | 关系变化规则 | list | 160 | 世界书条目「关系规则」 |

**AI 动作**：「生成关系发展规则」——输入初始关系+双方性格，输出 3~5 条
可被关键词触发的推进条件（"当 {{user}} 主动道谢时，信任 +1"）。

**联动**：`growth` 与世界书绑定，聊天里命中关键词时由引擎注入。

---

## 5. 模块 04 人生经历 `history`

| 字段 key | 中文名 | 类型 | 预算 | 去向 |
|---|---|---|---|---|
| `family` | 家庭背景 | block | 140 | description 摘要 |
| `upbringing` | 成长经历 | block | 140 | description 摘要 |
| `timeline` | 重要事件 | list{age,event,impact} | 200 | 世界书（每事件一条） |
| `secret` | 秘密 | block | 120 | 世界书（关键词触发） |
| `memory` | 回忆 | block | 100 | 世界书 / 开场可用 |
| `goal` | 人生目标 | block | 80 | 灵魂档案 |

**AI 动作**
- 「生成时间线」：给定年龄与关键事件，补全成 `0/6/12/18/现在` 的因果关系链。
  输出必须带 `impact`（"因为 X，所以现在 Y"），否则不许落库——这条是防注水的硬规则。
- 「因果分析」：检查时间线里有没有"结果早于原因"。

---

## 6. 模块 05 世界与背景 `world`

| 字段 key | 中文名 | 类型 | 预算 | 去向 |
|---|---|---|---|---|
| `era` | 时代 | line | 20 | 世界书「背景」 |
| `geography` | 地理 | block | 160 | 世界书 |
| `factions` | 组织势力 | list{name,goal,attitude} | 200 | 世界书（每势力一条） |
| `society` | 社会制度 | block | 140 | 世界书 |
| `places` | 重要地点 | list{name,desc} | 200 | 世界书（每地点一条） |
| `rules` | 世界规则 | list | 160 | 世界书（常驻条目） |

**AI 动作**：「一键生成世界书」——按规模（小型 5-10 条 / 标准 15-30 条 / 大型 40-80 条）
产出条目数组，每条带 `keywords`（2~6 个）、`content`（80~200 字）、`constant`（是否常驻）。
落地用现有的 `addCharacterBookEntry`。

**联动**：`factions`/`places` 的名字进关系图谱，也进 §10 的冲突检测。

---

## 7. 模块 06 对话与文风 `voice`

| 字段 key | 中文名 | 类型 | 预算 | 去向 |
|---|---|---|---|---|
| `tone` | 说话语气 | tags | 30 | personality |
| `wording` | 措辞习惯 | block | 120 | personality |
| `catchphrase` | 口头禅 | list | 40 | personality |
| `action` | 动作描写风格 | block | 100 | mes_example 的写法 |
| `emotion` | 情绪表达 | block | 100 | personality |
| `samples` | 示例对话 | list{pair} | 300 | mes_example |
| `firstMes` | 开场白 | block | 260 | first_mes |

**AI 动作**
- 「多场景试演」：给同一角色写 3 段不同处境（被搭话 / 被冒犯 / 独处）的台词，
  用来检验语气是否稳定；用户选一段作为 `samples`。
- 「对话模仿」：拿 2 段现有 `samples` 当范本，写第 3 段。

---

## 8. 模块 07 情节与场景 `scene`

| 字段 key | 中文名 | 类型 | 预算 | 去向 |
|---|---|---|---|---|
| `meeting` | 初遇 | block | 140 | scenario |
| `backdrop` | 剧情背景 | block | 160 | scenario |
| `tension` | 核心矛盾 | block | 120 | scenario 尾 |
| `direction` | 剧情方向 | list | 120 | 世界书「导演提示」 |
| `openings` | 多开场白 | list(block) | 3×260 | first_mes + alternate_greetings |

**AI 动作**：「设计事件与分支」——按 `tension` 给 3 条走向（缓和/激化/反转），
每条附 2 个可触发的关键词。

---

## 9. 模块 08 行为与扮演规则 `rules`

| 字段 key | 中文名 | 类型 | 预算 | 去向 |
|---|---|---|---|---|
| `autonomy` | 角色自主性 | tags | 40 | system_prompt |
| `knowledge` | 知识边界 | block | 140 | system_prompt（"你不知道 X"） |
| `principles` | 行为原则 | list | 160 | system_prompt |
| `interaction` | 互动规则 | list | 140 | post_history_instructions |
| `consistency` | 一致性要求 | list | 120 | post_history_instructions |

**AI 动作**：「生成行为规则」——从模块 02 的性格与模块 04 的经历反推，
输出必须是**可判定的句子**（"不会主动提自己的过去"可以；"性格冷漠"不行）。

---

## 10. 模块 09 角色卡工程 `engineering`

不是页面上的文字，是"交出去之前"的那一关。子页面 `StudioEngineeringPage`。

| 项 | 说明 |
|---|---|
| Token 预算 | 目标 `description` + `personality` + `mes_example` 总预算（默认 1200 token），实时条 |
| 预览 | 转换器产出的卡片全文，只读，可复制 |
| 世界书绑定 | 显示将要写入的条目数、常驻条目数、预计 token |
| 格式 | CCv3（默认）/ CCv2 / 纯 JSON |
| 版本 | `character_version` + 本地草稿版本号 |
| 试聊 | 直接开一个临时聊天，不进书架（发 `first_mes` 试一段） |

**转换器 `buildCard(draft) → Map<String,Object?>`**：纯函数，放
`app/lib/tavern/tavern_studio_build.dart`，必须能单测。规则见 §11。

---

## 11. 转换器：创作层 → 卡片层

### 11.1 字段映射（按顺序拼 description）

```
description =
  外观（profile.appearance，最长 160 字）
+ 身份（profile.identity / age / species）
+ 性格（mind.surface → 一句，mind.inner 摘要）
+ 关系（bond.initial + bond.impression，1~2 句）
+ 经历（history.family + history.upbringing，各压到 60 字内）
+ 缺陷（mind.flaw）
```

`personality` = `mind.surface` + `voice.tone` + `voice.wording` + `profile.habits`，
总长压到 200 字内。

`scenario` = `scene.meeting` + `scene.backdrop` + `scene.tension`，压到 150 字内。

`first_mes` = `voice.firstMes`（若空则 `scene.openings[0]`）。
`alternate_greetings` = `scene.openings[1..]` + 用户在模块 07 里标星的。

`mes_example` = 最多 2 段 `voice.samples`，每段前加 `<START>`。

`system_prompt` ← `rules.*`；`post_history_instructions` ← `rules.interaction/consistency`。

`character_book.entries` ← `world.*` + `history.timeline/secret` + `profile.ability/weakness`
+ `bond.growth`（每条：`keys` 来自 AI 给的 keywords，`content` 是该字段正文，
`constant` 只有 `world.rules` 为 true）。

`extensions.dshgo.studio` ← 整份草稿（含未进卡的字段），导出/导入跟着走。

### 11.2 超预算时的裁剪顺序（先砍最不痛的）

1. `mes_example` 从 2 段砍到 1 段；
2. `history` 段落压到 40 字；
3. `mind.inner` 只留一句；
4. `bond.impression` 整段移除；
5. 仍超 → 拒绝保存并提示，不静默截断（截断会写出半句话的卡）。

### 11.3 不进卡片的东西

- `desire` / `fear` / `goal`（灵魂档案）→ 只存 extensions，聊天时由剧本/导演按需注入；
- 时间线的 `impact` 说明 → 只存元数据；
- 所有 `history` 栈 → 只存元数据，导出时可剥掉（提供一个"干净导出"开关）。

---

## 12. 三个附加系统（可以晚做，但要留位置）

### 12.1 角色灵魂档案 `soul`

字段：`motive`（核心动机）、`constants`（不可改变的特质，tags）、`conflict`（内在冲突）、
`growth`（成长方向）。四行，都 `block`。
它的作用不是进卡，而是**作为所有 AI 动作的隐藏约束**：每次生成都把它放进提示。
UI 上是一个固定在编辑器顶部的折叠条（"灵魂：想被需要 · 不会主动求人"）。

### 12.2 角色关系图谱 `graph`

```jsonc
{ "nodes": [ {"id":"player","label":"{{user}}","kind":"user"},
             {"id":"n_lan","label":"阿岚","kind":"npc","bookEntryId":"..."} ],
  "edges": [ {"from":"n_lan","to":"player","label":"前同事","trust":40,"conflict":"旧账"} ] }
```

- 节点可一键生成世界书条目（`kind: npc` 的默认常驻关、关键词开）。
- 边上不能有节点不存在的 id：保存前校验，报错不落库。
- 展示用最朴素的力导向或径向布局即可，不要引入重型图库。

### 12.3 角色行为模拟器 `simulator`

给 3 个内置测试场景（被搭话 / 被冒犯 / 被要求做违背原则的事），
用当前卡片真跑一次短对话，输出判定：
`像不像这个人（1-5）` + `哪里不像（引用具体台词）` + `建议改哪个字段`。
它花真钱，所以：默认关闭、每次跑之前显示预计 token、跑完把建议写进"检查"列表。

---

## 13. 分阶段实施计划

### P0 · 骨架（不动 AI，先把地基和转换器做对）

- `StudioDraft` 数据类 + JSON 读写 + 存进 `extensions.dshgo.studio`（写一个往返单测）。
- 字段控件六种 + 锁定/撤销（widget 测试）。
- `buildCard(draft)` 转换器 + 裁剪顺序（纯单测，这是最关键的一份测试）。
- 编辑器外壳：模块列表页 → 模块子页（先只放字段，先不接 AI）。
- 验收：手填一份草稿 → 预览 → 存成卡 → 导出 → 再导入 → 草稿还在。

### P1 · 四个模块接上 AI

- `studioAsk` 协议 + 五种动作 + 锁定保护 + 检查结果列表。
- 接模块 01 人物档案、02 深度人格、06 对话与文风、07 情节与场景。
- 验收：每个字段的五个动作都能跑通；锁定字段在"整模块生成"后一字不变；
  解析失败的原文能弹出来；单测覆盖提示组装（该带的上下文都在、锁定的不在可写目标里）。

### P2 · 世界书与经历

- 模块 05 一键生成世界书（规模/内容勾选）+ 落地到 `character_book`。
- 模块 04 时间线生成 + 因果检查 + 模块 03 关系规则。
- 验收：生成 15 条条目后，卡片的 `character_book.entries` 有 15 条、关键词非空；
  同一份草稿重复生成不会产生重复条目（按名字去重）。

### P3 · 三个附加系统 + 一致性

- 灵魂档案（约束注入）、关系图谱（含校验）、模拟器（3 场景）、全局一致性检查。
- 验收：图谱有悬空 id 时保存被拒并指出是哪条；模拟器跑完能给出可点击的字段建议。

---

## 14. 明确不做的事（避免越做越散）

- 不做云端同步、不做多人协作编辑。
- 不做"AI 自动把整本小说拆成角色卡"（这是另一个功能）。
- 不引入新的富文本编辑器；字段就是纯文本，`action`/`*动作*` 靠约定不靠控件。
- 不为每个模块单独设计一套视觉；沿用现有 `SettingsSection` / `FormFieldBlock` /
  `CapsuleChoiceChip` / `SegmentedPill`，新页面只在信息密度上做区别。
- 不把九个模块一次性塞进一个页面。一页一模块，返回列表页。

## 15. 风险与已知取舍

| 风险 | 处理 |
|---|---|
| 字段太多，用户不知道从哪开始 | 保留"一句灵感 → 整卡"的快速档；专业模式提供"先随便生成，再逐字段改" |
| 每个字段都能 AI，容易点出几十次调用 | 整模块生成优先；字段级 AI 是补充。生成前显示预计 token |
| 草稿存进 extensions 会让卡片变大 | 干净导出开关；草稿分区压缩（只存非空字段） |
| 世界书条目太多拖慢每回合 | 默认常驻条目 ≤ 3 条；工程页显示"常驻 token 预估" |
| 转换器规则改动会悄悄改变老卡 | `buildCard` 带 `v` 版本号，老版本草稿按旧规则转换 |
