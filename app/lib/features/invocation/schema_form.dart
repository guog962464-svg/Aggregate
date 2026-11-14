import 'dart:convert';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

import '../../widgets/glass/aggregate_buttons.dart';

class SchemaForm extends StatefulWidget {
  const SchemaForm({super.key, required this.schema});
  final JsonMap schema;
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
    final valid = formKey.currentState?.validate() ?? true;
    setState(() => showSummary = !valid);
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
      final raw = controllers[entry.key]?.text.trim() ?? '';
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
  Widget build(BuildContext context) => Form(
    key: formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSummary) ...[
          Focus(
            focusNode: summaryFocus,
            child: Text(
              '请检查标红字段后重试。',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (properties.isEmpty) const Text('此功能不需要参数。'),
        for (final entry in properties.entries) ...[
          Builder(
            builder: (context) {
              final spec = entry.value is Map ? entry.value as Map : const {};
              final type = spec['type'];
              final label =
                  '${spec['title'] ?? entry.key}${requiredFields.contains(entry.key) ? ' *' : ''}';
              if (type == 'boolean') {
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(label),
                  value: booleans[entry.key] ?? false,
                  onChanged: (value) =>
                      setState(() => booleans[entry.key] = value),
                );
              }
              final options = spec['enum'];
              if (type == 'string' &&
                  options is List &&
                  options.every((item) => item is String)) {
                return DropdownButtonFormField<String>(
                  key: Key('field-${entry.key}'),
                  initialValue: selections[entry.key],
                  isExpanded: true,
                  decoration: InputDecoration(labelText: label),
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
                  }),
                  validator: (value) =>
                      requiredFields.contains(entry.key) && value == null
                      ? '请选择$label'
                      : null,
                );
              }
              final controller = controllers.putIfAbsent(
                entry.key,
                () => TextEditingController(
                  text: type == 'array'
                      ? '[]'
                      : type == 'object'
                      ? '{}'
                      : '',
                ),
              );
              return TextFormField(
                key: Key('field-${entry.key}'),
                controller: controller,
                decoration: InputDecoration(
                  labelText: label,
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
                validator: (raw) {
                  final text = raw?.trim() ?? '';
                  if (text.isEmpty) {
                    return requiredFields.contains(entry.key)
                        ? '请输入$label'
                        : null;
                  }
                  if (type == 'integer' && int.tryParse(text) == null) {
                    return '请输入整数';
                  }
                  if (type == 'number' && num.tryParse(text) == null) {
                    return '请输入数字';
                  }
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
                  if (spec['enum'] is List &&
                      !(spec['enum'] as List).contains(text)) {
                    return '请输入列出的选项';
                  }
                  return null;
                },
              );
            },
          ),
          if (entry.value is Map &&
              ((entry.value as Map)['type'] == 'array' ||
                  (entry.value as Map)['type'] == 'object'))
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
          const SizedBox(height: 16),
        ],
      ],
    ),
  );
}
