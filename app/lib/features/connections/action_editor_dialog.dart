import 'dart:convert';

import 'package:aggregate_connectors/aggregate_connectors.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../widgets/glass/aggregate_buttons.dart';

class ActionEditorDialog extends StatefulWidget {
  const ActionEditorDialog({
    super.key,
    required this.runtime,
    required this.connection,
  });

  final RuntimePort runtime;
  final Connection connection;

  @override
  State<ActionEditorDialog> createState() => _ActionEditorDialogState();
}

class _ActionEditorDialogState extends State<ActionEditorDialog> {
  final manifestText = TextEditingController();
  final sampleText = TextEditingController(text: '{}');
  String? selectedAction;
  String? preview;
  String? error;
  String? notice;
  bool busy = false;
  bool loaded = false;

  static const jsonType = XTypeGroup(label: 'JSON', extensions: ['json']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final existing = await widget.runtime.loadActionManifest(
        widget.connection.id,
      );
      final draft = existing ?? _starterManifest();
      if (!mounted) return;
      setState(() {
        manifestText.text = const JsonEncoder.withIndent('  ').convert(draft);
        loaded = true;
      });
    } catch (cause) {
      if (!mounted) return;
      setState(() {
        manifestText.text = const JsonEncoder.withIndent('  ')
            .convert(_starterManifest());
        loaded = true;
        error = '读取原动作清单失败：$cause。可编辑新清单或导入文件。';
      });
    }
  }

  JsonMap _starterManifest() => {
    'schemaVersion': 1,
    'id': 'local-${widget.connection.id.value}',
    'displayName': widget.connection.label,
    'platforms': ['macos'],
    'executable': widget.connection.location,
    'actions': [
      {
        'id': 'version',
        'title': '查看版本',
        'argv': ['--version'],
        'inputSchema': {
          'type': 'object',
          'properties': <String, Object?>{},
          'required': <String>[],
          'additionalProperties': false,
        },
        'output': 'text',
        'permission': 'read',
        'timeoutMs': 30000,
      },
    ],
  };

  ConnectorManifest _parse() {
    final value = jsonDecode(manifestText.text);
    return ConnectorManifest.fromJson(value);
  }

  List<ConnectorAction> _availableActions() {
    try {
      return _parse().actions;
    } catch (_) {
      return const [];
    }
  }

  void _addAction() {
    try {
      final value = jsonObject(jsonDecode(manifestText.text), 'manifest');
      final actions = value['actions'];
      if (actions is! List) throw const FormatException('actions 必须是数组');
      var number = 1;
      while (actions.any(
        (action) => action is Map && action['id'] == 'action$number',
      )) {
        number++;
      }
      final id = 'action$number';
      actions.add({
        'id': id,
        'title': '新动作',
        'argv': ['--help'],
        'inputSchema': {
          'type': 'object',
          'properties': <String, Object?>{},
          'required': <String>[],
          'additionalProperties': false,
        },
        'output': 'text',
        'permission': 'unknown',
        'timeoutMs': 30000,
      });
      setState(() {
        manifestText.text = const JsonEncoder.withIndent('  ').convert(value);
        selectedAction = id;
        notice = '已加入新动作，请编辑名称、参数数组与输入规则。';
        error = null;
      });
    } catch (cause) {
      setState(() => error = '$cause');
    }
  }

  void _preview() {
    try {
      final manifest = _parse();
      final input = jsonObject(jsonDecode(sampleText.text), 'sample');
      final action = manifest.actions.firstWhere(
        (item) => item.id == (selectedAction ?? manifest.actions.first.id),
      );
      final argv = action.expand(input);
      setState(() {
        selectedAction = action.id;
        preview = const JsonEncoder.withIndent('  ')
            .convert([manifest.executable, ...argv]);
        error = null;
        notice = '清单有效。下方是最终参数数组；此操作不会运行程序。';
      });
    } catch (cause) {
      setState(() {
        error = '$cause';
        preview = null;
      });
    }
  }

  Future<void> _import() async {
    final file = await openFile(acceptedTypeGroups: const [jsonType]);
    if (file == null) return;
    setState(() => busy = true);
    try {
      final value = await widget.runtime.readActionManifestFile(file.path);
      if (!mounted) return;
      setState(() {
        manifestText.text = const JsonEncoder.withIndent('  ').convert(value);
        selectedAction = null;
        preview = null;
        notice = '已读取清单。检查后点击保存动作。';
        error = null;
      });
    } catch (cause) {
      if (mounted) setState(() => error = '$cause');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _export() async {
    try {
      final manifest = _parse();
      final location = await getSaveLocation(
        suggestedName: '${manifest.id}.json',
        acceptedTypeGroups: const [jsonType],
      );
      if (location == null) return;
      setState(() => busy = true);
      await widget.runtime.exportActionManifest(
        widget.connection.id,
        manifest.toJson(),
        location.path,
      );
      if (mounted) {
        setState(() {
          notice = '已导出动作清单。';
          error = null;
        });
      }
    } catch (cause) {
      if (mounted) setState(() => error = '$cause');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      final manifest = _parse();
      await widget.runtime.saveActionManifest(
        widget.connection.id,
        manifest.toJson(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (cause) {
      if (mounted) setState(() => error = '$cause');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    manifestText.dispose();
    sampleText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('编辑动作 · ${widget.connection.label}'),
    content: SizedBox(
      width: 640,
      child: SingleChildScrollView(
        child: !loaded
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '清单版本 1 · 参数以数组传递，{{变量名}} 从输入规则取值。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      AggregateActionButton(
                        label: '新增动作',
                        icon: Icons.add,
                        onPressed: busy ? null : _addAction,
                      ),
                      AggregateActionButton(
                        label: '导入',
                        icon: Icons.file_open_outlined,
                        style: AggregateActionStyle.quiet,
                        onPressed: busy ? null : _import,
                      ),
                      AggregateActionButton(
                        label: '导出',
                        icon: Icons.save_alt,
                        style: AggregateActionStyle.quiet,
                        onPressed: busy ? null : _export,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('action-manifest-json'),
                    controller: manifestText,
                    onChanged: (_) => setState(() => preview = null),
                    maxLines: 14,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      labelText: '动作清单 JSON',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      final actions = _availableActions();
                      final current =
                          actions.any((action) => action.id == selectedAction)
                          ? selectedAction
                          : actions.isEmpty
                          ? null
                          : actions.first.id;
                      return DropdownButtonFormField<String>(
                        key: Key(
                          'preview-action-${current ?? 'none'}-${actions.length}',
                        ),
                        initialValue: current,
                        decoration: const InputDecoration(labelText: '预览动作'),
                        items: [
                          for (final action in actions)
                            DropdownMenuItem(
                              value: action.id,
                              child: Text('${action.title} · ${action.id}'),
                            ),
                        ],
                        onChanged: actions.isEmpty
                            ? null
                            : (value) => setState(() {
                                selectedAction = value;
                                preview = null;
                              }),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: sampleText,
                    maxLines: 3,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      labelText: '预览输入 JSON',
                      helperText: '例如 {"keyword":"示例"}；只预览，不执行。',
                    ),
                  ),
                  const SizedBox(height: 8),
                  AggregateActionButton(
                    label: '检查并预览参数',
                    icon: Icons.preview_outlined,
                    onPressed: busy ? null : _preview,
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      preview!,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                  if (notice != null) ...[
                    const SizedBox(height: 8),
                    Text(notice!),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    ),
    actions: [
      AggregateActionButton(
        label: '取消',
        icon: Icons.close,
        style: AggregateActionStyle.quiet,
        onPressed: busy ? null : () => Navigator.of(context).pop(false),
      ),
      AggregateActionButton(
        label: '保存动作',
        icon: Icons.save_outlined,
        style: AggregateActionStyle.primary,
        onPressed: busy || !loaded ? null : _save,
        enabled: !busy && loaded,
      ),
    ],
  );
}
