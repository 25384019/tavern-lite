// 状态字段的类型化编辑：数字按范围、枚举按选项、布尔按开关、列表按条目，
// 文本还是文本。任何时候都能退回到「直接编 JSON」——高级编辑不删。
//
// 校验只在这里做（界面层）：不合法就留在面板上解释，绝不写进去，
// 所以"失败不破坏已有值"是结构上的保证，不是靠小心。
//
// 返回值：null = 取消；raw = 用户要去编 JSON；value = 新值。

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../common/sheet_title_bar.dart';
import '../providers/provider_widgets.dart';
import '../settings/settings_widgets.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';

/// 编辑结果：要么一个新值，要么"转去直接编 JSON"。
class StateEditResult {
  const StateEditResult.value(this.value) : raw = false;
  const StateEditResult.raw() : value = null, raw = true;
  final Object? value;
  final bool raw;
}

/// schema 说这一项是什么。缺省按现有值的形状判断。
String stateValueKind(Object? node, Object? value) {
  final type = switch (node) {
    {'type': final String t} => t,
    _ => '',
  };
  if (node is Map<String, Object?> && node['enum'] is List) return 'enum';
  return switch (type) {
    'boolean' => 'boolean',
    'integer' || 'number' => 'number',
    'array' => 'array',
    'string' => 'string',
    _ => switch (value) {
      bool _ => 'boolean',
      num _ => 'number',
      List _ => 'array',
      String _ => 'string',
      _ => 'json',
    },
  };
}

Future<StateEditResult?> showTavernStateValueEditor(
  BuildContext context, {
  required String title,
  required Object? value,
  required Map<String, Object?>? node,
}) => showModalBottomSheet<StateEditResult>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _StateValueSheet(title: title, value: value, node: node),
);

class _StateValueSheet extends StatefulWidget {
  const _StateValueSheet({
    required this.title,
    required this.value,
    required this.node,
  });

  final String title;
  final Object? value;
  final Map<String, Object?>? node;

  @override
  State<_StateValueSheet> createState() => _StateValueSheetState();
}

class _StateValueSheetState extends State<_StateValueSheet> {
  late final String _kind = stateValueKind(widget.node, widget.value);

  late final _number = TextEditingController(
    text: widget.value is num ? '${widget.value}' : '',
  );
  late final _text = TextEditingController(
    text: widget.value is String ? widget.value! as String : '',
  );
  late final _item = TextEditingController();
  late bool _flag = widget.value == true;
  late final List<String> _items = [
    if (widget.value is List)
      for (final item in widget.value! as List<Object?>)
        if (item is String) item,
  ];
  String? _extension;

  num? get _low => switch (widget.node?['minimum']) {
    final num n => n,
    _ => null,
  };

  num? get _high => switch (widget.node?['maximum']) {
    final num n => n,
    _ => null,
  };

  num get _step => switch (widget.node?['x-dsh-step']) {
    final num n when n > 0 => n,
    _ => 1,
  };

  List<String> get _options => [
    for (final option
        in (widget.node?['enum'] as List<Object?>?) ?? const <Object?>[])
      if (option is String) option,
  ];

  @override
  void dispose() {
    _number.dispose();
    _text.dispose();
    _item.dispose();
    super.dispose();
  }

  /// 现在是几号：范围外的钳回去，没填的用下限。
  num _clamp(num value) {
    final low = _low;
    final high = _high;
    var result = value;
    if (low != null && result < low) result = low;
    if (high != null && result > high) result = high;
    return result;
  }

  void _bump(num by) {
    final current =
        num.tryParse(_number.text.trim()) ??
        (widget.value is num ? widget.value! as num : 0);
    final next = _clamp(current + by);
    setState(
      () => _number.text = next is int || next == next.roundToDouble()
          ? '${next.round()}'
          : '$next',
    );
  }

  /// 保存前把当前的控件读成一个值；不合法的返回 null 并写好 [_extension]。
  Object? _read() {
    switch (_kind) {
      case 'boolean':
        return _flag;
      case 'enum':
        final picked = _options.contains(_text.text) ? _text.text : null;
        if (picked == null) {
          setState(() => _extension = context.l10n.tavernStatePickOne);
          return null;
        }
        return picked;
      case 'number':
        final raw = _number.text.trim();
        final parsed = num.tryParse(raw);
        if (parsed == null) {
          setState(() => _extension = context.l10n.tavernStateNotANumber);
          return null;
        }
        final low = _low;
        final high = _high;
        if ((low != null && parsed < low) || (high != null && parsed > high)) {
          setState(
            () => _extension = context.l10n.tavernStateOutOfRange(
              '${low ?? '—'}',
              '${high ?? '—'}',
            ),
          );
          return null;
        }
        return parsed;
      case 'array':
        return _items.where((item) => item.trim().isNotEmpty).toList();
      default:
        return _text.text;
    }
  }

  void _save() {
    setState(() => _extension = null);
    final value = _read();
    if (value == null && _kind != 'json') return;
    Navigator.of(context).pop(StateEditResult.value(value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dsh = DshColors.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(widget.title),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.node?['description'] case final String note
                        when note.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          note.trim(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: dsh.textTertiary,
                          ),
                        ),
                      ),
                    ..._controls(context, l10n),
                    if (_extension case final message?)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: dsh.danger,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                children: [
                  FilledButton(
                    key: const ValueKey('tavern-state-edit-save'),
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                    child: Text(l10n.commonSave),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    key: const ValueKey('tavern-state-edit-raw'),
                    onPressed: () =>
                        Navigator.of(context).pop(const StateEditResult.raw()),
                    icon: const Icon(AppIcons.code, size: 16),
                    label: Text(l10n.tavernStateEditRaw),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _controls(BuildContext context, L10n l10n) {
    switch (_kind) {
      case 'boolean':
        return [
          SwitchListTile(
            key: const ValueKey('tavern-state-edit-bool'),
            value: _flag,
            onChanged: (on) => setState(() => _flag = on),
            title: Text(l10n.tavernStateYes),
          ),
        ];
      case 'enum':
        return [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              key: const ValueKey('tavern-state-edit-enum'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _options)
                  ChoiceChip(
                    label: Text(option),
                    selected: _text.text == option,
                    onSelected: (_) => setState(() => _text.text = option),
                  ),
              ],
            ),
          ),
        ];
      case 'number':
        final low = _low;
        final high = _high;
        return [
          Row(
            children: [
              IconButton(
                key: const ValueKey('tavern-state-edit-minus'),
                onPressed: () => _bump(-_step),
                icon: const Icon(AppIcons.remove),
              ),
              Expanded(
                child: TextField(
                  key: const ValueKey('tavern-state-edit-number'),
                  controller: _number,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    hintText: low == null || high == null
                        ? null
                        : '$low ~ $high',
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('tavern-state-edit-plus'),
                onPressed: () => _bump(_step),
                icon: const Icon(AppIcons.add),
              ),
            ],
          ),
          if (low != null && high != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.tavernStateRange('$low', '$high'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: DshColors.of(context).textTertiary),
              ),
            ),
        ];
      case 'array':
        return [
          Wrap(
            key: const ValueKey('tavern-state-edit-list'),
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (index, item) in _items.indexed)
                InputChip(
                  label: Text(item),
                  onDeleted: () => setState(() => _items.removeAt(index)),
                  deleteIcon: const Icon(AppIcons.close, size: 14),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('tavern-state-edit-item'),
            controller: _item,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: l10n.tavernStateAddItem,
              suffixIcon: IconButton(
                icon: const Icon(AppIcons.add, size: 18),
                onPressed: () {
                  final text = _item.text.trim();
                  if (text.isEmpty) return;
                  setState(() {
                    _items.add(text);
                    _item.clear();
                  });
                },
              ),
            ),
            onSubmitted: (text) {
              final trimmed = text.trim();
              if (trimmed.isEmpty) return;
              setState(() {
                _items.add(trimmed);
                _item.clear();
              });
            },
          ),
        ];
      default:
        return [
          FormFieldBlock(
            label: l10n.tavernStateEditText,
            child: TextField(
              key: const ValueKey('tavern-state-edit-text'),
              controller: _text,
              minLines: 3,
              maxLines: 8,
            ),
          ),
        ];
    }
  }
}
