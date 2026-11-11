import 'dart:async';
import 'dart:convert';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// Shared form: platform adapters supply the fields and perform the probe.
class ConnectionSetupDialog extends StatefulWidget {
  const ConnectionSetupDialog({
    super.key,
    required this.setup,
    this.initialKind = ConnectionKind.cli,
    this.allowedKinds = const {
      ConnectionKind.cli,
      ConnectionKind.mcpStdio,
      ConnectionKind.mcpHttp,
    },
  });

  final ConnectionSetupPort setup;
  final ConnectionKind initialKind;
  final Set<ConnectionKind> allowedKinds;

  @override
  State<ConnectionSetupDialog> createState() => _ConnectionSetupDialogState();
}

class _ConnectionSetupDialogState extends State<ConnectionSetupDialog> {
  final label = TextEditingController();
  final executable = TextEditingController();
  final arguments = TextEditingController(text: '[]');
  final directory = TextEditingController();
  final url = TextEditingController();
  final manifest = TextEditingController();
  final token = TextEditingController();
  final extra = <String, TextEditingController>{};
  late ConnectionAdapter adapter;
  ConnectionSetupReport? report;
  String? error;
  bool busy = false;
  int generation = 0;
  int detectionRequest = 0;
  bool detectingExecutable = false;
  String? executableHint;
  String? autoDetectedPath;

  @override
  void initState() {
    super.initState();
    final choices = widget.setup.connectionAdapters
        .where((item) => widget.allowedKinds.contains(item.kind))
        .toList();
    adapter = choices.firstWhere(
      (item) => item.kind == widget.initialKind,
      orElse: () => choices.first,
    );
    for (final field in choices.expand((item) => item.fields)) {
      extra.putIfAbsent(field.key, TextEditingController.new);
    }
    for (final controller in _controllers) {
      controller.addListener(_changed);
    }
    executable.addListener(_executableChanged);
    if (adapter.defaultLabel case final value?) label.text = value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_detectExecutable());
    });
  }

  List<TextEditingController> get _controllers => [
    label,
    executable,
    arguments,
    directory,
    url,
    manifest,
    token,
    ...extra.values,
  ];

  void _changed() {
    generation++;
    final old = report;
    report = null;
    error = null;
    if (old?.canSave == true) {
      unawaited(widget.setup.discardConnectionSetup(old!.draftId));
    }
    if (mounted) setState(() {});
  }

  void _executableChanged() {
    if (executable.text != autoDetectedPath) {
      autoDetectedPath = null;
      executableHint = null;
    }
  }

  Future<void> _detectExecutable() async {
    if (!adapter.autoDetectExecutable) return;
    final adapterId = adapter.id;
    final original = executable.text;
    final request = ++detectionRequest;
    setState(() {
      detectingExecutable = true;
      executableHint = '正在查找已安装的程序…';
    });
    try {
      final path = await widget.setup.detectExecutable(adapterId);
      if (!mounted || request != detectionRequest || adapter.id != adapterId) {
        return;
      }
      if (path != null && path.startsWith('/')) {
        if (executable.text == original && original.isEmpty) {
          autoDetectedPath = path;
          executable.text = path;
        }
        setState(
          () => executableHint = executable.text == path ? '已自动找到官方程序' : null,
        );
      } else {
        setState(() => executableHint = '未找到官方程序，请手动选择');
      }
    } catch (_) {
      if (mounted && request == detectionRequest) {
        setState(() => executableHint = '自动检测失败，请手动选择');
      }
    } finally {
      if (mounted && request == detectionRequest) {
        setState(() => detectingExecutable = false);
      }
    }
  }

  @override
  void dispose() {
    detectionRequest++;
    if (report?.canSave == true) {
      unawaited(widget.setup.discardConnectionSetup(report!.draftId));
    }
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _choose(TextEditingController controller) async {
    final file = await openFile();
    if (file != null) controller.text = file.path;
  }

  Future<void> _chooseFieldContent(TextEditingController controller) async {
    final file = await openFile();
    if (file == null) return;
    if (await file.length() > 32 * 1024) {
      setState(() => error = 'Private Key 文件不能超过 32 KiB');
      return;
    }
    controller.text = await file.readAsString();
  }

  ConnectionSetupDraft _draft() {
    if (label.text.trim().isEmpty) {
      throw const FormatException('请输入连接名称');
    }
    List<String> parsed = const [];
    if (adapter.kind != ConnectionKind.mcpHttp &&
        adapter.showGenericCliFields) {
      final decoded = jsonDecode(arguments.text);
      if (decoded is! List || decoded.any((item) => item is! String)) {
        throw const FormatException('启动参数必须是 JSON 字符串数组');
      }
      parsed = decoded.cast<String>();
    }
    for (final field in adapter.fields) {
      if (field.required && extra[field.key]!.text.trim().isEmpty) {
        throw FormatException('请输入${field.label}');
      }
    }
    final kind = adapter.kind;
    return ConnectionSetupDraft(
      adapterId: adapter.id,
      spec: ConnectionSpec(
        kind: kind,
        label: label.text.trim(),
        executionTarget: adapter.executionTarget,
        executable: kind == ConnectionKind.mcpHttp
            ? null
            : executable.text.trim(),
        arguments: parsed,
        workingDirectory:
            !adapter.showGenericCliFields || directory.text.trim().isEmpty
            ? null
            : directory.text.trim(),
        url: kind == ConnectionKind.mcpHttp ? url.text.trim() : null,
        authToken:
            kind == ConnectionKind.mcpHttp && token.text.trim().isNotEmpty
            ? token.text.trim()
            : null,
        manifestPath:
            adapter.kind == ConnectionKind.cli &&
                adapter.showGenericCliFields &&
                manifest.text.trim().isNotEmpty
            ? manifest.text.trim()
            : null,
      ),
      values: {
        for (final field in adapter.fields) field.key: extra[field.key]!.text,
      },
    );
  }

  Future<void> _test() async {
    if (busy) return;
    final current = ++generation;
    setState(() {
      busy = true;
      error = null;
      report = null;
    });
    try {
      final result = await widget.setup.testConnectionSetup(_draft());
      if (!mounted || current != generation) {
        if (result.canSave) {
          await widget.setup.discardConnectionSetup(result.draftId);
        }
        return;
      }
      if (result.canSave) {
        for (final field in adapter.fields) {
          if (field.kind != SetupFieldKind.secret) continue;
          final controller = extra[field.key]!;
          controller.removeListener(_changed);
          controller.clear();
          controller.addListener(_changed);
        }
      }
      setState(() => report = result);
    } catch (cause) {
      if (mounted && current == generation) {
        setState(
          () => error = cause is FormatException
              ? cause.message
              : '测试失败，请检查输入与服务状态。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _save() async {
    final current = report;
    if (busy || current?.canSave != true) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final connection = await widget.setup.saveConnectionSetup(
        current!.draftId,
      );
      report = null;
      if (mounted) Navigator.pop(context, connection);
    } catch (_) {
      if (mounted) setState(() => error = '保存失败，请重试连接测试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String title, {
    bool file = false,
    bool secret = false,
    int lines = 1,
    String? hint,
    VoidCallback? choose,
    VoidCallback? detect,
  }) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: TextField(
      controller: controller,
      maxLines: lines,
      obscureText: secret && lines == 1,
      decoration: InputDecoration(
        labelText: title,
        helperText: hint,
        alignLabelWithHint: lines > 1,
        suffixIcon: file || choose != null || detect != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (detect != null)
                    IconButton(
                      tooltip: '自动检测程序',
                      onPressed: detect,
                      icon: const Icon(Icons.manage_search_outlined),
                    ),
                  if (file || choose != null)
                    IconButton(
                      tooltip: '选择$title',
                      onPressed: choose ?? () => _choose(controller),
                      icon: const Icon(Icons.folder_open_outlined),
                    ),
                ],
              )
            : null,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final choices = widget.setup.connectionAdapters
        .where((item) => widget.allowedKinds.contains(item.kind))
        .toList();
    final compact = MediaQuery.sizeOf(context).width < 600;
    final canChooseRuntimePath =
        adapter.executionTarget.kind == ExecutionTargetKind.device &&
        Theme.of(context).platform != TargetPlatform.android;
    final form = SizedBox(
      width: compact ? double.infinity : 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: adapter.id,
              decoration: const InputDecoration(labelText: '适配器'),
              items: [
                for (final item in choices)
                  DropdownMenuItem(value: item.id, child: Text(item.label)),
              ],
              onChanged: busy
                  ? null
                  : (value) {
                      if (value == null) return;
                      detectionRequest++;
                      detectingExecutable = false;
                      executableHint = null;
                      if (executable.text == autoDetectedPath) {
                        executable.clear();
                      }
                      autoDetectedPath = null;
                      final previousDefault = adapter.defaultLabel;
                      if (previousDefault != null &&
                          label.text == previousDefault) {
                        label.clear();
                      }
                      _changed();
                      setState(
                        () => adapter = choices.firstWhere(
                          (item) => item.id == value,
                        ),
                      );
                      if (adapter.defaultLabel case final value?) {
                        if (label.text.isEmpty) label.text = value;
                      }
                      unawaited(_detectExecutable());
                    },
            ),
            _field(label, '名称'),
            if (adapter.kind == ConnectionKind.mcpHttp) ...[
              _field(url, 'HTTP URL'),
              _field(
                token,
                'Bearer Token（可选）',
                secret: true,
                hint: '测试时使用，保存后写入当前设备的安全存储。',
              ),
            ] else ...[
              _field(
                executable,
                adapter.executionTarget.kind == ExecutionTargetKind.host
                    ? 'Host 程序绝对路径'
                    : '程序绝对路径',
                file: canChooseRuntimePath,
                hint: adapter.autoDetectExecutable ? executableHint : null,
                detect: adapter.autoDetectExecutable && !detectingExecutable
                    ? () => unawaited(_detectExecutable())
                    : null,
              ),
              if (adapter.showGenericCliFields) ...[
                _field(arguments, '启动参数 JSON 数组'),
                _field(directory, '工作目录（可选）'),
                if (adapter.kind == ConnectionKind.cli)
                  _field(manifest, '动作清单 JSON（可选）', file: canChooseRuntimePath),
              ],
            ],
            for (final field in adapter.fields)
              _field(
                extra[field.key]!,
                field.label,
                file: field.kind == SetupFieldKind.file && canChooseRuntimePath,
                secret: field.kind == SetupFieldKind.secret,
                choose: field.readFileContent
                    ? () => _chooseFieldContent(extra[field.key]!)
                    : null,
                hint: field.hint,
              ),
            if (adapter.description case final description?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(description),
              ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
            if (report case final result?) ...[
              const SizedBox(height: 20),
              for (final check in result.checks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        switch (check.status) {
                          SetupCheckStatus.passed => Icons.check_circle_outline,
                          SetupCheckStatus.actionRequired => Icons.info_outline,
                          SetupCheckStatus.failed => Icons.error_outline,
                        },
                        size: 20,
                        color: switch (check.status) {
                          SetupCheckStatus.passed => Theme.of(
                            context,
                          ).colorScheme.primary,
                          SetupCheckStatus.actionRequired => Theme.of(
                            context,
                          ).colorScheme.secondary,
                          SetupCheckStatus.failed => Theme.of(
                            context,
                          ).colorScheme.error,
                        },
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text('${check.label}：${check.detail}')),
                    ],
                  ),
                ),
            ],
            if (error case final message?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
    final testButton = OutlinedButton(
      onPressed: busy || detectingExecutable ? null : _test,
      child: const Text('测试连接'),
    );
    final saveButton = FilledButton(
      onPressed: busy || report?.canSave != true ? null : _save,
      child: const Text('保存连接'),
    );
    if (compact) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('添加连接'),
            leading: IconButton(
              tooltip: '关闭添加连接',
              onPressed: busy ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: form,
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Expanded(child: testButton),
                  const SizedBox(width: 12),
                  Expanded(child: saveButton),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      title: const Text('添加连接'),
      content: form,
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        testButton,
        saveButton,
      ],
    );
  }
}
