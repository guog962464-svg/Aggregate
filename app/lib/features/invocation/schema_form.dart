import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';

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
    super.dispose();
  }

  bool validate() => formKey.currentState?.validate() ?? true;

  JsonMap arguments() {
    final values = <String, Object?>{};
    for (final entry in properties.entries) {
      final spec = entry.value is Map ? entry.value as Map : const {};
      final type = spec['type'];
      if (type == 'boolean') {
        values[entry.key] = booleans[entry.key] ?? false;
        continue;
      }
      final raw = controllers[entry.key]?.text.trim() ?? '';
      if (raw.isEmpty && !requiredFields.contains(entry.key)) continue;
      values[entry.key] = switch (type) {
        'integer' => int.parse(raw),
        'number' => num.parse(raw),
        _ => raw,
      };
    }
    return values;
  }

  @override
  Widget build(BuildContext context) => Form(
    key: formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              final controller = controllers.putIfAbsent(
                entry.key,
                TextEditingController.new,
              );
              return TextFormField(
                key: Key('field-${entry.key}'),
                controller: controller,
                decoration: InputDecoration(labelText: label),
                keyboardType: type == 'integer' || type == 'number'
                    ? TextInputType.number
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
                  return null;
                },
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ],
    ),
  );
}
