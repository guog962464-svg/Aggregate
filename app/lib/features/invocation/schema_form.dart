import 'dart:convert';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_design_tokens.dart';

const _lazySchemaFieldThreshold = 40;

class SchemaForm extends StatefulWidget {
  const SchemaForm({
    super.key,
    required this.schema,
    this.columnsWhenWide = false,
    this.labelsOutside = false,
    this.glassFields = false,
    this.markRequired = true,
  });
  final JsonMap schema;
  final bool columnsWhenWide;
  final bool labelsOutside;
  final bool glassFields;
  final bool markRequired;
  @override
  State<SchemaForm> createState() => SchemaFormState();
}

class SchemaFormState extends State<SchemaForm> {
  final formKey = GlobalKey<FormState>();
  final controllers = <String, TextEditingController>{};
  final booleans = <String, bool>{};
  final selections = <String, String>{};
  final expandedJsonFields = <String>{};
  final summaryFocus = FocusNode();
  final validationErrors = <String, String>{};
  bool showSummary = false;

  Map<String, Object?> get properties {
    final raw = widget.schema['properties'];
    return raw is Map ? Map<String, Object?>.from(raw) : {};
  }

  List<String> get requiredFields {
    final raw = widget.schema['required'];
    return raw is List ? raw.whereType<String>().toList() : [];
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    summaryFocus.dispose();
    super.dispose();
  }

  bool validate() {
    final allErrors = _validateAllFields();
    final visibleFieldsValid = formKey.currentState?.validate() ?? true;
    final valid = allErrors.isEmpty && visibleFieldsValid;
    setState(() {
      validationErrors
        ..clear()
        ..addAll(allErrors);
      showSummary = !valid;
    });
    if (!valid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) summaryFocus.requestFocus();
      });
    }
    return valid;
  }

  JsonMap arguments() {
    final values = <String, Object?>{};
    for (final entry in properties.entries) {
      final spec = entry.value is Map ? entry.value as Map : const {};
      final type = spec['type'];
      if (type == 'boolean') {
        values[entry.key] = booleans[entry.key] ?? false;
        continue;
      }
      if (selections.containsKey(entry.key)) {
        values[entry.key] = selections[entry.key];
        continue;
      }
      final raw = (controllers[entry.key]?.text ?? _defaultFieldText(type))
          .trim();
      if (raw.isEmpty && !requiredFields.contains(entry.key)) continue;
      values[entry.key] = switch (type) {
        'integer' => int.parse(raw),
        'number' => num.parse(raw),
        'array' || 'object' => jsonDecode(raw),
        _ => raw,
      };
    }
    return values;
  }

  String _defaultFieldText(Object? type) => switch (type) {
    'array' => '[]',
    'object' => '{}',
    _ => '',
  };

  Map<String, String> _validateAllFields() {
    final errors = <String, String>{};
    for (final entry in properties.entries) {
      final error = _fieldError(entry);
      if (error != null) errors[entry.key] = error;
    }
    return errors;
  }

  String _validationSummary() {
    final labels = validationErrors.keys
        .take(3)
        .map((name) {
          final spec = properties[name];
          return spec is Map ? '${spec['title'] ?? name}' : name;
        })
        .join('、');
    final remaining = validationErrors.length - 3;
    return '待检查参数：$labels${remaining > 0 ? '等 $remaining 项' : ''}';
  }

  String? _fieldError(MapEntry<String, Object?> entry, {String? rawValue}) {
    final spec = entry.value is Map ? entry.value as Map : const {};
    final type = spec['type'];
    final required = requiredFields.contains(entry.key);
    final label = '${spec['title'] ?? entry.key}${required ? ' *' : ''}';
    if (type == 'boolean') return null;

    final options = spec['enum'];
    if (type == 'string' &&
        options is List &&
        options.every((item) => item is String)) {
      final selected = selections[entry.key];
      return required && selected == null ? '请选择$label' : null;
    }

    final text =
        (rawValue ?? controllers[entry.key]?.text ?? _defaultFieldText(type))
            .trim();
    if (text.isEmpty) return required ? '请输入$label' : null;
    if (type == 'integer' && int.tryParse(text) == null) return '请输入整数';
    if (type == 'number' && num.tryParse(text) == null) return '请输入数字';
    if (type == 'array' || type == 'object') {
      try {
        final parsed = jsonDecode(text);
        if (type == 'array' && parsed is! List ||
            type == 'object' && parsed is! Map) {
          return 'JSON 类型不正确';
        }
      } on FormatException {
        return '请输入有效 JSON';
      }
    }
    if (spec['enum'] is List && !(spec['enum'] as List).contains(text)) {
      return '请输入列出的选项';
    }
    return null;
  }

  void _formatJson(String name) {
    final controller = controllers[name];
    if (controller == null) return;
    try {
      final decoded = jsonDecode(controller.text);
      final formatted = const JsonEncoder.withIndent('  ').convert(decoded);
      controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      setState(() {});
    } on FormatException {
      // The field validator provides the inline error for malformed JSON.
      formKey.currentState?.validate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = properties.entries.toList(growable: false);
    final lazyFields = entries.length >= _lazySchemaFieldThreshold;
    return Form(
      key: formKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns =
              widget.columnsWhenWide &&
              constraints.maxWidth >= 560 &&
              !lazyFields;
          final columnSpacing = widget.columnsWhenWide ? 18.0 : 16.0;
          final fieldWidth = (constraints.maxWidth - columnSpacing) / 2;
          final fields = switch ((lazyFields, twoColumns)) {
            (true, _) => SizedBox(
              key: const Key('schema-field-list'),
              height: 420,
              child: ListView.builder(
                primary: false,
                padding: EdgeInsets.zero,
                itemCount: entries.length,
                itemBuilder: (context, index) =>
                    _fieldEntry(context, entries[index]),
              ),
            ),
            (false, true) => Wrap(
              spacing: columnSpacing,
              children: [
                for (final entry in entries)
                  SizedBox(
                    width: _usesFullWidth(entry)
                        ? constraints.maxWidth
                        : fieldWidth,
                    child: _fieldEntry(context, entry),
                  ),
              ],
            ),
            _ => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in entries) _fieldEntry(context, entry),
              ],
            ),
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSummary) ...[
                Focus(
                  focusNode: summaryFocus,
                  child: Text(
                    '请检查标红字段后重试。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                if (validationErrors.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _validationSummary(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              if (entries.isEmpty) const Text('此功能不需要参数。'),
              fields,
            ],
          );
        },
      ),
    );
  }

  bool _usesFullWidth(MapEntry<String, Object?> entry) {
    final spec = entry.value is Map ? entry.value as Map : const {};
    return switch (spec['type']) {
      'array' || 'object' || 'boolean' => true,
      _ => false,
    };
  }

  Widget _fieldEntry(BuildContext context, MapEntry<String, Object?> entry) {
    final spec = entry.value is Map ? entry.value as Map : const {};
    final type = spec['type'];
    final required = requiredFields.contains(entry.key);
    final labelBase = '${spec['title'] ?? entry.key}';
    final displayLabel =
        '$labelBase${required && widget.markRequired ? ' *' : ''}';
    final semanticLabel = required && !widget.markRequired
        ? '$labelBase，必填'
        : displayLabel;
    final glassField =
        widget.glassFields &&
        type != 'boolean' &&
        type != 'array' &&
        type != 'object';
    final fieldDecoration = _fieldDecoration(
      context,
      displayLabel: displayLabel,
      spec: spec,
      type: type,
      glassField: glassField,
    );
    final Widget field;
    if (type == 'boolean') {
      field = SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(displayLabel),
        value: booleans[entry.key] ?? false,
        onChanged: (value) => setState(() => booleans[entry.key] = value),
      );
    } else {
      final options = spec['enum'];
      if (type == 'string' &&
          options is List &&
          options.every((item) => item is String)) {
        field = DropdownButtonFormField<String>(
          key: Key('field-${entry.key}'),
          initialValue: selections[entry.key],
          isExpanded: true,
          decoration: fieldDecoration,
          items: [
            for (final option in options.cast<String>())
              DropdownMenuItem(
                value: option,
                child: Text(
                  option,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) => setState(() {
            if (value == null) {
              selections.remove(entry.key);
            } else {
              selections[entry.key] = value;
            }
            if (showSummary) {
              final error = _fieldError(entry);
              if (error == null) {
                validationErrors.remove(entry.key);
              } else {
                validationErrors[entry.key] = error;
              }
            }
          }),
          validator: (_) => _fieldError(entry),
        );
      } else {
        final controller = controllers.putIfAbsent(
          entry.key,
          () => TextEditingController(text: _defaultFieldText(type)),
        );
        field = TextFormField(
          key: Key('field-${entry.key}'),
          controller: controller,
          decoration: fieldDecoration.copyWith(
            helperText: type == 'array' || type == 'object'
                ? '输入 JSON ${type == 'array' ? '数组' : '对象'}'
                : spec['enum'] is List
                ? '可选：${(spec['enum'] as List).join('、')}'
                : null,
            suffixIcon: type == 'array' || type == 'object'
                ? AggregateIconButton(
                    tooltip: '格式化 ${spec['title'] ?? entry.key}',
                    icon: Icons.data_object,
                    onPressed: () => _formatJson(entry.key),
                  )
                : null,
          ),
          minLines: type == 'array' || type == 'object' ? 4 : 1,
          maxLines: type == 'array' || type == 'object'
              ? (expandedJsonFields.contains(entry.key) ? 14 : 6)
              : 1,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          textAlignVertical: type == 'array' || type == 'object'
              ? TextAlignVertical.top
              : null,
          style: type == 'array' || type == 'object'
              ? const TextStyle(fontFamily: 'monospace')
              : null,
          keyboardType: type == 'integer' || type == 'number'
              ? TextInputType.number
              : type == 'array' || type == 'object'
              ? TextInputType.multiline
              : null,
          textInputAction: type == 'array' || type == 'object'
              ? TextInputAction.newline
              : null,
          onChanged: (raw) {
            if (!showSummary) return;
            setState(() {
              final error = _fieldError(entry, rawValue: raw);
              if (error == null) {
                validationErrors.remove(entry.key);
              } else {
                validationErrors[entry.key] = error;
              }
            });
          },
          validator: (raw) => _fieldError(entry, rawValue: raw),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.labelsOutside && type != 'boolean' && !glassField) ...[
          Text(displayLabel, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
        ],
        widget.labelsOutside || glassField
            ? Semantics(label: semanticLabel, child: field)
            : field,
        if (type == 'array' || type == 'object')
          Align(
            alignment: Alignment.centerRight,
            child: AggregateActionButton(
              label: expandedJsonFields.contains(entry.key)
                  ? '收起 JSON 编辑器'
                  : '展开 JSON 编辑器',
              icon: expandedJsonFields.contains(entry.key)
                  ? Icons.unfold_less
                  : Icons.unfold_more,
              style: AggregateActionStyle.quiet,
              onPressed: () => setState(() {
                if (!expandedJsonFields.add(entry.key)) {
                  expandedJsonFields.remove(entry.key);
                }
              }),
            ),
          ),
        SizedBox(height: widget.glassFields ? 7 : 16),
      ],
    );
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String displayLabel,
    required Map spec,
    required Object? type,
    required bool glassField,
  }) {
    if (!glassField) {
      return InputDecoration(
        labelText: widget.labelsOutside ? null : displayLabel,
      );
    }
    final theme = Theme.of(context);
    final tokens =
        theme.extension<GlassDesignTokens>() ??
        GlassDesignTokens.forBrightness(theme.brightness);
    final hint = _glassHint(spec, type);
    final fill = Color.lerp(tokens.inset, tokens.glassTop, .18)!;
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: tokens.line.withValues(alpha: .72)),
    );
    return InputDecoration(
      labelText: displayLabel,
      labelStyle: theme.textTheme.labelSmall?.copyWith(
        fontSize: 10,
        height: 1,
        color: tokens.muted,
      ),
      floatingLabelStyle: theme.textTheme.labelSmall?.copyWith(
        fontSize: 10,
        height: 1,
        color: tokens.muted,
      ),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      hintText: hint,
      hintStyle: theme.textTheme.bodySmall?.copyWith(
        height: 1,
        color: tokens.muted.withValues(alpha: .92),
      ),
      isDense: true,
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      constraints: const BoxConstraints(minHeight: 42),
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: BorderSide(color: tokens.glow, width: 1.25),
      ),
      errorBorder: outline.copyWith(
        borderSide: BorderSide(color: tokens.danger),
      ),
      focusedErrorBorder: outline.copyWith(
        borderSide: BorderSide(color: tokens.danger, width: 1.25),
      ),
      errorStyle: theme.textTheme.bodySmall?.copyWith(
        fontSize: 10,
        color: tokens.danger,
      ),
    );
  }

  String? _glassHint(Map spec, Object? type) {
    final explicitHint = spec['placeholder'] ?? spec['hint'];
    if (explicitHint is String && explicitHint.isNotEmpty) return explicitHint;
    final example =
        spec['example'] ??
        (spec['examples'] is List && (spec['examples'] as List).isNotEmpty
            ? (spec['examples'] as List).first
            : null);
    if (example != null) return '例如 $example';
    return switch (type) {
      'integer' || 'number' => '请输入数字',
      _ => '请输入内容',
    };
  }
}
