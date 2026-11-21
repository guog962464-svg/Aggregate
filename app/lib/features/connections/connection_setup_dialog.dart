import 'dart:async';
import 'dart:convert';

import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/glass/aggregate_buttons.dart';
import '../../widgets/glass/glass_action_button.dart';
import '../../widgets/glass/glass_design_tokens.dart';
import '../../widgets/glass/glass_glyph.dart';
import '../../widgets/glass/glass_motion.dart';
import '../../widgets/glass/glass_panel_surface.dart';

/// Supplies non-sensitive initial values for the isolated UI inspection
/// runtime. Product runtimes do not implement this interface.
abstract interface class ConnectionSetupInspectionSamplesPort {
  Map<String, Map<String, String>> get connectionSetupInitialValues;
}

/// Shared form: platform adapters supply the fields and perform the probe.
class ConnectionSetupDialog extends StatefulWidget {
  const ConnectionSetupDialog({
    super.key,
    required this.setup,
    this.initialKind = ConnectionKind.cli,
    this.selectedTargetLabel,
    this.initialValuesByAdapter = const {},
    this.allowedKinds = const {
      ConnectionKind.cli,
      ConnectionKind.mcpStdio,
      ConnectionKind.mcpHttp,
    },
  });

  final ConnectionSetupPort setup;
  final ConnectionKind initialKind;
  final String? selectedTargetLabel;
  final Map<String, Map<String, String>> initialValuesByAdapter;
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
    _applyInitialValues(adapter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_detectExecutable());
    });
  }

  void _applyInitialValues(ConnectionAdapter selected) {
    final values = widget.initialValuesByAdapter[selected.id] ?? const {};
    label.text = values['label'] ?? selected.defaultLabel ?? '';
    executable.text = values['executable'] ?? '';
    arguments.text = values['arguments'] ?? '[]';
    directory.text = values['directory'] ?? '';
    url.text = values['url'] ?? '';
    token.text = values['token'] ?? '';
    for (final entry in extra.entries) {
      entry.value.text = values[entry.key] ?? '';
    }
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
      controller.removeListener(_changed);
    }
    executable.removeListener(_executableChanged);
    for (final field in adapter.fields) {
      if (field.kind == SetupFieldKind.secret) extra[field.key]?.clear();
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
    if (Theme.of(context).platform == TargetPlatform.android) {
      try {
        final bytes = await const MethodChannel('aggregate/document_content')
            .invokeMethod<Uint8List>('pickSmallText');
        if (bytes == null || !mounted) return;
        if (bytes.length > 32 * 1024) {
          setState(() => error = 'Private Key 文件不能超过 32 KiB');
          return;
        }
        controller.text = utf8.decode(bytes);
      } on PlatformException catch (cause) {
        if (mounted) {
          setState(
            () => error = cause.code == 'file_too_large'
                ? 'Private Key 文件不能超过 32 KiB'
                : '无法读取所选文件，请重新选择。',
          );
        }
      } on FormatException {
        if (mounted) setState(() => error = '所选文件不是有效的 UTF-8 文本。');
      }
      return;
    }

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
    String? placeholder,
    double? topSpacing,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    String? detectTooltip,
    bool readOnly = false,
    VoidCallback? choose,
    VoidCallback? detect,
  }) {
    final macDesign = _isMacDesign(context);
    final tokens = Theme.of(context).extension<GlassDesignTokens>();
    final field = TextFormField(
      controller: controller,
      style: macDesign
          ? Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tokens!.text,
              fontSize: 13,
              height: 18 / 13,
              fontWeight: FontWeight.w500,
            )
          : null,
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
        hintText: macDesign ? placeholder : null,
        helperText: macDesign ? null : hint,
        alignLabelWithHint: lines > 1,
        isDense: macDesign,
        floatingLabelBehavior: macDesign ? FloatingLabelBehavior.always : null,
        contentPadding: macDesign
            ? EdgeInsets.fromLTRB(14, lines > 1 ? 9 : 7, 10, 6)
            : null,
        labelStyle: macDesign
            ? Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontSize: 10, height: 12 / 10)
            : null,
        floatingLabelStyle: macDesign
            ? Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontSize: 10, height: 12 / 10)
            : null,
        filled: macDesign,
        fillColor: macDesign ? tokens!.inset.withValues(alpha: .46) : null,
        enabledBorder: macDesign
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: tokens!.line.withValues(alpha: .72),
                ),
              )
            : null,
        focusedBorder: macDesign
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens!.focusRing, width: 1.2),
              )
            : null,
        border: macDesign
            ? OutlineInputBorder(borderRadius: BorderRadius.circular(12))
            : null,
        suffixIcon: file || choose != null || detect != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (detect != null)
                    _fieldIconButton(
                      context,
                      tooltip: detectTooltip ?? '自动检测程序',
                      icon: Icons.manage_search_outlined,
                      onPressed: detect,
                    ),
                  if (file || choose != null)
                    _fieldIconButton(
                      context,
                      tooltip: '选择$title',
                      icon: Icons.folder_open_outlined,
                      onPressed: choose ?? () => _choose(controller),
                    ),
                ],
              )
            : null,
      ),
    );
    final fieldHeight = macDesign ? (lines > 1 ? 58.0 : 44.0) : null;
    return Padding(
      padding: EdgeInsets.only(top: macDesign ? topSpacing ?? 12 : 16),
      child: macDesign && hint != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: fieldHeight, child: field),
                const SizedBox(height: 6),
                Text(
                  hint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens!.muted,
                    fontSize: 10,
                    height: 14 / 10,
                  ),
                ),
              ],
            )
          : SizedBox(height: fieldHeight, child: field),
    );
  }

  bool _isMacDesign(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.macOS &&
      GlassMotionScope.maybeOf(context) != null &&
      Theme.of(context).extension<GlassDesignTokens>() != null &&
      MediaQuery.sizeOf(context).width >= 760 &&
      MediaQuery.sizeOf(context).height >= 720;

  Widget _fieldIconButton(
    BuildContext context, {
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final button = AggregateIconButton(
      tooltip: tooltip,
      icon: icon,
      onPressed: onPressed,
      size: _isMacDesign(context)
          ? GlassButtonSize.terminalIcon
          : GlassButtonSize.icon,
    );
    return _isMacDesign(context)
        ? SizedBox(width: 36, height: 36, child: button)
        : button;
  }

  Widget _macSetupIconButton(
    BuildContext context, {
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 42,
      height: 44,
      child: Center(
        child: AggregateIconButton(
          tooltip: tooltip,
          icon: icon,
          onPressed: onPressed,
          size: GlassButtonSize.terminalIcon,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final choices = widget.setup.connectionAdapters
        .where((item) => widget.allowedKinds.contains(item.kind))
        .toList();
    final compact = MediaQuery.sizeOf(context).width < 600;
    final macDesign = _isMacDesign(context);
    final tokens = Theme.of(context).extension<GlassDesignTokens>();
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
    final inspectionSample = widget.initialValuesByAdapter.containsKey(
      adapter.id,
    );
    final musicSetup =
        macDesign &&
        adapter.autoDetectExecutable &&
        adapter.fields.any((field) => field.readFileContent);
    final previewMusicSample = musicSetup && inspectionSample;
    final previewHttpSample =
        macDesign && adapter.kind == ConnectionKind.mcpHttp && inspectionSample;
    final form = SizedBox(
      width: compact
          ? double.infinity
          : macDesign
          ? 588
          : 520,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(top: macDesign ? 0 : 8),
        child: Form(
          key: formKey,
          autovalidateMode: validationAttempted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!macDesign && widget.selectedTargetLabel != null)
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
                                  widget.selectedTargetLabel!,
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
              if (macDesign) ...[
                SizedBox(
                  height: 14,
                  child: Text(
                    '适配器',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontSize: 10, height: 14 / 10),
                  ),
                ),
                const SizedBox(height: 2),
              ],
              SizedBox(
                height: macDesign ? 42 : null,
                child: DropdownButtonFormField<String>(
                  initialValue: adapter.id,
                  style: macDesign
                      ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens!.text,
                          fontSize: 13,
                          height: 18 / 13,
                          fontWeight: FontWeight.w500,
                        )
                      : null,
                  decoration: InputDecoration(
                    labelText: macDesign ? null : '适配器',
                    isDense: macDesign,
                    filled: macDesign,
                    fillColor: macDesign
                        ? tokens!.inset.withValues(alpha: .46)
                        : null,
                    contentPadding: macDesign
                        ? const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          )
                        : null,
                    enabledBorder: macDesign
                        ? OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: tokens!.line.withValues(alpha: .72),
                            ),
                          )
                        : null,
                    focusedBorder: macDesign
                        ? OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: tokens!.focusRing,
                              width: 1.2,
                            ),
                          )
                        : null,
                    border: macDesign
                        ? OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          )
                        : null,
                  ),
                  items: [
                    for (final item in choices)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          item.label,
                          style: macDesign
                              ? Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: tokens!.text,
                                      fontSize: 13,
                                      height: 18 / 13,
                                      fontWeight: FontWeight.w500,
                                    )
                              : null,
                        ),
                      ),
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
                          if (widget.initialValuesByAdapter.containsKey(
                            adapter.id,
                          )) {
                            _applyInitialValues(adapter);
                          } else if (adapter.defaultLabel case final value?) {
                            if (label.text.isEmpty) label.text = value;
                          }
                          unawaited(_detectExecutable());
                        },
                ),
              ),
              _field(label, '名称', topSpacing: 11, validator: _validateLabel),
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
                  hint: previewHttpSample
                      ? null
                      : hostTarget
                      ? '经配对通道发送；保存后由 Mac Host 管理凭证。'
                      : inspectionSample
                      ? '安全预览令牌仅在当前进程内存中；关闭后丢弃。'
                      : '测试时使用，保存后写入当前设备的安全存储。',
                ),
              ] else ...[
                if (musicSetup && canChooseRuntimePath) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _field(
                            executable,
                            '程序',
                            topSpacing: 0,
                            validator: _validateExecutable,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _macSetupIconButton(
                          context,
                          tooltip: '检测程序',
                          icon: Icons.search,
                          onPressed: canDetectExecutable && !detectingExecutable
                              ? () => unawaited(_detectExecutable())
                              : null,
                        ),
                        const SizedBox(width: 8),
                        _macSetupIconButton(
                          context,
                          tooltip: '选择程序绝对路径',
                          icon: Icons.folder_open_outlined,
                          onPressed: () => _choose(executable),
                        ),
                      ],
                    ),
                  ),
                ] else
                  _field(
                    executable,
                    adapter.autoDetectExecutable && macDesign
                        ? '程序'
                        : hostTarget
                        ? 'Host 程序名称'
                        : '程序绝对路径',
                    file: canChooseRuntimePath,
                    readOnly: hostTarget && adapter.autoDetectExecutable,
                    hint: canDetectExecutable
                        ? (previewMusicSample
                              ? null
                              : executableHint ??
                                    (inspectionSample &&
                                            adapter.autoDetectExecutable
                                        ? '这是内存预览路径，不会检查本机磁盘。'
                                        : hostCommandLookup
                                        ? '输入 Mac Host PATH 中的命令名；不会读取手机文件路径。'
                                        : null))
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
                  if (!hostTarget)
                    _field(directory, '工作目录（可选）', placeholder: '留空使用默认目录'),
                  if (adapter.kind == ConnectionKind.cli && !hostTarget)
                    _field(
                      manifest,
                      '动作清单 JSON（可选）',
                      file: canChooseRuntimePath,
                      placeholder: '选择文件…',
                    ),
                ],
              ],
              for (final field in adapter.fields)
                if (musicSetup &&
                    canChooseRuntimePath &&
                    field.readFileContent) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _field(
                            extra[field.key]!,
                            field.label,
                            secret: field.kind == SetupFieldKind.secret,
                            topSpacing: 0,
                            placeholder: '选择 .pem 文件',
                            hint: previewMusicSample ? null : field.hint,
                            validator: field.required
                                ? (value) => value?.trim().isNotEmpty == true
                                      ? null
                                      : '请输入${field.label}'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _macSetupIconButton(
                          context,
                          tooltip: '选择${field.label}',
                          icon: Icons.folder_open_outlined,
                          onPressed: () =>
                              _chooseFieldContent(extra[field.key]!),
                        ),
                      ],
                    ),
                  ),
                ] else
                  _field(
                    extra[field.key]!,
                    field.label,
                    file:
                        field.kind == SetupFieldKind.file &&
                        canChooseRuntimePath,
                    secret: field.kind == SetupFieldKind.secret,
                    choose: field.readFileContent
                        ? () => _chooseFieldContent(extra[field.key]!)
                        : null,
                    placeholder: field.readFileContent
                        ? '选择 .pem 文件'
                        : previewMusicSample && field.key == 'appId'
                        ? '输入 App ID'
                        : null,
                    hint: field.hint,
                    validator: field.required
                        ? (value) => value?.trim().isNotEmpty == true
                              ? null
                              : '请输入${field.label}'
                        : null,
                  ),
              if (previewHttpSample && report == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 14,
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: tokens!.warm,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              '尚未测试',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: tokens.warm,
                                    fontSize: 11,
                                    height: 14 / 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Bearer Token 仅留在当前进程内存，关闭后丢弃。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.muted,
                          fontSize: 10,
                          height: 14 / 10,
                        ),
                      ),
                    ],
                  ),
                ),
              if (previewMusicSample)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '程序路径是内存样例；不会检查磁盘或发起登录。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens!.muted,
                          fontSize: 10,
                          height: 14 / 10,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Private Key 只用于连接配置，不写入连接清单。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens!.muted,
                          fontSize: 10,
                          height: 14 / 10,
                        ),
                      ),
                    ],
                  ),
                ),
              if (!macDesign && adapter.description != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(adapter.description!),
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
    final testButton = AggregateActionButton(
      label: '测试连接',
      icon: Icons.refresh,
      onPressed: busy || detectingExecutable ? null : _test,
      enabled: !busy && !detectingExecutable,
      busy: busy && !saving,
      busyLabel: '正在测试…',
      size: macDesign
          ? GlassButtonSize.terminalToolbar
          : GlassButtonSize.secondary,
    );
    final saveButton = AggregateActionButton(
      label: '保存连接',
      icon: Icons.check,
      style: AggregateActionStyle.primary,
      onPressed: busy || report?.canSave != true ? null : _save,
      enabled: !busy && report?.canSave == true,
      busy: saving,
      busyLabel: '正在保存…',
      size: macDesign
          ? GlassButtonSize.terminalToolbar
          : GlassButtonSize.secondary,
    );
    return PopScope(
      canPop: !saving,
      child: macDesign
          ? _macDialog(
              context,
              form,
              testButton,
              saveButton,
              tokens!,
              hideInitialStatus: previewHttpSample || previewMusicSample,
            )
          : compact
          ? Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(
                    widget.selectedTargetLabel == null
                        ? '添加连接'
                        : '第 2 步 · 配置连接',
                  ),
                  leading: AggregateIconButton(
                    tooltip: '关闭添加连接',
                    icon: Icons.close,
                    onPressed: saving ? null : () => Navigator.pop(context),
                    enabled: !saving,
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
                AggregateActionButton(
                  label: '取消',
                  icon: Icons.close,
                  style: AggregateActionStyle.quiet,
                  onPressed: saving ? null : () => Navigator.pop(context),
                  enabled: !saving,
                ),
                testButton,
                saveButton,
              ],
            ),
    );
  }

  Widget _macDialog(
    BuildContext context,
    Widget form,
    Widget testButton,
    Widget saveButton,
    GlassDesignTokens tokens, {
    required bool hideInitialStatus,
  }) {
    return Dialog(
      // The Flutter content view starts below the native title bar. Offset the
      // modal within that view so its frame matches the 1360×900 design board.
      alignment: const Alignment(0, -.202),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        key: const Key('connection-setup-panel'),
        width: 648,
        height: 668,
        child: GlassPanelSurface(
          borderRadius: BorderRadius.circular(18),
          blurSigma: 14,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(30, 20, 30, 35),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 24,
                  child: Text(
                    widget.selectedTargetLabel == null
                        ? '添加连接'
                        : '第 2 步 · 配置连接',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: tokens.text,
                      fontSize: 20,
                      height: 24 / 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                SizedBox(
                  height: 18,
                  child: Text(
                    '填写连接信息，测试通过后即可保存。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.muted,
                      fontSize: 11,
                      height: 18 / 11,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.inset.withValues(alpha: .42),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: tokens.line.withValues(alpha: .7),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          GlassGlyphMark(
                            glyph: GlassGlyph.network,
                            size: 18,
                            color: tokens.ink,
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '执行设备',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: tokens.muted,
                                        fontSize: 10,
                                        height: 13 / 10,
                                      ),
                                ),
                                Text(
                                  widget.selectedTargetLabel ?? '本机 Mac',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: tokens.text,
                                        fontSize: 13,
                                        height: 18 / 13,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 27),
                Expanded(child: form),
                if (report != null || !hideInitialStatus)
                  SizedBox(
                    height: 14,
                    child: Row(
                      children: [
                        GlassGlyphMark(
                          key: const Key('connection-setup-status-glyph'),
                          glyph: GlassGlyph.refresh,
                          size: 14,
                          color: tokens.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            report == null
                                ? '尚未测试 · 测试通过后才可保存'
                                : '测试结果来自当前运行时；保存前请核对连接信息。',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: tokens.muted,
                                  fontSize: 10,
                                  height: 14 / 10,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Divider(height: 1, color: tokens.line.withValues(alpha: .78)),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 91,
                      height: 40,
                      child: AggregateActionButton(
                        label: '取消',
                        icon: Icons.close,
                        style: AggregateActionStyle.quiet,
                        onPressed: saving ? null : () => Navigator.pop(context),
                        enabled: !saving,
                        size: GlassButtonSize.terminalToolbar,
                      ),
                    ),
                    const SizedBox(width: 9),
                    SizedBox(width: 125, height: 40, child: testButton),
                    const SizedBox(width: 9),
                    SizedBox(width: 97, height: 40, child: saveButton),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _checkStatusLabel(SetupCheckStatus status) => switch (status) {
  SetupCheckStatus.passed => '已通过',
  SetupCheckStatus.actionRequired => '待完成',
  SetupCheckStatus.failed => '未通过',
};
