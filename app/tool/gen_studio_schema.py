#!/usr/bin/env python3
"""从一张表生成创作层的字段规格 + l10n 文案。

  python tool/gen_studio_schema.py

产出（两个都覆盖写）：
  lib/tavern/tavern_studio_schema.dart
  lib/l10n/parts/studio_zh.arb, studio_en.arb

为什么生成：59 个字段 × 2 种语言 = 118 条文案，手写错一个键名，analyze 才会发现。
表是唯一真相：加字段就加一行，重跑，别去改生成出来的两个文件。
"""
from __future__ import annotations

import json
import os

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# module | key | 中文 | English | control | budget | target | required
FIELDS = [
    # 01 人物档案
    ("profile", "name", "姓名", "Name", "line", 12, "card", True),
    ("profile", "nickname", "昵称", "Nickname", "line", 12, "card", False),
    ("profile", "age", "年龄", "Age", "line", 8, "card", False),
    ("profile", "gender", "性别", "Gender", "tags", 4, "card", False),
    ("profile", "species", "种族", "Species", "line", 12, "card", False),
    ("profile", "appearance", "外貌", "Appearance", "block", 160, "card", True),
    ("profile", "body", "体态细节", "Bearing", "block", 120, "card", False),
    ("profile", "identity", "身份职业", "Role", "line", 20, "card", False),
    ("profile", "likes", "爱好", "Likes", "tags", 60, "card", False),
    ("profile", "habits", "生活习惯", "Habits", "block", 120, "card", False),
    ("profile", "ability", "能力", "Abilities", "block", 120, "book", False),
    ("profile", "weakness", "弱点", "Weakness", "block", 100, "book", False),
    # 02 深度人格
    ("mind", "surface", "表层性格", "Surface", "tags", 40, "card", False),
    ("mind", "inner", "内在性格", "Inner", "block", 160, "card", False),
    ("mind", "values", "价值观", "Values", "block", 100, "card", False),
    ("mind", "desire", "欲望", "Desire", "block", 80, "meta", False),
    ("mind", "fear", "恐惧", "Fear", "block", 80, "meta", False),
    ("mind", "flaw", "缺陷", "Flaw", "block", 80, "card", False),
    ("mind", "trigger", "情绪触发", "Triggers", "list", 120, "book", False),
    ("mind", "defense", "防御机制", "Defences", "block", 100, "book", False),
    # 03 玩家关系
    ("bond", "initial", "初始关系", "Starting relation", "line", 20, "card", False),
    ("bond", "impression", "彼此印象", "First impression", "block", 120, "card", False),
    ("bond", "trust", "信任度", "Trust", "line", 4, "meta", False),
    ("bond", "intimacy", "亲密边界", "Boundaries", "tags", 60, "book", False),
    ("bond", "conflict", "关系冲突", "Friction", "block", 120, "card", False),
    ("bond", "growth", "关系变化规则", "How it grows", "list", 160, "book", False),
    # 04 人生经历
    ("history", "family", "家庭背景", "Family", "block", 140, "card", False),
    ("history", "upbringing", "成长经历", "Upbringing", "block", 140, "card", False),
    ("history", "timeline", "重要事件", "Timeline", "list", 200, "book", False),
    ("history", "secret", "秘密", "Secrets", "block", 120, "book", False),
    ("history", "memory", "回忆", "Memories", "block", 100, "book", False),
    ("history", "goal", "人生目标", "Goal", "block", 80, "meta", False),
    # 05 世界与背景
    ("world", "era", "时代", "Era", "line", 20, "book", False),
    ("world", "geography", "地理", "Geography", "block", 160, "book", False),
    ("world", "factions", "组织势力", "Factions", "list", 200, "book", False),
    ("world", "society", "社会制度", "Society", "block", 140, "book", False),
    ("world", "places", "重要地点", "Places", "list", 200, "book", False),
    ("world", "worldRules", "世界规则", "World rules", "list", 160, "book", False),
    # 06 对话与文风
    ("voice", "tone", "说话语气", "Tone", "tags", 30, "card", False),
    ("voice", "wording", "措辞习惯", "Wording", "block", 120, "card", False),
    ("voice", "catchphrase", "口头禅", "Catchphrases", "list", 40, "card", False),
    ("voice", "action", "动作描写", "Action style", "block", 100, "meta", False),
    ("voice", "emotion", "情绪表达", "Emotion", "block", 100, "card", False),
    ("voice", "samples", "示例对话", "Sample lines", "list", 300, "card", False),
    ("voice", "firstMes", "开场白", "Opening line", "block", 260, "card", False),
    # 07 情节与场景
    ("scene", "meeting", "初遇", "First meeting", "block", 140, "card", False),
    ("scene", "backdrop", "剧情背景", "Backdrop", "block", 160, "card", False),
    ("scene", "tension", "核心矛盾", "Core tension", "block", 120, "card", False),
    ("scene", "direction", "剧情方向", "Directions", "list", 120, "book", False),
    ("scene", "openings", "多开场白", "Openings", "list", 260, "card", False),
    # 08 行为与扮演规则
    ("rules", "autonomy", "角色自主性", "Autonomy", "tags", 40, "card", False),
    ("rules", "knowledge", "知识边界", "Knowledge", "block", 140, "card", False),
    ("rules", "principles", "行为原则", "Principles", "list", 160, "card", False),
    ("rules", "interaction", "互动规则", "Interaction", "list", 140, "card", False),
    ("rules", "consistency", "一致性", "Consistency", "list", 120, "card", False),
    # 12.1 灵魂档案（模块 12，先按模块摆进来）
    ("soul", "motive", "核心动机", "Motive", "block", 60, "meta", False),
    ("soul", "constants", "不可改变", "Constants", "tags", 40, "meta", False),
    ("soul", "conflict", "内在冲突", "Inner conflict", "block", 60, "meta", False),
    ("soul", "soulGrowth", "成长方向", "Growth", "block", 60, "meta", False),
]

# 界面文案：key | 中文 | English | 占位符 {名字: 类型} 或 None
UI_KEYS = [
    ("studioTitle", "专业创作", "Professional", None),
    ("studioSubtitle", "九个模块，一层一层写", "Nine modules, one layer at a time", None),
    ("studioHint", "先写有把握的字段，剩下的下一版交给 AI。锁上的字段不会被 AI 改。",
     "Write what you know. Locked fields are never rewritten.", None),
    ("studioPreview", "预览", "Preview", None),
    ("studioPreviewAction", "预览并保存", "Preview and save", None),
    ("studioSaveAsCard", "存进书架", "Save to the shelf", None),
    ("studioSaveFailed", "没能存进书架", "Couldn't save it to the shelf", None),
    ("studioMissingRequired", "还差：{names}", "Still missing: {names}", {"names": "String"}),
    ("studioTooLong", "描述 {chars} 字，上限 {cap}；先精简一些再存",
     "The description is {chars} characters; the cap is {cap}. Trim it first.",
     {"chars": "int", "cap": "int"}),
    ("studioTotalChars", "描述 {count} 字", "{count} characters", {"count": "int"}),
    ("studioBookCount", "世界书 {count} 条", "{count} world book entries", {"count": "int"}),
    ("studioFieldHint", "这段字最后去哪由转换器决定：有的进角色描述，有的变成世界书条目。",
     "Where each field lands is the converter's call: some go into the description, some become book entries.",
     None),
    ("studioLock", "锁定", "Lock", None),
    ("studioUnlock", "解锁", "Unlock", None),
    ("studioUndo", "撤销", "Undo", None),
    ("studioBudget", "建议 {count} 字以内", "up to {count} characters", {"count": "int"}),
    ("studioAddTag", "加一个标签", "Add a tag", None),
    ("studioAddItem", "加一条", "Add one", None),
    # AI 动作
    ("studioAiActions", "让 AI 写这一格", "Ask the AI for this field", None),
    ("studioAiFill", "补全", "Fill in", None),
    ("studioAiFillSubtitle", "空着的时候用", "For an empty field", None),
    ("studioAiExpand", "扩写", "Expand", None),
    ("studioAiExpandSubtitle", "写长一点，不推翻已有的", "Longer, without overturning what's there", None),
    ("studioAiTrim", "精简", "Tighten", None),
    ("studioAiTrimSubtitle", "压到七成，只留能进卡的", "Down to about 70%, keeping what belongs in a card", None),
    ("studioAiRewrite", "重写", "Rewrite", None),
    ("studioAiRewriteSubtitle", "按你说的要求重写", "Rewrite as you ask", None),
    ("studioAiCheck", "检查", "Check", None),
    ("studioAiCheckSubtitle", "找矛盾和空话，不改文本", "Find contradictions; change nothing", None),
    ("studioAiWholeModule", "整模块生成", "Write the whole module", None),
    ("studioAiWholeSubtitle", "把还没写、没锁的字段一次写完", "Fill every empty, unlocked field at once", None),
    ("studioAiInstruction", "想要怎么改", "How should it change", None),
    ("studioAiInstructionHint", "例如：更冷一点，少用感叹号", "e.g. colder, fewer exclamation marks", None),
    ("studioAiProposal", "看看要不要", "Review before using", None),
    ("studioAiIssues", "查出来的问题", "What the check found", None),
    ("studioAiAdopt", "采用", "Use it", None),
    ("studioAiDiscard", "丢弃", "Discard", None),
    ("studioAiFailed", "没能生成，再试一次", "Couldn't generate; try again", None),
    ("studioAiNothing", "模型这次没给出能用的内容", "The reply had nothing usable in it", None),
    ("studioAiLocked", "这个字段锁着呢，先解锁", "This field is locked; unlock it first", None),
    ("studioAiUsage", "这次 {count} tokens · ¥{cost}", "{count} tokens · ¥{cost}",
     {"count": "int", "cost": "String"}),
    ("studioAiUsageTokens", "这次 {count} tokens", "{count} tokens", {"count": "int"}),
    ("studioAiBook", "生成世界书条目", "Make world book entries", None),
    ("studioAiBookSubtitle", "把这一模块拆成几条，带关键词", "Split this module into entries with keys", None),
    ("studioBookConstant", "常驻", "Always on", None),
    ("studioCardSubtitle", "这张卡的专业草稿：读回来、改、存回去",
     "This card's studio draft: load, edit, save back", None),
    ("studioSavedToCard", "存回这张卡了", "Saved back to this card", None),
    ("studioSaveToCard", "存回这张卡", "Save back to this card", None),
    ("studioRestoreFailed", "没能读回草稿，先空着写", "Couldn't load the draft; starting empty", None),
    ("studioSimulate", "????", "Try three scenes", None),
    ("studioSimulateSubtitle", "??? / ??? / ????????????",
     "Spoken to, insulted, alone: does this card sound like them", None),
    ("studioStateAi", "????", "State plan", None),
    ("studioStateAiSubtitle", "?????????????????",
     "Design a few state fields for this card; review first", None),
    ("studioState", "??", "State", None),
    ("studioStateNone", "?????", "No state yet", None),
    ("studioStatePick", "????{name}?", "Use the template \u300c{name}\u300d", {"name": "String"}),
    ("studioStateClear", "????", "No state", None),
    ("studioStateFields", "{count} ?", "{count} fields", {"count": "int"}),
]

MODULES = [
    ("profile", "01 人物档案", "Profile", "谁：姓名、外貌、身份、能力与弱点", "Who they are"),
    ("mind", "02 深度人格", "Depth", "为什么：欲望、恐惧、缺陷、触发", "Why they are"),
    ("bond", "03 玩家关系", "Bonds", "和你：初始关系、印象、边界、变化规则", "How they meet you"),
    ("history", "04 人生经历", "History", "从哪来：家庭、经历、秘密、目标", "Where they come from"),
    ("world", "05 世界与背景", "World", "在哪：时代、势力、地点、规则", "The world around them"),
    ("voice", "06 对话与文风", "Voice", "怎么说：语气、措辞、口头禅、示例", "How they speak"),
    ("scene", "07 情节与场景", "Scenes", "怎么开始：初遇、矛盾、多开场白", "How it starts"),
    ("rules", "08 行为规则", "Rules", "怎么演：自主性、知识边界、原则", "How they behave"),
    ("soul", "灵魂档案", "Soul", "真正驱动他的是什么（不进卡，只做约束）", "What drives them"),
]

HEADER = """// 生成文件，别手改：改 `tool/gen_studio_schema.py` 里的表，重跑。
//
// 创作层的字段规格：九个模块、59 个字段，每个都带着控件类型、字数预算和去向。
// 去向只有三种：
//   card —— 会被转换器写进 description / personality / scenario / …；
//   book —— 变成世界书条目，关键词触发时才注入；
//   meta —— 只留在 extensions 里，给导演/剧本按需用，不占卡片字数。

import '../../l10n/l10n.dart';

/// 字段怎么填。
enum StudioControl { line, block, tags, list }

/// 这段文字最后去哪。
enum StudioTarget { card, book, meta }

"""


def camel(module: str, key: str) -> str:
    return "studio" + module.capitalize() + key[0].upper() + key[1:]


def module_key(module: str, suffix: str) -> str:
    return "studioModule" + module.capitalize() + suffix


def dart() -> str:
    out = [HEADER]
    out.append("class StudioFieldSpec {\n"
               "  const StudioFieldSpec(\n"
               "    this.key,\n"
               "    this.control,\n"
               "    this.budget,\n"
               "    this.target, {\n"
               "    this.required = false,\n"
               "  });\n\n"
               "  final String key;\n"
               "  final StudioControl control;\n\n"
               "  /// 建议字数。超了不减分，但转换器会按它裁剪。\n"
               "  final int budget;\n"
               "  final StudioTarget target;\n\n"
               "  /// 存卡前必须填。\n"
               "  final bool required;\n\n"
               "  bool get isList => control == StudioControl.tags || control == StudioControl.list;\n"
               "}\n\n"
               "class StudioModuleSpec {\n"
               "  const StudioModuleSpec(this.id, this.fields);\n\n"
               "  final String id;\n"
               "  final List<StudioFieldSpec> fields;\n\n"
               "  StudioFieldSpec? field(String key) {\n"
               "    for (final field in fields) {\n"
               "      if (field.key == key) return field;\n"
               "    }\n"
               "    return null;\n"
               "  }\n"
               "}\n\n")
    out.append("const studioModules = <StudioModuleSpec>[\n")
    for module, *_ in MODULES:
        out.append(f"  StudioModuleSpec('{module}', [\n")
        for m, key, zh, en, control, budget, target, required in FIELDS:
            if m != module:
                continue
            req = ", required: true" if required else ""
            out.append(
                f"    StudioFieldSpec('{key}', StudioControl.{control}, {budget}, "
                f"StudioTarget.{target}{req}),\n"
            )
        out.append("  ]),\n")
    out.append("];\n\n")

    out.append("/// 模块 id → 它的规格；没有就 null。\n"
               "StudioModuleSpec? studioModule(String id) {\n"
               "  for (final module in studioModules) {\n"
               "    if (module.id == id) return module;\n"
               "  }\n"
               "  return null;\n"
               "}\n\n")
    out.append("/// 模块名。\nString studioModuleLabel(String module, L10n l10n) => switch (module) {\n")
    for module, zh, en, *_ in MODULES:
        out.append(f"  '{module}' => l10n.{module_key(module, '')},\n")
    out.append("  _ => module,\n};\n\n")
    out.append("/// 一句话说明：这一模块管什么。\n"
               "String studioModuleSubtitle(String module, L10n l10n) => switch (module) {\n")
    for module, zh, en, sub_zh, sub_en in MODULES:
        out.append(f"  '{module}' => l10n.{module_key(module, 'Sub')},\n")
    out.append("  _ => '',\n};\n\n")
    out.append("/// 字段名。\n"
               "String studioFieldLabel(String module, String field, L10n l10n) =>\n"
               "    switch ('$module.$field') {\n")
    for module, key, zh, en, *_ in FIELDS:
        out.append(f"      '{module}.{key}' => l10n.{camel(module, key)},\n")
    out.append("      _ => field,\n    };\n\n")
    out.append("/// 一个模块里必填却又空着的字段，存卡前拦一下。\n"
               "List<String> studioMissingRequired(String module, String Function(String key) read) => [\n"
               "  for (final field in studioModule(module)?.fields ?? const <StudioFieldSpec>[])\n"
               "    if (field.required && read(field.key).trim().isEmpty) field.key,\n"
               "];\n")
    return "".join(out)


def arb() -> tuple[dict, dict]:
    zh: dict = {}
    en: dict = {}
    for module, name_zh, name_en, sub_zh, sub_en in MODULES:
        zh[module_key(module, "")] = name_zh
        en[module_key(module, "")] = name_en
        zh[module_key(module, "Sub")] = sub_zh
        en[module_key(module, "Sub")] = sub_en
    for module, key, label_zh, label_en, *_ in FIELDS:
        zh[camel(module, key)] = label_zh
        en[camel(module, key)] = label_en
    for key, text_zh, text_en, placeholders in UI_KEYS:
        zh[key] = text_zh
        en[key] = text_en
        if placeholders:
            meta = {"placeholders": {name: {"type": kind} for name, kind in placeholders.items()}}
            zh[f"@{key}"] = meta
            en[f"@{key}"] = meta
    return zh, en


def write_arb(path: str, data: dict) -> None:
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("{\n")
        items = list(data.items())
        for index, (key, value) in enumerate(items):
            comma = "," if index < len(items) - 1 else ""
            handle.write(f"  {json.dumps(key, ensure_ascii=False)}: {json.dumps(value, ensure_ascii=False)}{comma}\n")
        handle.write("}\n")


def main() -> None:
    dart_path = os.path.join(APP, "lib", "tavern", "tavern_studio_schema.dart")
    with open(dart_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(dart())
    zh, en = arb()
    parts = os.path.join(APP, "lib", "l10n", "parts")
    write_arb(os.path.join(parts, "studio_zh.arb"), zh)
    write_arb(os.path.join(parts, "studio_en.arb"), en)
    print(f"OK: {len(FIELDS)} fields, {len(MODULES)} modules -> schema + {len(zh)} keys x 2")


if __name__ == "__main__":
    main()
