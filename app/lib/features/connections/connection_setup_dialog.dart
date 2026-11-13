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
    this.selectedTargetLabel,
    this.allowedKinds = const {
      ConnectionKind.cli,
      ConnectionKind.mcpStdio,
      ConnectionKind.mcpHttp,
    },
  });

  final ConnectionSetupPort setup;
  final ConnectionKind initialKind;
  final String? selectedTargetLabel;
  final Set<ConnectionKind> allowedKinds;

  @override
  State<ConnectionSetupDialog> createState() => _ConnectionSetupDialogState();
}

class _ConnectionSetupDialogState extends State<ConnectionSetupDialog> {
  final formKey = GlobalKey<FormState>();
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
  bool saving = false;
  bool validationAttempted = false;
  int generation = 0;
  int detectionRequest = 0;
  bool detectingExecutable = false;
  String? executableHint;
  DetectedExecutableSelection? detectedExecutable;
  String? detectedExecutableInput;

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

  String? _validateLabel(String? value) =>
      value?.trim().isNotEmpty == true ? null : '请输入连接名称';

  String? _validateExecutable(String? value) {
    if (adapter.kind == ConnectionKind.mcpHttp) return null;
    if (adapter.executionTarget.kind == ExecutionTargetKind.host) {
      return detectedExecutable?.reference?.isNotEmpty == true
          ? null
          : '请先在 Mac Host 查找并确认程序';
    }
    final path = value?.trim() ?? '';
    if (path.isEmpty) return '请选择程序绝对路径';
    if (!path.startsWith('/')) return '请输入程序绝对路径';
    return null;
  }

  String? _validateArguments(String? value) {
    if (adapter.kind == ConnectionKind.mcpHttp ||
        !adapter.showGenericCliFields) {
      return null;
    }
    try {
      final decoded = jsonDecode(value ?? '');
      if (decoded is List && decoded.every((item) => item is String)) {
        return null;
      }
    } on FormatException {
      // Keep malformed JSON as a field-level error.
    }
    return '启动参数必须是 JSON 字符串数组';
  }

  String? _validateUrl(String? value) {
    if (adapter.kind != ConnectionKind.mcpHttp) return null;
    final endpoint = Uri.tryParse(value?.trim() ?? '');
    if (endpoint == null ||
        !endpoint.hasAuthority ||
        !{'http', 'https'}.contains(endpoint.scheme)) {
      return '请输入有效的 HTTP MCP 地址';
    }
    return null;
  }

  void _executableChanged() {
    if (detectedExecutable != null &&
        executable.text != detectedExecutableInput) {
      detectedExecutable = null;
      detectedExecutableInput = null;
      executableHint = null;
    }
  }

  Future<void> _detectExecutable() async {
    final lookupByName =
        adapter.executionTarget.kind == ExecutionTargetKind.host &&
        !adapter.autoDetectExecutable &&
        {ConnectionKind.cli, ConnectionKind.mcpStdio}.contains(adapter.kind);
    if (!adapter.autoDetectExecutable && !lookupByName) return;
    final adapterId = adapter.id;
    final original = executable.text;
    if (lookupByName && original.trim().isEmpty) {
      setState(() => executableHint = '请输入 Mac Host 上的程序名称后再查找');
      return;
    }
    final request = ++detectionRequest;
    setState(() {
      detectingExecutable = true;
      executableHint = adapter.executionTarget.kind == ExecutionTargetKind.host
          ? '正在 Mac Host 上查找程序…'
          : '正在查找已安装的程序…';
    });
    try {
      final DetectedExecutableSelection? selection;
      if (widget.setup case final ConnectionSetupExecutableSelectionPort port) {
        selection = await port.detectExecutableSelection(
          adapterId,
          executableName: lookupByName ? original.trim() : null,
        );
      } else {
        final path = await widget.setup.detectExecutable(adapterId);
        selection = path == null
            ? null
            : DetectedExecutableSelection(displayLocation: path, path: path);
      }
      if (!mounted || request != detectionRequest || adapter.id != adapterId) {
        return;
      }
      final validPath = selection?.path?.startsWith('/') ?? false;
      final validReference = selection?.reference?.isNotEmpty ?? false;
      if (selection != null && (validPath || validReference)) {
        if (executable.text == original && original.isEmpty) {
          if (selection.path != null) {
            detectedExecutable = selection;
            executable.text = selection.path!;
            detectedExecutableInput = executable.text;
          } else if (lookupByName) {
            detectedExecutable = selection;
            detectedExecutableInput = original;
          } else {
            detectedExecutable = selection;
            detectedExecutableInput = selection.displayLocation;
            executable.text = selection.displayLocation;
          }
        } else if (lookupByName && executable.text == original) {
          detectedExecutable = selection;
          detectedExecutableInput = original;
        }
        setState(() {
          executableHint = lookupByName
              ? 'Mac Host 已找到程序；实际路径不会传回手机。'
              : adapter.executionTarget.kind == ExecutionTargetKind.host
              ? 'Mac Host 已找到程序。'
              : executable.text == selection?.path
              ? '已自动找到官方程序'
              : null;
        });
      } else {
        setState(
          () => executableHint =
              adapter.executionTarget.kind == ExecutionTargetKind.host
              ? 'Mac Host 未找到该程序，请检查名称或授权。'
              : '未找到官方程序，请手动选择',
        );
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
    final hostExecutableReference =
        adapter.executionTarget.kind == ExecutionTargetKind.host &&
            kind != ConnectionKind.mcpHttp
        ? detectedExecutable?.reference
        : null;
    if (adapter.executionTarget.kind == ExecutionTargetKind.host &&
        kind != ConnectionKind.mcpHttp &&
        hostExecutableReference == null) {
      throw const FormatException('请先通过 Mac Host 查找并确认程序');
    }
    return ConnectionSetupDraft(
      adapterId: adapter.id,
      executableReference: hostExecutableReference,
      spec: ConnectionSpec(
        kind: kind,
        label: label.text.trim(),
        executionTarget: adapter.executionTarget,
        executable:
            kind == ConnectionKind.mcpHttp || hostExecutableReference != null
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
    setState(() => validationAttempted = true);
    if (formKey.currentState?.validate() != true) return;
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
      saving = true;
      error = null;
    });
    try {
      final connection = await widget.setup.saveConnectionSetup(
        current!.draftId,
      );
      report = null;
      if (mounted) {
        setState(() => saving = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context, connection);
        });
      }
    } on ConnectionSetupOutcomeUnknown {
      if (mounted) {
        setState(() {
          report = null;
          error = '保存结果未知。请先在 Mac Host 检查连接列表，再决定是否重新配置。';
        });
      }
    } catch (_) {
      unawaited(widget.setup.discardConnectionSetup(current!.draftId));
      if (mounted) {
        setState(() {
          report = null;
          error = '保存失败，请重新测试连接后再试。';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          saving = false;
        });
      }
    }
  }

  Widget _field(
    TextEditingController controller,
    String title, {
    bool file = false,
    bool secret = false,
    int lines = 1,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    String? detectTooltip,
    bool readOnly = false,
    VoidCallback? choose,
    VoidCallback? detect,
  }) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: TextFormField(
      controller: controller,
      maxLines: lines,
      readOnly: readOnly,
      keyboardType:
          keyboardType ?? (secret ? TextInputType.visiblePassword : null),
      validator: validator,
      obscureText: secret && lines == 1,
      autocorrect: !secret,
      enableSuggestions: !secret,
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
                      tooltip: detectTooltip ?? '自动检测程序',
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
    final hostTarget = adapter.executionTarget.kind == ExecutionTargetKind.host;
    final hostCommandLookup =
        hostTarget &&
        !adapter.autoDetectExecutable &&
        {ConnectionKind.cli, ConnectionKind.mcpStdio}.contains(adapter.kind);
    final canDetectExecutable =
        adapter.autoDetectExecutable || hostCommandLookup;
    final form = SizedBox(
      width: compact ? double.infinity : 520,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 8),
        child: Form(
          key: formKey,
          autovalidateMode: validationAttempted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.selectedTargetLabel case final targetLabel?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            adapter.executionTarget.kind ==
                                    ExecutionTargetKind.host
                                ? Icons.desktop_mac_outlined
                                : Icons.phone_android_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '执行设备',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium,
                                ),
                                Text(
                                  targetLabel,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
                        if (detectedExecutable != null &&
                            executable.text == detectedExecutableInput) {
                          executable.clear();
                        }
                        detectedExecutable = null;
                        detectedExecutableInput = null;
                        final previousDefault = adapter.defaultLabel;
                        if (previousDefault != null &&
                            label.text == previousDefault) {
                          label.clear();
                        }
                        validationAttempted = false;
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
              _field(label, '名称', validator: _validateLabel),
              if (adapter.kind == ConnectionKind.mcpHttp) ...[
                _field(
                  url,
                  'HTTP URL',
                  keyboardType: TextInputType.url,
                  validator: _validateUrl,
                ),
                _field(
                  token,
                  'Bearer Token（可选）',
                  secret: true,
                  hint: hostTarget
                      ? '经配对通道发送；保存后由 Mac Host 管理凭证。'
                      : '测试时使用，保存后写入当前设备的安全存储。',
                ),
              ] else ...[
                _field(
                  executable,
                  hostTarget
                      ? adapter.autoDetectExecutable
                            ? 'Host 上的程序'
                            : 'Host 程序名称'
                      : '程序绝对路径',
                  file: canChooseRuntimePath,
                  readOnly: hostTarget && adapter.autoDetectExecutable,
                  hint: canDetectExecutable
                      ? executableHint ??
                            (hostCommandLookup
                                ? '输入 Mac Host PATH 中的命令名；不会读取手机文件路径。'
                                : null)
                      : null,
                  detectTooltip: hostTarget ? '在 Mac Host 查找程序' : null,
                  validator: _validateExecutable,
                  detect: canDetectExecutable && !detectingExecutable
                      ? () => unawaited(_detectExecutable())
                      : null,
                ),
                if (adapter.showGenericCliFields) ...[
                  _field(
                    arguments,
                    '启动参数 JSON 数组',
                    lines: 3,
                    keyboardType: TextInputType.multiline,
                    validator: _validateArguments,
                  ),
                  if (!hostTarget) _field(directory, '工作目录（可选）'),
                  if (adapter.kind == ConnectionKind.cli && !hostTarget)
                    _field(
                      manifest,
                      '动作清单 JSON（可选）',
                      file: canChooseRuntimePath,
                    ),
                ],
              ],
              for (final field in adapter.fields)
                _field(
                  extra[field.key]!,
                  field.label,
                  file:
                      field.kind == SetupFieldKind.file && canChooseRuntimePath,
                  secret: field.kind == SetupFieldKind.secret,
                  choose: field.readFileContent
                      ? () => _chooseFieldContent(extra[field.key]!)
                      : null,
                  hint: field.hint,
                  validator: field.required
                      ? (value) => value?.trim().isNotEmpty == true
                            ? null
                            : '请输入${field.label}'
                      : null,
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
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      label:
                          '${_checkStatusLabel(check.status)}：${check.label}。${check.detail}',
                      child: ExcludeSemantics(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              switch (check.status) {
                                SetupCheckStatus.passed =>
                                  Icons.check_circle_outline,
                                SetupCheckStatus.actionRequired =>
                                  Icons.info_outline,
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
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_checkStatusLabel(check.status)} · ${check.label}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                  Text(check.detail),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
              if (error case final message?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final testButton = OutlinedButton(
      onPressed: busy || detectingExecutable ? null : _test,
      child: Text(busy && !saving ? '正在测试…' : '测试连接'),
    );
    final saveButton = FilledButton(
      onPressed: busy || report?.canSave != true ? null : _save,
      child: Text(saving ? '正在保存…' : '保存连接'),
    );
    return PopScope(
      canPop: !saving,
      child: compact
          ? Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(
                    widget.selectedTargetLabel == null
                        ? '添加连接'
                        : '第 2 步 · 配置连接',
                  ),
                  leading: IconButton(
                    tooltip: '关闭添加连接',
                    onPressed: saving ? null : () => Navigator.pop(context),
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
            )
          : AlertDialog(
              title: Text(
                widget.selectedTargetLabel == null ? '添加连接' : '第 2 步 · 配置连接',
              ),
              content: form,
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                testButton,
                saveButton,
              ],
            ),
    );
  }
}

String _checkStatusLabel(SetupCheckStatus status) => switch (status) {
  SetupCheckStatus.passed => '已通过',
  SetupCheckStatus.actionRequired => '待完成',
  SetupCheckStatus.failed => '未通过',
};
