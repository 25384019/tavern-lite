# 交接：Tavern Lite（DSH Go 酒馆模块独立 App）

新会话从这里接。这份文件是当前进度的唯一真相，不要凭记忆推断。

## 0. 这一轮（2026-11-16 下午，按 `docs/一体化执行任务书.md` 开工）

| 任务书条目 | 状态 |
|---|---|
| §1.1 状态卡对话「上下文超限」 | **主人已解决**（设备上那条会话已能正常回复，见 `docs/shelf-state-card.png` 与聊天页的用量行） |
| §1.2 状态标题 | **已做并真机验证**：`tavern/tavern_state_hints.dart` 的 `tavernStateLabel(s)`，schema 的 `title`/`x-dsh-title` 优先，同层撞名补键名（`心情（mood）`），嵌套按 JSON Pointer 找 |
| §1.3 状态类型化编辑 | **已做并真机验证**：`ui/tavern/tavern_state_editor.dart`，数字（min/max/step + ± 键）、枚举（选项）、布尔（开关）、列表（条目增删）、文本；任何情况都有「直接编 JSON」；非法输入留在面板上解释且**不写入** |
| §1.5 递归组合互斥 | **已做**：核实出引擎语义与 ST 同名选项**方向相反**（见下），`tavernRecursionConflict()` 挡住「只在递归里出现 + 递归里跳过」这对死组合，界面文案改成描述引擎真实行为 |
| **审查修复（小宅酱 2026-11-16 16:0x 那批）** | **5 条全修完并补了测试**，见下表 |
| §2 角色 AI 工坊 P1–P3 | **P1 + P2 已做并真机验证**；**草稿持久化与「从已有卡读回/写回」已做并真机验证**（见 §2 底座）；**P3（灵魂档案当约束/关系图谱/三场景模拟器）没做** |
| §3 状态模板 + AI 制卡 | **闭环已做并真机验证**（见 §3 落地）：资源库 › 状态模板（新建/编辑/删除、逐项增删改、应用到卡）；专业创作里「状态」一行可**选模板**或**让 AI 按角色设计**（先看候选、采用才写），存的卡直接带 `extensions.dshgo.state` |
| §4 世界书工坊全量 | **AI 四阶段 + 条目搜索/批量 + 条目级 AI + 调试器 + 版本快照** 都已做并真机验证；剩下图谱、时间线 |
| §5 预设工坊 | **新建 / 复制 / 编辑 / 删除 / 设为默认 / 导出 + 提示词 AI 辅助 已做并真机验证**；**参数分组编辑、A/B 对比、版本历史没做** |
| §6 验证与交付 | 单测 **147 例**全过；设备集成测试跑过 12 个文件；`flutter analyze` 0 error。**真 Key 已验证一条完整链路**（见下「真模型验证」）。三个包已重打（2026-11-16 20:5x 带截断修复）并装到雷电。用户说明见 `docs/使用说明.md`。 |

### 真模型暴露的两个问题（2026-11-16 21:0x，主人实测）

**1. AI 制卡有回复、不出预览。**
第一次真请求时是「JSON 被 max_tokens 截断」——已修（`tavernCardRepair`）。
第二次（中文灵感「灯塔看守人」）仍然不出预览。最可能的原因：**中文提示下模型把键名也翻译了**
（`名字` / `描述` / `开场白`），而 `_normalize` 只认英文键 → 没有 `name` → 整张卡被判失败。
修法：
- `_fieldAliases` + `_field()`：每个字段认一批别名（中文、camelCase、ST 变体），
  再不行做大小写不敏感匹配。
- 名字缺失但描述/开场白有内容 → 给占位名「未命名角色」（能看到、能丢弃），不再整份作废。
- 单测补 4 例（中文键、camelCase、缺名字、全空）。

**2. 世界书刚存完，列表还是空的。**
世界书工坊保存后只写了引擎，没让列表的 provider 失效。修法：`putLorebook` 之后
`ref.invalidate(tavernLorebooksProvider)`。（列表是另一个 `FutureProvider.autoDispose`，
不主动刷新就还是缓存里的旧结果。）

### 内置内容（2026-11-16 23:0x，随包分发）

主人给了两批素材：`C:\暑期项目\nixiangdu\worldbooks\_top15_按下载量\`（15 本 ST 世界书 JSON）
和微信目录里的 `20261116-223542.zip`（3 张 PiuPiuCard 角色卡 PNG）。

- **先验证再用**：`test/bundled_content_test.dart` 用真引擎把 15 本 + 3 张全部导入一遍，
  15/15、3/3 都能读，条目数也对（最大一本 78 条）。这条测试留在仓库里，以后换素材先跑它。
- **打包方式**：素材放 `app/assets/bundled/`，磁盘名改成安全的 `wb01.json` / `card01.png`
  （原文件名带全角括号、感叹号、假名，Windows 上 Flutter 拷资源会 `errno 123` 直接构建失败），
  显示名放进 `assets/bundled/manifest.json`。**manifest.json 必须单独在 pubspec 里声明**，
  只声明目录不会带上它（踩过：页面上显示 0 本）。
- **入口**：资源库 › **内置内容** → 列出 15 书 + 3 卡 → 「全部装进来」。
  按名字去重，点几次都不会重复；装完 `invalidate` 世界书和角色卡两个 provider，列表立刻更新
  （和世界书工坊那个刷新 bug 同类，一起修了）。
- 真机验证：装完 `lorebooks/` 17 个（2 原有 + 15），`characters/` 5 个（2 + 3，卡图也在），
  资源库显示「世界书 17 本」、书架的角色区能看到 3 张新卡的图。
  证据：`docs/bundled-content-library.png`、`docs/bundled-content-shelf.png`。
- APK 从 36.6 MB 涨到 41.2 MB（+3.4 MB 素材），在可接受范围。

### AI 制卡「有回复不出预览」的完整结论（2026-11-16 22:1x，三次真机复测后定案）

不是单一原因，是**两个叠在一起**：

1. **解析层真失败过**（第一次「陈叔」那次）：回复被 max_tokens 截断。→ 加 `tavernCardRepair`。
2. **解析其实成功了，但预览在页面下方、没有自动滚动**（第二、三次「陆怀灯 / 陈望海」）。
   主人两次都说"没有进入预览"，同一句原文在单测里解析得好好的（`test/real_model_reply_2_test.dart`
   用的是截图里那一段），说明卡是有的，只是**渲染在折叠线以下**，用户以为没生成。

修法（按顺序都做了）：
- 解析加固：内层引号转义（`口头禅是"嗯"`）、**不再拿最后一个 `}` 当 JSON 结尾**（`{{user}}` 里的 `}`
  会把后面的字段整段切掉——这是第二次失败的真凶）、按键名兜底扫描、字段别名（中文/camelCase）。
- **生成成功自动滚到预览**：`Scrollable.ensureVisible(_previewKey)`，用户不用自己往下找。

真机确认（2026-11-16 22:1x，DeepSeek 真 Key）：
「a lighthouse keeper on a lonely island」→ 自动滚到预览「沈海潮，五十三岁，孤岛灯塔看守人」，
标签 6 个、描述/性格/两条备选开场/示例对话全在（性格里的 `口头禅是"嗯"和"不急"` 也保住了）
→ 存进书架 → `characters/card-ade54264…` 落盘。用量 1254 tokens · ¥0.0043。
证据：`docs/real-ai-card-preview-2.png`。

### 真模型验证（2026-11-16 21:00，主人填好 Key 后）

**跑通的**：酒馆 › 书架 › AI 制卡 → 一句英文灵感 → **真实 DeepSeek 请求** → 流式输出 → 预览
（「陈叔」，52 岁拉面店老板，标签 拉面店/日常/固执/短句/深夜食堂，描述里正确用了 `{{user}}`）
→ 存进书架 → 落盘 `files/tavern/characters/card-31b283…` → **重启 app 后书架还在**。
用量行显示「这次用了 938 tokens · ¥0.0029」。

证据截图：`docs/real-ai-card-preview.png`（预览）、`docs/real-ai-card-saved.png`（存好的编辑页）、
`docs/real-ai-truncated-raw.png`（第一次失败时的「模型原文」）。

**真模型一上来就暴露了一个真 bug**：第一次请求失败了，点「模型原文」看到模型其实写了完整卡片 JSON，
但**结尾被 max_tokens 截断**（`"creator_notes": "…"` 后面还挂着个 `、`），`jsonDecode` 整份拒绝。
修法：`tavern_card_studio.dart` 加 `tavernCardRepair()`——括号栈 + 引号状态扫描，退到最后一个完整的值
再补上还开着的括号；补不了才认失败。补了 5 例单测（半个字符串+悬空顿号 / 半个 key / 半个数组项 /
不是 JSON 别硬修 / 完整 JSON 不动）。修完重跑同一条请求就成功了。

**还没用真 Key 验的**：专业创作的字段级 AI、世界书四阶段、状态方案、预设提示词 AI、三场景试演。
它们和 AI 制卡共用同一套传输层与「先给候选」的流程，但提示词形状不同，**不能用制卡的成功代替**。

### 还没做的（据实）

| 项 | 说明 |
|---|---|
| **真实 Key 端到端** | 所有 AI 功能都只用 `MockClient` 验证过接线与解析，**没有用真模型跑过**。这是最该补的一条。 |
| §2 P3 的图谱/模拟器 | 灵魂档案当约束**已做**（进提示），三场景试演**已做**（`studio-simulate`），**关系图谱没做** |
| §4 图谱 / 时间线 / 版本历史 | 没做（任务书的扩展项） |
| §5 参数分组编辑 / A/B / 版本历史 | 没做（扩展项） |
| 状态 rules（每回合自动改数值） | 只做了定义 + 初始值，规则没接 |
| 卡内世界书删除条目 | 引擎只给了 `addCharacterBookEntry`，补条目可以，删不行 |

### 审查那批 5 条的修法（2026-11-16 下午）

| # | 问题 | 修法 | 测试 |
|---|---|---|---|
| 1 | 编辑世界书可能丢掉递归层级（把 `delayUntilRecursion` 当布尔读，2 会变 false） | `tavern_book_entry.dart` 加 `tavernBookRecursionLevel` / `tavernBookRecursionValue`：读的时候 `true`→1、数字原样；写的时候**原来是什么形状就还写什么形状**。编辑页把它从开关换成 0–10 的层级步进器 | `tavern_book_entry_test.dart` 3 例（读、写、只改名字不动层级） |
| 2 | 提示里只有中文名，解析器只认英文键 → 真实模型的中文键全被丢 | 提示里显式列出「键（中文名）」，输出形状也用真键；解析时按中文名反查回键；整模块还会列出**待填空字段的键** | `tavern_studio_ai_test.dart` 3 例（键在提示里、整模块只列空的、中文名能对回） |
| 3 | 整模块可能覆盖已写内容 | 解析（解 `wholeModule` 时跳过非空）**和**采用（`onlyEmpty`）两道闸 | 单测 2 例，真机那条「整模块」也顺带覆盖 |
| 4 | 取消重写仍然发请求 | `_askFor` 里 `asked == null` 直接 return | 真机新测试：用 `calls` 计数证明**一次请求都没发** |
| 5 | 全局摘要读的是不存在的 `world.area` | 改成 era / geography / society / places | 提示组装测试里断言摘要带地理 |

另外两件：

- **扫描深度**：审查说得对，引擎里 `effectiveDepth <= 0` 直接返回空串（不匹配），`0` **不等于**「用全局」。
  文案已改成「不填 = 用全局；填 0 = 这条永不按关键词匹配」。没有改引擎语义（那会动到别人的书）。
- **`extensions` 合并层级**：`updateCharacterData` 原来只合一层，写 `dshgo.studio` 会把 `dshgo.state` 冲掉。
  改成两层：命名空间内再逐个键合并。`studio_roundtrip_test.dart` 5 例（含「state 要留着」）。

### §2 P1 的落地（AI 接线）

- `tavern/tavern_studio_ai.dart`：`studioAiMessages`（提示）、`studioAiBody`（请求体）、
  `studioAiParse`（解析 + 过滤）、`studioAiApply`（写入）。
- `ui/tavern/tavern_studio_page.dart`：字段右上角 ✨（五动作）、模块页右上角整模块生成、
  候选面板（旧的划掉 + 新的）、采用/丢弃、tokens 与 ¥。
- 护栏（都在解析层，不靠界面自觉）：只收本模块的键、字段动作只收目标字段、
  **锁定字段一律丢弃**、空值丢弃；解析失败只提示「模型这次没给出能用的内容」，不落库。
- 验证：`test/tavern_studio_ai_test.dart` 13 例；
  `integration_test/app_studio_ai_test.dart` 5 条真机（补全/整模块/检查/回废话/世界书），
  用 `MockClient` 顶掉传输层——不花钱、不要 Key，但走的是真的 client、真的提示、真的界面。

### §3 落地（状态模板 + 制卡带状态）

- `tavern/state_templates.dart`：`StateTemplate` / `StateField`（数字/文本/布尔/枚举/列表，
  带初始值、范围、选项、隐藏），`toState()` 折成卡片的 `{schema, init}`，`fromState()` 把老卡读回来；
  `stateTemplateIssues()` 自检（空键/重复/非法字符/范围反了/枚举没选项）；`StateTemplateStore` 一个 JSON 文件。
- `ui/state/state_templates_page.dart`：资源库入口 → 列表（新建/编辑/删除/**应用到角色**，覆盖前先问）。
- `ui/state/state_template_edit_page.dart`：模板名 + 状态项增删改（每项一个面板）。
- 专业创作：`StudioDraft.state` + 转换器写进 `extensions.dshgo.state`；列表页「状态」一行 →
  选模板 / AI 设计（`StudioAiAction.state`，先预览后采用）/ 不要状态。
- 验证：`test/state_templates_test.dart` 11 例、`tavern_studio_ai_test.dart` 状态三例、
  `tavern_studio_test.dart` 转换器两例；真机
  `integration_test/app_state_template_test.dart`（建模板→应用→卡里读回）和
  `app_studio_state_test.dart`（选模板存卡 / AI 方案存卡）都通过。

- 条目管理（`ui/tavern/tavern_library_book_page.dart`）：顶部搜索框按**名字 / 关键词 / 正文**过滤；
  右上角「选择」进入批量模式 → 全选 / 取消全选 / 批量启用 / 批量停用 / 批量删除（删除要确认，
  并且**从大 index 往小删**，否则后面的条目会前移错位）。
- 验证：真机 `integration_test/app_library_book_batch_test.dart`：3 条 → 搜「码头」只剩 1 条 →
  全选停用（引擎里三条 `disable` 都是 true）→ 清空选择 → 单选一条删除 → 剩 2 条。

- 条目级 AI（`ui/tavern/tavern_lorebook_page.dart` 的内容格子右上角 ✨）：写长 / 精简 / 按说明重写 /
  给几个关键词。前三个先出候选，采用才改这一格；「给关键词」直接把 2~6 个词填进关键词框。
  提示与解析在 `tavern/lorebook_ai.dart`（`lorebookEntryAiMessages` / `aiProseParse` / `aiKeysParse`）。
- **查清了一件事**：上一轮说「点条目行打不开编辑页」是**测试写错了**，不是产品 bug。
  重复 `pumpWidget` 留下旧树、以及 ✨ 按钮在折叠区外没先 `ensureVisible` 就点（点落空，还会误触返回把页面弹掉），
  都会造成「页面没开」的假象。按正常路径（点行 → 进编辑页 → 滚到 ✨ → 点）跑通了：
  写长 → 采用 → 保存 → 引擎里那条 `content` 变了（`integration_test/app_lorebook_entry_ai_test.dart`）。

### §5 落地（预设工坊的第一段）

- `tavern/preset_new.dart`：`emptyPresetJson()` / `createEmptyPreset()` / `duplicatePreset()`。
  引擎没有 create，只有 `importPreset`；**列表里的名字取的是文件名**，所以名字要同时写进 JSON 和 fileName
  （踩过：只写 JSON 会得到满屏叫 "preset" 的预设）。
- 预设页：右上角 ＋ 新建空白（弹窗起名，建完直接进编辑页）、条目菜单多「复制一份」；
  编辑/删除/设为默认/导出用的是原来就有的那套。
- 验证：`test/preset_new_test.dart` 6 例（建、兜底名、改参数与主提示后读回、复制、删、设默认，全跑真引擎）；
  真机 `integration_test/app_preset_new_test.dart`：新建 → 引擎里有 → 列表里有 → 复制 → 两份。
- 顺手修：弹窗里的 `TextEditingController` 原来在 `await` 之后就 dispose，退场动画还会用到它 →
  改成弹窗自己是个 StatefulWidget，在 `dispose()` 里释放。

- `tavern/preset_ai.dart`：写/扩写/精简一条提示词的提示与解析。
  **两种回答都收**：JSON 的 `content`，或者模型直接回的整段话（去掉围栏）。
- 提示词面板里那颗 ✨：选动作 → 问一句想要什么（可留空）→ 出候选 → 采用才写进这一条并走
  原来的 `updatePresetPrompt` 保存；丢弃就什么都不发生。取消不发起请求。
- 验证：`test/preset_ai_test.dart` 8 例（JSON / 围栏 / 散文 / 空）；真机
  `integration_test/app_preset_ai_test.dart`：✨ → 从头写 → 采用 → 引擎里那条 `content` 变了。

### §4 版本快照（2026-11-16 晚）

- `tavern/version_store.dart`：资产历史（`<support>/versions/<kind>/<id>/`，一版一个文件 + 索引），
  每份资产最多留 20 份，超了连文件一起丢掉最旧的；索引坏了当没有，不影响正本。
- 世界书页右上角「版本」：**存一份快照**（可手点，也能在改动前先存）、按时间列出（带体积）、
  **回到这一版**（先确认，然后 `putLorebook` 原样写回）、删除某一版。
- 验证：`test/version_store_test.dart` 7 例（存/列/读/删、顺序、按资产隔离、超上限丢最旧、索引坏）；
  真机 `integration_test/app_book_version_test.dart`：存快照 → 把书改成别的内容 → 回滚 → 
  引擎里又是原来那条「码头」。

### §4 落地（世界书 AI 四阶段）

- `tavern/lorebook_ai.dart`：四个提示 + 四个解析（蓝图 / 规划 / 一批正文 / 审查），
  `lorebookBatchLimit = 8`，`lorebookEntriesJson()` 折成 ST 原生 `entries`（uid 为键、常驻 `position: 0`）。
- `ui/tavern/tavern_lorebook_wizard_page.dart`：四段式页面，每段产物都能看、能改、能重跑；
  规划可逐条勾选；正文可逐条改/删；一批失败只影响那一批。
- 入口：资源库 › 世界书 › 右上角 ＋ › **世界书工坊**。
- 落盘：`putLorebook` 写成一个普通的世界书（`description` = 蓝图概述），之后照常在条目页里改，
  **不引入第二种格式**。
- 验证：`test/lorebook_ai_test.dart` 12 例；真机 `integration_test/app_lorebook_wizard_test.dart`
  四步走完，最后 `lorebook(id)` 读回来 2 条、常驻那条 `position: 0`（用 `MockClient` 按调用次数回四种答案）。

### §2 底座：草稿存得下、读得回、存得回去

- `tavern/studio_store.dart`：
  - `StudioDraftStore`：本地未存草稿（`<support>/studio/draft.json`），先写临时文件再改名；
    坏文件当没有；空草稿 = 清掉。`studioDraftStoreProvider` 在 `tavern_provider.dart`。
  - `loadStudioDraftFromCard` / `saveStudioDraftToCard`：卡片里 `extensions.dshgo.studio` 的读写。
  - `studioDraftFromCardData`：**老卡没有草稿时用它现有的内容起一份**（名字、描述→外貌、
    性格→内在性格、场景→初遇、开场白、示例、标签→表层性格），不让人对着空表单重打。
  - `studioEntryTitles` / `studioEntriesMissingFrom`：补条目按标题去重，存几次都只补缺的。
- 引擎加了 `updateCharacterData(id, patch)`（`api.dart` / `engine.dart` / `store/character_library.dart`），
  `extensions` **两层合并**（命名空间内再逐键合），所以写 `dshgo.studio` 不会冲掉 `dshgo.state`。
  `character_book` 明确拒绝（它有自己的 API）。
- 界面：角色页「设置」里多了一行 **专业草稿**；工作室带 `characterId` 时，
  保存 = 改正文（`updateCharacterFields`）+ 补缺的条目（`addCharacterBookEntry`）+ 存草稿
  （`updateCharacterData`），按钮文案也变成「存回这张卡」，**不会多出一张卡**。
  没绑卡的工作室退出时把草稿留在本地，下次打开接上；存成卡之后本地那份清掉。
- 验证：`test/studio_store_test.dart` 12 例 + `test/studio_roundtrip_test.dart` 5 例；
  `integration_test/app_studio_card_test.dart` 真机一条：老卡（没有草稿）→ 打开 → 起一份草稿 →
  改外貌 → 存回 → **书架还是 1 张**、正文更新、草稿进了 extensions、`dshgo.state` 还在。

### §2 P2 的落地（世界书与经历）

- 草稿多了一块 `book: List<StudioBookEntry>`（标题 / 正文 / 关键词 / 是否常驻），
  存在 `extensions.dshgo.studio.book` 里；`toJson` 空条目不写，旧草稿没有这个键也能读。
- AI 多了一个动作 `StudioAiAction.book`：只在 `history / world / bond / rules` 四个模块的
  整模块菜单里出现，提示要求「3~6 条，每条带 2~6 个关键词，没把握别常驻」。
- 转换器把草稿条目**排在**「字段里写的 `关键词|正文`」前面，常驻的 `position: before_char`，
  没有关键词的用正文开头六个字兜底，总数仍受 `studioBookLimit`（24）限制。
- 采用是**追加**不是覆盖：生成几批就是几批，用户自己删。
- 验证：`test/tavern_studio_book_test.dart` 8 例（往返、转换、排序、上限、解析、追加）；
  真机第 5 条：世界模块 → ✨ → 生成世界书条目 → 采用 → 页脚出现「世界书 2 条」。

### §1.5 的核实结论（重要，别照着 ST 的字面意思改）

`packages/dsh_tavern/lib/src/worldinfo/world_info.dart`：

- `delayUntilRecursion != 0` → 741 行：非递归阶段直接跳过；745 行：递归层级不够也跳过。
- `excludeRecursion` → 752 行：**递归扫描阶段跳过这一条**（= ST 的 Prevent Recursion）。
- `preventRecursion` → 869 行：这一条不进「可以继续触发别人」的名单（= ST 的 Exclude Recursion）。

也就是说**这两个名字在引擎里和 ST 是反的**。UI 现在按引擎真实行为写（「递归里跳过本条目」/「不向外递归」，
副标题注明了 ST 里的叫法）。`exclude + delay` 同时开 = 任何阶段都不激活，保存被挡下并解释。

没动引擎去"改回 ST 语义"——那会改变现有卡片的触发行为，得主人拍板。要改的话：
把 752 与 869 两处的字段对调，并跑引擎自己的 world info 测试。

### 设备验证怎么做的（下一轮照这个套路）

`integration_test/app_state_panel_test.dart` 直接挂 `TavernStagePanel`：

```dart
final tavern = await openTavern('${tempDir}/tavern');       // 真引擎、临时目录
final card = await tavern.importCard(bytes, fileName: 'x.json');
final chatId = await tavern.createChat(card.id);
await tester.pumpWidget(ProviderScope(
  overrides: [tavernProvider.overrideWithValue(tavern)],
  child: MaterialApp(… L10n.delegate …, home: Scaffold(body: TavernStagePanel(…))),
));
```

比走整套导航稳，而且数据是测试自己造的，不依赖模拟器里有没有卡。

## 1. 位置

| 用途 | 路径 |
|---|---|
| 构建工程（改代码、编 APK 在这里） | `E:\dshgo\tavern-lite\` |
| 交付副本（含 `dist/` 里的 APK、docs） | `E:\jiuuguan'\tavern-lite\` |
| 上游源码（只读，不要改） | `E:\dshgo\src\dsh-Go`（tag `v1.0.16`，commit `ddaff424b9fa1ed1d0cca389823facc046135dae`，AGPL-3.0） |
| Flutter SDK | `E:\dshgo\sdk\flutter`（3.50.0 / Dart 3.14.0） |

改完代码要同步到交付副本：`robocopy E:\dshgo\tavern-lite "E:\jiuuguan'\tavern-lite" /E /XD build .dart_tool .idea .gradle`，
再把 `app\build\app\outputs\flutter-apk\*.apk` 复制到 `dist/`。

## 2. 构建

```powershell
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
$env:JAVA_HOME='C:\Program Files\Java\jdk-17'
$FL = 'E:\dshgo\sdk\flutter\bin\flutter.bat'      # 必须用全路径，见下面的坑
cd E:\dshgo\tavern-lite\app
& $FL pub get
& $FL analyze --no-pub                            # 当前 0 error
& $FL build apk --release                         # 通用（三 ABI）
& $FL build apk --release --split-per-abi         # arm64 / v7a / x86_64
```

已踩过的坑（配置里都已修好，别回退）：

- **PATH 上的 `flutter` 是 `C:\tools\flutter`（Dart 3.12.2），不是这个项目的 SDK。**
  直接敲 `flutter build` 会报 `Because dsh_app requires SDK version ^3.13.5, version solving failed`。
  一律用 `E:\dshgo\sdk\flutter\bin\flutter.bat`（Flutter 3.50.0 / Dart 3.14.0）。
- `android/gradle.properties` 必须有 `kotlin.incremental=false`（Kotlin 2.4.20 在 Windows 上关不掉增量缓存）
  和 `org.gradle.java.home=C:/Program Files/Java/jdk-17`（否则 Gradle 会挑 Android Studio 的 JBR 25）。
- `android/app/build.gradle.kts` 里 `lint { checkReleaseBuilds = false; checkDependencies = false }`
  （AGP 9.3.1 的 lint 会抛 `NoSuchMethodError: JavaDocParser.parseDataItem`）。
- 若报 `compileDebugJavaWithJavac ... jdkImage`：删 `%USERPROFILE%\.gradle\caches\9.5.0\transforms`
  再构建（会重跑依赖 transform，约 2 分钟）。
- **不要用 PowerShell 的 `Get-Content`/`Set-Content` 改 `.dart` 文件**：会把 UTF-8 中文写成 GBK 乱码。
  用 `read`/`edit` 工具，或 python 以 `encoding='utf-8'` 读写。
- 写 JSON 给 curl 时不能用 `Set-Content -Encoding utf8`（带 BOM，服务端会报 parse error），用 `-Encoding ascii`。
- **改了界面文字要跑 l10n 合并，否则 `lib/l10n/gen/` 里没有新键。**
  工具在 `app/tool/l10n_merge.py`（从上游 `E:\dshgo\src\dsh-Go\app\tool` 拷过来的）：
  ```powershell
  $env:FLUTTER='E:\dshgo\sdk\flutter\bin\flutter.bat'   # 脚本按环境的 FLUTTER 找 SDK
  cd E:\dshgo\tavern-lite\app
  python tool\l10n_merge.py        # 71 parts / 7473 keys → gen-l10n
  ```
  文字只写在 `lib/l10n/parts/<area>_{zh,en}.arb`；两边键要成对，带占位符的还要写 `@key` 元数据（int 用 `"type": "int"`）。
- **`flutter test integration_test/...` 装在 `io.github.tavernlite.uiqa`，不是 `io.github.tavernlite.app`**。
  两种包名并存；`uiqa` 是测试用的那份，跑完测试想手动看界面，要么用它，要么把 release 包装回去。

## 3. 这个项目是什么

把 DSH Go 的「酒馆」单独拆成 Android App：卡片 / 世界书 / 预设 / 正则 / 人设 / 聊天 / 分支 / 群聊 /
舞台四标签（本局·状态·导演·本回合）/ 自动导演 / 提示词检视 / 缓存统计都在；DSH 引擎、终端、SSH、
远程、桌宠、Live2D 运行时、论坛、工坊、手机控制、语音输入全部去掉。

- 引擎 `packages/dsh_tavern`：98 个 lib 文件，**只有 2 个改过**（`api.dart` 加 `stream` 字段、
  `llm/model_client.dart` 用这个字段），其余与上游逐字节相同。195 个测试文件 / 2111 个用例，
  `dart test` 在本机 2730 通过、1 个 Windows 临时目录改名失败（单独重跑即过）。
- `app/lib` 193 个文件（含 `gen-l10n` 生成的 3 个）。多 API、模型选择、AI 制卡是本项目新加的，
  其余是上游裁剪 + 少量 lite 重写。
- applicationId `io.github.tavernlite.app`，可与 DSH Go 并存。release 用模板 debug 签名。

## 4. 已实现的功能（本轮陆续加的）

1. **多 API 配置**（`app/lib/api/api_profiles.dart` + `app/lib/ui/api/`）
   - DeepSeek 官方（内置，不可删）+ 任意个 OpenAI 兼容端点；Base URL / Key / 模型 / SSE / 思考开关。
   - Key 存 Keystore（`api_profile_key_<id>`），元数据在 SharedPreferences `api_profiles_v1`。
   - 页面：`ApiProfilesPage`（列表、激活、编辑、删除、测试连接）、`ApiProfileEditor`、`ApiKeyPage`。
2. **模型自动获取**（`app/lib/api/model_catalog.dart`、`ui/api/model_picker.dart`）
   - 请求 `<Base URL>/models`，解析 `context_window` / `max_output_tokens` / `input_modalities` /
     `effort.supported_levels`，读不到就按名字猜并标注「按名字判断」。
   - 选中后写回：官方写 `tavernSettings.setModel()`，自定义写 `profile.copyWith(model, vision, contextWindow, maxOutput)`。
3. **接口 / 模型两行**（`ui/api/api_tiles.dart`：`ApiProviderTile`、`ApiModelTile`）
   - 用在「我的 → 模型与连接」和「舞台 → 本局 → 正在用」；本局里传 `compact: true`（窄面板，限宽省略）。
4. **自定义接口不再被拦**（`app/lib/state/model_access.dart` 的 `modelAccessProvider`）
   - 聊天页原来 4 处只看 `settingsProvider.hasApiKey`（官方 Key），配了中转照样提示「先填 API Key」；
     现在看当前生效接口有没有 Key。
5. **人民币计费**（`tavern/tavern_session_usage.dart`）
   - `const tavernUsdToCny = 7.2;` + `tavernCny()`；显示全改 ¥（`tavernCostLabel`、本局用量、用量页）。
   - 提醒档位 `tavernCostAlerts` 改成 `[0, 0.1, 0.5, 1.0, 3.0]` 元；ARB 文案 `tavernSessionUsageCost` /
     `tavernCostAlertSubtitle` 也改了（中英都改）。
6. **聊天页顶部遮挡修复**（`ui/tavern/tavern_chat_page.dart`）
   - 那个 `ListView(reverse: true)` 的 padding 原来是 `(16, 12, 16, topInset+8)`，顶部只留 12，
     第一条消息会钻到浮层 header 底下；改成两边都 `topInset + 8`。
7. **AI 角色工坊**（`tavern/tavern_card_studio.dart` + `ui/tavern/tavern_card_studio_page.dart`）
   - 两档（设计稿定的）：**快速创作**只有「核心创意」+「篇幅」；**高级创作**再加姓名（可空＝AI 取名）/
     身份 / 世界观 / 与玩家关系 / 性格标签（多选）/ 补充设定。默认停在快速档，`SegmentedPill` 切换。
   - 世界观与关系是**自由输入**（`_freeField`）：直接打字，右边那颗箭头只是"从常见项里挑一个"
     的补全面板；两者共用一个 controller，挑完还能继续改。
   - 「没填的字段不进提示」：`TavernCardWish` 里空串直接跳过，模型不会去猜你不想指定的东西；
     性格标签是"必须包含"、补充设定是"照这个写，不要改写"。
   - 篇幅 → max_tokens 1200 / 2000 / 3000，同时改提示里的字数要求。
   - 一次 chat-completions 调用，流式贴原文 → 解析成卡 → 预览 → 存进书架。
   - **不走引擎、不进聊天**：`tavernModelClientProvider` 直接 new `TavernModelClient`，
     `tavernModelConfigProvider` 取当前生效接口（和引擎同一个源），所以没有 preset / 历史 / 上下文锁。
   - 解析很宽：```json 围栏、前面带「好的，这是你的卡：」、外面包一层 CCv3 `data` 都能救回来；
     救不回来就把原文摊在页面上让人看，不猜。没有 name 的回复当失败。
   - 存卡走 `importCard`（V2 JSON），所以跟导入的卡完全一样：有 id、有页、能继续编辑；
     存完直接 `pushReplacement` 到编辑页，返回是书架。
   - 费用按 ¥ 显示（复用 `tavernModelPrice` / `tavernReplyCost` / `tavernCny`）。
   - 入口三处：书架右上角魔法棒（`tavern-card-studio`）、导入面板第四项（`tavern-import-ai`）、
     空书架按钮（`tavern-empty-studio`）。
   - 生成键钉在底部 `FormBottomBar`；提示语和流式原文放在页面最上面（写完不用往下找）。
   - 新增 63 个 l10n 键，都在 `lib/l10n/parts/tavern_{zh,en}.arb`（`tavernCardStudio*` / `tavernCardTrait*`）。
8. **专业创作（P0 地基）**（`tavern/tavern_studio_draft.dart`、`tavern_studio_schema.dart`（生成）、
   `tavern_studio_build.dart`、`ui/tavern/tavern_studio_page.dart`）
   - 九个模块 / 59 个字段，按 `docs/AI-CARD-STUDIO-SPEC.md` 落地。模块列表显示进度（已填/总数），
     子页逐字段编辑；每个字段有 🔒锁定 和 ↺撤销（撤销栈 10 步，条目字段按行还原）。
   - **转换器 `buildStudioCard`** 是这块的核心：把草稿按固定顺序折成 description / personality /
     scenario / first_mes / mes_example / 提示词，另有世界书条目。
     description 上限 900 字，超了按规格 §11.2 的四步裁（砍经历 → 内在留一句 → 去印象 → 去体态），
     还超就抛 `StudioBuildError` 让页面拒绝保存——不静默截断。
   - 世界书只收"有明确关键词"的：列表字段写成 `关键词|正文`（中英竖线都认），没写的拿正文开头几个字兜底；
     整段文字的字段（能力/弱点/秘密）暂时不进书，因为没关键词的条目等于常驻、每回合都烧钱。
   - 草稿存进卡片的 `extensions.dshgo.studio`，导出导入都跟着走（有单测往返验证）。
   - 入口：工坊页「专业创作」那一行（`tavern-card-studio-pro`）。
   - **AI 动作还没接**：字段上只有锁和撤销，没有点不动的 ✨（P1 再接 studioAsk）。
   - 字段表是生成出来的：改 `app/tool/gen_studio_schema.py` 里的表，重跑脚本，
     它同时产出 `tavern_studio_schema.dart` 和 `lib/l10n/parts/studio_{zh,en}.arb`（100 个键）。
   - 验证过：`test/tavern_studio_test.dart` 15 例（含描述裁剪顺序、条目上限、草稿往返），
     `integration_test/app_studio_test.dart` 在模拟器上跑通整条链（九模块→填字→锁定→撤销真的退回→
     进度 2/12→预览→存卡进角色页）。
9. **世界书：新建空白书**（`tavern/lorebook_new.dart` + 世界书列表页的 `+`）
   - 引擎没有 create，只有 `putLorebook(id, json)`；**读不到就照写**（engine.dart 2222：
     `_readBookNow` 返回 null 后直接 `_writeBookNow`），所以新建 = 挑个没占用的 id 把空书写进去。
   - `newLorebookId()`：32 位十六进制，满足引擎的 `^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`。
   - `emptyLorebookJson(name)`：ST 原生形状，**不写 `scan_depth` / `token_budget`**——
     缺省时按用户全局设置走，写死会把用户的偏好冲掉。
   - 列表右上角 `+` 现在是二选一：导入世界书 / 新建空白书；起名后直接进书的条目页。
   - 顺手修了一个文案错：独立世界书的空态原来复用卡内书那句「**这张卡**还没有自己的世界书」，
     现在有自己的 `tavernLibraryBookStart`。
   - 验证过：`test/lorebook_new_test.dart` 5 例（真开引擎、真落盘：新建即出现在列表、加条目读回 1 条、
     删一本另一本还在）；`integration_test/app_lorebook_new_test.dart` 在模拟器上跑通
     资源库→世界书→＋→新建→起名→加一条→保存。
10. **世界书：专业触发规则**（`tavern/tavern_book_entry.dart` + 条目编辑页）
    - 条目编辑页底下多了一段「更多触发规则」，默认折叠，展开后有：
      正则触发 / 不从这里递归出去 / 不接受递归进来 / 只在递归里出现 / 扫描深度 /
      分组（名字 + 强制整组 + 组内权重）/ 黏住轮数 / 冷却轮数 / 延迟轮数。
    - 字段名用的是 **CC v3 的 extensions 写法**（`exclude_recursion`、`group_weight`、`sticky`…），
      `tavern_book_entry.dart` 的 `_extensionNames` 负责搬到 ST 原生条目顶层
      （`excludeRecursion`、`groupWeight`、`sticky`…），读回来再搬回去——所以同一份编辑器
      既能编卡内书，也能编资源库里的书。
    - 写回是**稀疏**的：等于默认值、而且原来就没有的字段不写，不会给每条塞一堆 false / 0。
    - 验证过：`test/tavern_book_entry_test.dart` 4 例（两种形状互转、原地合并、
      11 个新字段走一圈不丢）；`integration_test/app_lorebook_new_test.dart` 里加了一段真机往返：
      展开 → 打开正则 + 递归 → 填分组「港口」→ 保存 → 重新打开，三个值都是从引擎读回来的。

## 5. 测试

```powershell
cd E:\dshgo\tavern-lite\app
# 纯逻辑，不用设备：制卡的请求组装 / JSON 解析 / V2 卡
flutter test test/tavern_card_studio_test.dart
# 纯逻辑，不用设备：草稿（锁定/撤销/JSON 往返）+ 转换器（拼接顺序/裁剪/世界书）
flutter test test/tavern_studio_test.dart
# 真引擎、不用设备：新建世界书（putLorebook 当 create 用，落盘后能读回）
flutter test test/lorebook_new_test.dart
# 纯逻辑，不用设备：条目两种形状互转（含递归/分组/冷却那 11 个字段）
flutter test test/tavern_book_entry_test.dart
# 设备上：资源库 → 世界书 → ＋ → 新建空白书 → 起名 → 加一条 → 存住
flutter test integration_test/app_lorebook_new_test.dart -d <device>
# 设备上：工坊 → 专业创作 → 九个模块 → 填字 → 撤销 → 预览 → 存卡
flutter test integration_test/app_studio_test.dart -d <device>
# 设备上的 widget 级冒烟：首页 → 我的 → API Key → API 配置 → 新增编辑器
flutter test integration_test/app_smoke_test.dart -d <device>
# 示例卡 → 角色页 → 聊天 → 舞台四标签（窄屏会先点开抽屉）
flutter test integration_test/app_tavern_flow_test.dart -d <device>
# 真实模型两回合 + 缓存命中（Key 走命令行，不进仓库）
flutter test integration_test/live_model_test.dart -d <device> --dart-define=TAVERN_TEST_KEY=sk-...
# 自定义档（deepseek:false + stream:false）非流式
flutter test integration_test/live_custom_api_test.dart -d <device> --dart-define=TAVERN_TEST_KEY=sk-...
# AI 制卡：从书架打开、三段在、空需求不花钱、选基调和篇幅生效
flutter test integration_test/app_card_studio_test.dart -d <device>
```

实测过的数字（2026-11-15，Redmi 2312DRAABC / Android 15）：
两回合 `promptTokens` 403 / 400，`cacheHitTokens` 256 / 128，`completionTokens` 24 / 29，
`thinking:false` 生效（reasoning 0 字）。

## 6. 设备

- 模拟器：雷电 0 号，`emulator-5554`，装 `app-x86_64-release.apk`。
  - **注意**：之前 `wm size 1080x2400` 覆盖导致画面塞进横屏窗口、鼠标点哪都不对；
    已 `wm size reset; wm density reset`（现 1920x1080 / 280dpi）。别再覆盖，要竖屏就改实例分辨率。
  - 这台 adb `input tap` 落点偶尔偏移，验证 UI 优先用 integration_test。
- 真机：Redmi `2312DRAABC`（Android 15 / arm64），无线调试已配过对；装 `app-arm64-v8a-release.apk`。

## 7. 还没做 / 已知问题

1. **识图只是标记**：模型选择里能看到「识图」，但**不能真的发图**。引擎 `send()` 只接文本，
   消息模型没有图片字段。要做需改三处：消息模型加图片、prompt 组装出 `image_url` 多模态段、输入框加附件。
2. **header 半透明透字**：消息滚动时会从「林晚 就绪」胶囊下穿过（原版设计）。要改就加不透明底或顶部渐隐。
3. ~~`dist\tavern-lite-1.0.16-universal-release.apk` 是 22:24 的，没有人民币和 inset 修复~~
   已重打：23:19 的通用包，其 `lib/arm64-v8a/libapp.so` 与 22:37 的 arm64 包 CRC 完全一致
   （`3587A0D9` / 22086616 字节），可确认与修好的源码同源。dist 里三个包现在都是新的。
4. 状态定义（卡片的 `extensions.dshgo.state`）能显示也能改，但 `rules`（每回合自动改数值）还没写过示范。
5. 文档（`docs/VERIFICATION.md` 等）还没补这一轮的多 API / 模型选择 / 人民币改动。
6. **AI 制卡没在设备上真正跑过一次生成**：模拟器上 `io.github.tavernlite.app` 没配 Key（Key 在
   `io.github.tavernlite.uiqa` 那份测试包里），所以只验证到「空需求提示」「无 Key 提示」两条。
   第一次真跑要盯两件事：模型吐的 JSON 能不能解析、`importCard` 存完卡在不在书架上。
   要跑就用 `live_*` 那套 `--dart-define=TAVERN_TEST_KEY=...` 的路子，别把 Key 写进仓库。
7. 生成一次卡会花掉几百到两千 token（篇幅决定 max_tokens）；页面上有 ¥ 估算，但没做上限拦截。
8. **专业创作只做到 P0**：字段、锁定、撤销、预览、存卡都通了，但**字段级 AI 动作（补全/扩写/精简/
   重写/检查）还没接**，规格 §1.5 的 `studioAsk` 一行没写。下一步就是它（P1），接完再谈
   "整模块生成"和"一致性检查"。
   - 另外还欠：从一张**已有卡**里把草稿读回来继续编辑（现在只能新建；`characterFields()` 能读到
     `extensions.dshgo.studio`，缺的是"存回已有卡"的写入路径——`updateCharacterFields` 不收
     `extensions` 和 `character_book`，要么加引擎 API，要么另想）。
   - 世界书条目目前只从列表字段的 `关键词|正文` 生成；能力/弱点/秘密这些整段文字还没进书，
     等 P2 让 AI 给关键词。
9. `docs/` 里有四份文档，别混：
   - `AI-CARD-STUDIO-SPEC.md`：角色卡九模块的字段级规格（P0 已按它落地一部分）；
   - `LOREBOOK-PRESET-TASKBOOK.md`：**世界书工坊 + 预设工坊的开发任务书**，开头就写死了
     "不许改角色卡工坊的哪些文件"和"只能走哪几条数据接口"，下一步照它做；
   - `card-studio-quick.png` / `card-studio-advanced.png`：工坊两档截图；
   - `VERIFICATION.md` 等老文档没跟上，别当现状读。
10. **模拟器现在是关着的**（2026-11-16 09:4x `adb devices` 为空，LDPlayer 进程不在）。
    要跑 integration_test 或截图，得先把雷电 0 号开起来；包本身没问题，01:31 那轮构建之后
    Dart 代码一个字没动（三个 APK 是同一份代码）。

## 8. 测试卡

`E:\dshgo\state-test.json`（也推到了模拟器 `/sdcard/Download/state-test.json`）：
带 `extensions.dshgo.state`，六项状态（好感/体力/心情/背包/时间/地点），用
`dart run tool/check_state_card.dart <path>` 验证过 `initialized=true schema=true issues=[]`。

## 9. 世界书类型 · 人格层 · 制卡顺手写世界书（2026-11-16 夜）

动手前先拿真书量了一遍：`C:\暑期项目\nixiangdu\worldbooks\_top15_按下载量`
（15 本，按下载量排，条目 1~82 本、正文均长 334~5928 字、常驻占比从 0 到 100%）。
结论是**工坊只会写一种书**——地点/势力/人物那套设定书——而真在用的书明显分五类，
写法完全不同。所以这一轮改的是「生成什么」，不是解析。

### 9.1 世界书五类（`lorebook_ai.dart` 的 `LorebookKind`）

| 类型 | 条数 | 正文 | 关键词 | 常驻 |
|---|---|---|---|---|
| world 世界设定 | 按篇幅 5/10/18 | 300–600 字 | 3–6 | 最多 1 条 |
| style 文风 | 4–6 | 400–900 字 | 无 | 全部 |
| guardrail 破甲/防抢话 | 1–3 | 80–200 字 | 无 | 全部 |
| mechanic 玩法机制 | 按篇幅 | 200–500 字 | 3–6 | 只有总则 |
| lexicon 描写词条 | 按篇幅 | 300–700 字 | 4–8 | 无 |

- 提示词按类分叉：`_system` / `_blueprintSpec` / `_planSpec` / `_batchSpec`，zh/en 各一套。
- 批次大小也按类分（`batchSize` 3~6），上限 `batchTokens` 2400~3600——
  原来固定 8 条 × 200 字配 2000 tokens，中文会直接被截断。
- 换类型会清空蓝图/规划/已写条目：拿设定书的蓝图去写文风书没有意义。
- 界面：工坊第一步多一行「类型」，点了弹面板选。

### 9.2 人格层（`preset_persona.dart`）

- `presetPersonaText(raw)`：从一本 ST 预设里取**系统提示**（跳过 marker、跳过 role 不是
  system 的），顺序照它自己的 `prompt_order`（character_id 100001 那组），老预设的
  `main_prompt` / `nsfw_prompt` / `jailbreak_prompt` 也认。
- `withPersona(messages, text)`：垫成第一条 system，任务的 system 留在最后，JSON 形状仍然优先。
- **制卡和世界书各一份，不共用**：`tavern.persona.card` / `tavern.persona.book`
  （`tavern_settings.dart`），两页各挑各的，互不影响已有对话。
- 预设本身没被改：只读不写，只把它的提示拼进这一次请求。

### 9.3 制卡顺手写世界书（`cardBookMessages`，和工坊是两套提示）

- 制卡页多一块「生成设定」：人格层 + 「同时写一本世界书」开关；
  开关打开后二选一：**AI 一键** / **我先说个大概**（填一段方向，写进提示）。
- 存卡顺序：`importCard` → 卡已在 → 再写世界书 → 逐条
  `addCharacterBookEntry`（字段名走 `cardBookEntryFields`，和条目编辑页同一套）。
  世界书写失败**不撤销存卡**，只弹一句「卡存好了，世界书没写出来」。
- 条目进的是卡片的 `character_book`，跟着卡走（导入导出、换设备都在一起），
  不是资源库里另一本要对名字的书。
- 提示锚点是这张卡自己（名字/描述/性格/场景），要求「只在这张卡的世界里成立」。

### 9.4 顺手修的真 bug

- `lorebookJson` 原来用 `lastIndexOf('}')` 当 JSON 结尾、裸 `jsonDecode`：
  和制卡第一次失败同一个坑（`{{user}}` 里的 `}`、正文里没转义的引号、被截断）。
  现在：先试原文，再试「补引号」，再试 `tavernCardRepair`，最后从末尾往前试几个 `}`。
- 分批写正文：原来第一批空就直接 `return`，后面几批不跑，交出去半本书。
  现在 `continue`，最后提示「N 批没写出来，其余先存着」。

### 9.5 「专业创作」的 AI 不认「我想要的角色」（已修）

现象：在专业创作里点字段上的 ✨，生成的东西和「我想要的角色」没关系。

查下来不是没写，是**写了没发**：

- `StudioDraft.idea`（就是制卡页那句创意，会随草稿存盘）在提示里只出现过一次
  ——`tavern_studio_ai.dart` 在 `_summary` 前后拼一句「角色创作灵感：…」，而
  `_summary` 只读 profile/world 的字段，所以那句创意在**某些路径上根本没进提示**；
  从制卡页进专业创作时 `TavernStudioPage.route()` 也没把 `_idea.text` 带过去。
- 现在：提示里明确成一段「我想要的角色：…」（`studioAiMessages`，800 字截断），
  制卡页进专业创作时带上 `idea: _idea.text`；
  专业创作页最上面多了一块可编辑的「我想要的角色」输入（绑 `_draft.idea`），
  从哪条路进来都能补写。
- 验证：`test/studio_idea_prompt_test.dart` 4 例（写了进提示 / 没写不占地方 /
  制卡页那句创意同一个字段 / 整模块生成也带着）。

### 9.6 工坊卡在第二步：计划被 1400 截断（2026-11-17 早）

现象：走到第二步「规划条目」就报「没生成出来」，永远进不到写正文。

病灶不在解析，在**请求的 token 上限**：

- `_ask` 默认 1400，而 `_makeBlueprint` / `_makePlan` 两个调用都没显式传值；
- 计划要一次列完所有条目（小 5 / 中 10 / 大 18 条，每条带标题、类型、理由），
  中文 JSON 大档稳超 1400 → 回复被截断 → JSON 不合法 → 解析为空 → 界面只会说
  「没生成出来」。写正文那步走 `batchTokens`（2400–3600），所以卡点只出现在计划。

修法：

- `_ask` 默认 1400 → **4000**（和 AI 制卡同一个数），蓝图跟着受益；
- 计划显式给 `lorebookPlanTokens(target)` = `(900 + target*180).clamp(1600, 4000)`，
  条数越多给得越多，不再依赖默认值「刚好够」；蓝图显式 `lorebookBlueprintTokens = 2200`；
- 计划解析为空时换一句更准的话（`lorebookWizardPlanEmpty`）：
  「回来了内容，但不是能用的计划（多半被截断了）」，和请求失败区分开；
- 单测断言 `lorebookPlanTokens(18) == 4000`、随条数单调增、蓝图 > 1400。

### 9.7 这一轮没验的

- **没在设备上跑过**：本机 Flutter 3.44.8 / Dart 3.12.2，而 `app/pubspec.yaml` 要
  `sdk: ^3.13.5`，`flutter test` 在解析依赖那步就退出了。`dart analyze` 能用现有的
  `package.json` 跑（对改过的文件逐个跑过，0 error 0 warning）；单元测试要主人那边跑。
- `flutter gen-l10n` 不受影响，l10n 走 `python tool/l10n_merge.py` 正常（7836 key）。
- 新增单测 `test/lorebook_kind_persona_test.dart`（人格层排序/空预设、五类提示分叉、
  `{{user}}` 与截断解析、卡内条目字段名、两套提示确实不同）。

### 9.7 人格层：从真素材里提炼出来的两条内置（2026-11-17）

**素材**：`C:\暑期项目\nixiangdu\worldbooks\_top15_按下载量` 里 15 本按下载量排的世界书。
按「授权 / 词表 / 文风 / 边界 / 格式」五类信号统计常驻条目的正文，结果很干净：

| 书 | 条目 | 常驻 | 授权 | 词表 | 文风 | 边界 |
|---|---|---|---|---|---|---|
| 09 多维度玩弄 | 78 | 62 | 93 | 430 | 72 | 382 |
| 02 雷霆破甲 | 11 | 10 | 16 | 109 | 9 | 34 |
| 15 涩涩文风 | 7 | 7 | 4 | 47 | 77 | 103 |
| 08 防抢话 | 1 | 1 | 0 | 0 | 0 | 3 |
| 01 描写补充 | 82 | **0** | 0 | 0 | 0 | 0 |

两类书长得很不一样：**破甲/文风类**全是常驻、长篇、几乎不讲关键词；**词条库类**零常驻、
全靠关键词触发。共同点是有效成分只有四样——授权（允许写什么）、词表（该用什么词）、
文风（怎么写）、边界（不许干什么）。

**这一轮落地的两件事**：

1. **内置人格两份**（`preset_persona.dart`）：`builtin:card` / `builtin:book`，
   把上面四样浓缩成各 ~800 字，写法是「授权但不强迫」——允许限制级、也别在非成人向的卡上
   硬塞性内容（这条和主人自己的规矩一致）。界面上人格层面板多一行「内置 · 写卡用 / 写书用」，
   不用导入预设也能用。
2. **宏净化 + 长度上限**（同一文件）：
   - 预设里的 `{{char}}`/`{{user}}`/`{{original}}` 是聊天宏，写卡请求里没有值——
     原样发过去，模型会以为自己在扮演而不是在写卡。现在换成「角色 / 玩家」，其余 `{{…}}` 删掉。
   - 破甲类预设动辄几千字，全塞进去会把 token 预算吃光。`personaTextLimit = 3000`，
     超了从末尾裁（授权和口吻通常在最前面），末尾留一句「后面截掉了」。

**没验的**：内置两份只在单测里断言了长度与关键词，没上真机跑过；
主人自己的 NSFW 预设还没导进这台模拟器（DB 里只有「默认预设」「Codex test preset」「111」三条，
后两条内容为空），要拿真预设校，得先在 资源库 › 预设 里导入。
