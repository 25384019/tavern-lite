// 编辑一个状态模板：模板名 + 状态项。
//
// 状态项有五种：数字、文本、布尔、枚举、列表。每项都能改名称、内部键、
// 初始值；数字带范围，枚举带选项。存之前跑一遍 stateTemplateIssues，
// 键重复/非法/范围反了都不让存，并说清楚是哪一项。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../tavern/state_templates.dart';
import '../common/app_sheet.dart';
import '../common/sheet_title_bar.dart';
import '../providers/provider_widgets.dart';
import '../settings/settings_widgets.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';

class StateTemplateEditPage extends StatefulWidget {
  const StateTemplateEditPage({super.key, this.template});

  /// null = 新建。
  final StateTemplate? template;

  static Route<StateTemplate> route(StateTemplate? template) =>
      MaterialPageRoute<StateTemplate>(
        builder: (_) => StateTemplateEditPage(template: template),
      );

  @override
  State<StateTemplateEditPage> createState() => _StateTemplateEditPageState();
}

class _StateTemplateEditPageState extends State<StateTemplateEditPage> {
  late final _name = TextEditingController(text: widget.template?.name ?? '');
  late final _id = widget.template?.id ?? newStateTemplateId();
  late List<StateField> _fields = [
    for (final field in widget.template?.fields ?? const <StateField>[])
      field.copy(),
  ];
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  StateTemplate get _template => StateTemplate(
    id: _id,
    name: _name.text.trim().isEmpty ? '状态模板' : _name.text.trim(),
    fields: _fields,
  );

  void _save() {
    final l10n = context.l10n;
    final issues = stateTemplateIssues(_template);
    if (issues.isNotEmpty) {
      setState(() => _error = l10n.stateTemplateIssues(issues.join('；')));
      return;
    }
    Navigator.of(context).pop(_template);
  }

  Future<void> _editField(int index) async {
    final next = await showAppSheet<StateField>(
      context,
      heightFactor: 0.85,
      isScrollControlled: true,
      builder: (_) => _StateFieldSheet(field: _fields[index]),
    );
    if (next == null || !mounted) return;
    setState(() {
      _fields[index] = next;
      _error = null;
    });
  }

  Future<void> _addField() async {
    final next = await showAppSheet<StateField>(
      context,
      heightFactor: 0.85,
      isScrollControlled: true,
      builder: (_) => _StateFieldSheet(
        field: StateField(
          key: 'field${_fields.length + 1}',
          title: context.l10n.stateTemplateNewField,
          type: StateFieldType.number,
          initial: 0,
        ),
      ),
    );
    if (next == null || !mounted) return;
    setState(() {
      _fields.add(next);
      _error = null;
    });
  }

  void _removeField(int index) => setState(() {
    _fields.removeAt(index);
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Stack(
      children: [
        AppPage.list(
          title: widget.template == null
              ? l10n.stateTemplateNew
              : l10n.stateTemplateEdit,
          actions: [
            GlassIconButton(
              key: const ValueKey('state-template-add-field'),
              icon: AppIcons.add,
              tooltip: l10n.stateTemplateAddField,
              onPressed: () => unawaited(_addField()),
            ),
          ],
          children: [
            SettingsSection(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: FormFieldBlock(
                    key: const ValueKey('state-template-name'),
                    label: l10n.stateTemplateName,
                    child: TextField(
                      controller: _name,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: l10n.stateTemplateNameHint,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_fields.isEmpty)
              Padding(
                key: const ValueKey('state-template-fields-empty'),
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
                child: Text(
                  l10n.stateTemplateNoFields,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: DshColors.of(context).textTertiary),
                ),
              )
            else
              SettingsSection(
                title: l10n.stateTemplateFields,
                children: [
                  for (final (index, field) in _fields.indexed)
                    SettingsTile(
                      key: ValueKey('state-template-field-${field.key}'),
                      icon: _iconOf(field.type),
                      tinted: false,
                      title: field.title,
                      subtitle: l10n.stateTemplateFieldSummary(
                        field.key,
                        _typeName(field.type, l10n),
                        _initialText(field),
                      ),
                      trailing: IconButton(
                        key: ValueKey(
                          'state-template-field-remove-${field.key}',
                        ),
                        icon: const Icon(AppIcons.delete, size: 18),
                        onPressed: () => _removeField(index),
                      ),
                      onTap: () => unawaited(_editField(index)),
                    ),
                ],
              ),
            if (_error case final message?)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Text(
                  message,
                  key: const ValueKey('state-template-error'),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: DshColors.of(context).danger),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Text(
                l10n.stateTemplateFieldNote,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DshColors.of(context).textTertiary,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: FormBottomBar.height),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.viewInsetsOf(context).bottom,
          child: FormBottomBar(
            child: FilledButton(
              key: const ValueKey('state-template-save'),
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(l10n.commonSave),
            ),
          ),
        ),
      ],
    );
  }

  static IconData _iconOf(StateFieldType type) => switch (type) {
    StateFieldType.number => AppIcons.chart,
    StateFieldType.boolean => AppIcons.selected,
    StateFieldType.choice => AppIcons.article,
    StateFieldType.list => AppIcons.files,
    StateFieldType.text => AppIcons.edit,
  };

  static String _typeName(StateFieldType type, L10n l10n) => switch (type) {
    StateFieldType.number => l10n.stateFieldTypeNumber,
    StateFieldType.text => l10n.stateFieldTypeText,
    StateFieldType.boolean => l10n.stateFieldTypeBoolean,
    StateFieldType.choice => l10n.stateFieldTypeChoice,
    StateFieldType.list => l10n.stateFieldTypeList,
  };

  static String _initialText(StateField field) => switch (field.toInitial()) {
    final List items => items.isEmpty ? '—' : items.join('、'),
    final Object value => '$value',
    null => '—',
  };
}

/// 一个状态项的编辑面板。
class _StateFieldSheet extends StatefulWidget {
  const _StateFieldSheet({required this.field});

  final StateField field;

  @override
  State<_StateFieldSheet> createState() => _StateFieldSheetState();
}

class _StateFieldSheetState extends State<_StateFieldSheet> {
  late final _key = TextEditingController(text: widget.field.key);
  late final _title = TextEditingController(text: widget.field.title);
  late final _initial = TextEditingController(
    text: switch (widget.field.toInitial()) {
      final List items => items.join('，'),
      final Object value => '$value',
      null => '',
    },
  );
  late final _min = TextEditingController(
    text: widget.field.min?.toString() ?? '',
  );
  late final _max = TextEditingController(
    text: widget.field.max?.toString() ?? '',
  );
  late final _options = TextEditingController(
    text: widget.field.options.join('，'),
  );
  late StateFieldType _type = widget.field.type;
  late bool _hidden = widget.field.hidden;
  late bool _flag = widget.field.toInitial() == true;

  @override
  void dispose() {
    for (final controller in [_key, _title, _initial, _min, _max, _options]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _done() {
    final options = [
      for (final option in _options.text.split(RegExp(r'[,，、]')))
        if (option.trim().isNotEmpty) option.trim(),
    ];
    final template = StateField(
      key: _key.text.trim(),
      title: _title.text.trim().isEmpty ? _key.text.trim() : _title.text.trim(),
      type: _type,
      initial: switch (_type) {
        StateFieldType.boolean => _flag,
        StateFieldType.number =>
          num.tryParse(_initial.text.trim()) ??
              num.tryParse(_min.text.trim()) ??
              0,
        StateFieldType.list => _initial.text,
        _ => _initial.text,
      },
      min: num.tryParse(_min.text.trim()),
      max: num.tryParse(_max.text.trim()),
      options: options,
      hidden: _hidden,
    );
    if (template.key.isEmpty) {
      setState(() {});
      return;
    }
    Navigator.of(context).pop(template);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
            SheetTitleBar(l10n.stateTemplateFieldEdit),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FormFieldBlock(
                      key: const ValueKey('state-field-title'),
                      label: l10n.stateFieldTitle,
                      child: TextField(
                        controller: _title,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    FormFieldBlock(
                      key: const ValueKey('state-field-key'),
                      label: l10n.stateFieldKey,
                      helper: l10n.stateFieldKeyHelp,
                      child: TextField(
                        controller: _key,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedPill<StateFieldType>(
                          key: const ValueKey('state-field-type'),
                          expand: true,
                          segments: [
                            PillSegment(
                              StateFieldType.number,
                              l10n.stateFieldTypeNumber,
                            ),
                            PillSegment(
                              StateFieldType.text,
                              l10n.stateFieldTypeText,
                            ),
                            PillSegment(
                              StateFieldType.boolean,
                              l10n.stateFieldTypeBoolean,
                            ),
                            PillSegment(
                              StateFieldType.choice,
                              l10n.stateFieldTypeChoice,
                            ),
                            PillSegment(
                              StateFieldType.list,
                              l10n.stateFieldTypeList,
                            ),
                          ],
                          selected: _type,
                          onChanged: (type) => setState(() => _type = type),
                        ),
                      ),
                    ),
                    if (_type == StateFieldType.boolean)
                      SettingsSwitchTile(
                        key: const ValueKey('state-field-initial-bool'),
                        title: l10n.stateFieldInitial,
                        value: _flag,
                        onChanged: (on) => setState(() => _flag = on),
                      )
                    else
                      FormFieldBlock(
                        key: const ValueKey('state-field-initial'),
                        label: l10n.stateFieldInitial,
                        helper: _type == StateFieldType.list
                            ? l10n.stateFieldInitialListHelp
                            : null,
                        child: TextField(
                          controller: _initial,
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                    if (_type == StateFieldType.number) ...[
                      FormFieldBlock(
                        key: const ValueKey('state-field-min'),
                        label: l10n.stateFieldMin,
                        child: TextField(
                          controller: _min,
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: true,
                            decimal: true,
                          ),
                        ),
                      ),
                      FormFieldBlock(
                        key: const ValueKey('state-field-max'),
                        label: l10n.stateFieldMax,
                        child: TextField(
                          controller: _max,
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: true,
                            decimal: true,
                          ),
                        ),
                      ),
                    ],
                    if (_type == StateFieldType.choice)
                      FormFieldBlock(
                        key: const ValueKey('state-field-options'),
                        label: l10n.stateFieldOptions,
                        helper: l10n.stateFieldOptionsHelp,
                        child: TextField(controller: _options),
                      ),
                    SettingsSwitchTile(
                      key: const ValueKey('state-field-hidden'),
                      title: l10n.stateFieldHidden,
                      subtitle: l10n.stateFieldHiddenHelp,
                      value: _hidden,
                      onChanged: (on) => setState(() => _hidden = on),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: FilledButton(
                key: const ValueKey('state-field-done'),
                onPressed: _done,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                child: Text(l10n.commonDone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
