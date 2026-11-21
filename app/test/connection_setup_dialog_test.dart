import 'dart:async';
import 'dart:convert';

import 'package:aggregate/features/connections/connection_setup_dialog.dart';
import 'package:aggregate/app/theme.dart';
import 'package:aggregate/widgets/glass/aggregate_buttons.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aggregate/widgets/glass/glass_motion.dart';
import 'package:flutter/foundation.dart';

final class _SetupFixture
    implements ConnectionSetupPort, ConnectionSetupExecutableSelectionPort {
  _SetupFixture({
    this.withField = false,
    this.withFileContent = false,
    this.music = false,
    this.autoDetect = false,
    this.httpOnly = false,
    this.actionRequired = false,
    this.executionTarget = ExecutionTarget.device,
    this.saveCompleter,
  });
  final bool withField;
  final bool withFileContent;
  final bool music;
  final bool autoDetect;
  final bool httpOnly;
  final bool actionRequired;
  final ExecutionTarget executionTarget;
  final Completer<Connection>? saveCompleter;
  int tests = 0;
  final discarded = <String>[];
  ConnectionSetupDraft? latest;

  @override
  List<ConnectionAdapter> get connectionAdapters => music
      ? const [
          ConnectionAdapter(
            id: 'music',
            label: '网易云音乐',
            kind: ConnectionKind.cli,
            defaultLabel: '网易云音乐',
            autoDetectExecutable: true,
            showGenericCliFields: false,
            fields: [
              SetupField(key: 'appId', label: '开放平台 App ID'),
              SetupField(
                key: 'privateKey',
                label: 'Private Key（PEM）',
                kind: SetupFieldKind.secret,
                hint: 'Private Key 只用于连接配置，不写入连接清单。',
                readFileContent: true,
              ),
            ],
          ),
        ]
      : httpOnly
      ? const [
          ConnectionAdapter(
            id: 'mcp-http',
            label: 'HTTP MCP',
            kind: ConnectionKind.mcpHttp,
          ),
        ]
      : autoDetect
      ? const [
          ConnectionAdapter(
            id: 'detectable',
            label: '可检测程序',
            kind: ConnectionKind.cli,
            autoDetectExecutable: true,
          ),
        ]
      : withFileContent
      ? [
          ConnectionAdapter(
            id: 'host-secret',
            label: 'Host Secret',
            kind: ConnectionKind.mcpHttp,
            executionTarget: ExecutionTarget.host(
              'host-0123456789abcdef0123456789abcdef',
            ),
            fields: [
              SetupField(
                key: 'privateKey',
                label: 'Private Key',
                kind: SetupFieldKind.secret,
                required: true,
                readFileContent: true,
              ),
            ],
          ),
        ]
      : withField
      ? const [
          ConnectionAdapter(
            id: 'special',
            label: '专用适配器',
            kind: ConnectionKind.cli,
            defaultLabel: '专用工具',
            showGenericCliFields: false,
            fields: [
              SetupField(
                key: 'secret',
                label: '令牌',
                kind: SetupFieldKind.secret,
              ),
            ],
          ),
        ]
      : [
          ConnectionAdapter(
            id: 'cli',
            label: '自定义 CLI',
            kind: ConnectionKind.cli,
            executionTarget: executionTarget,
          ),
        ];

  @override
  Future<String?> detectExecutable(String adapterId) async =>
      autoDetect ? '/usr/bin/printf' : null;

  @override
  Future<DetectedExecutableSelection?> detectExecutableSelection(
    String adapterId, {
    String? executableName,
  }) async {
    if (executionTarget.kind == ExecutionTargetKind.host &&
        executableName?.isNotEmpty == true) {
      return const DetectedExecutableSelection(
        displayLocation: 'Mac 主机 · CLI 程序',
        reference: 'host-executable-ref',
      );
    }
    final path = await detectExecutable(adapterId);
    return path == null
        ? null
        : DetectedExecutableSelection(displayLocation: path, path: path);
  }

  @override
  Future<ConnectionSetupReport> testConnectionSetup(
    ConnectionSetupDraft draft,
  ) async {
    tests++;
    latest = draft;
    return ConnectionSetupReport(
      draftId: 'draft-$tests',
      checks: [
        const SetupCheck('连通性', SetupCheckStatus.passed, '程序可启动。'),
        if (actionRequired)
          const SetupCheck(
            '账号登录',
            SetupCheckStatus.actionRequired,
            '保存后在播放器内扫码登录。',
          ),
      ],
      canSave: true,
    );
  }

  @override
  Future<Connection> saveConnectionSetup(String draftId) async =>
      await (saveCompleter?.future ??
          Future.value(
            const Connection(
              id: ConnectionId('saved'),
              kind: ConnectionKind.cli,
              label: '测试工具',
              location: '/usr/bin/printf',
              status: ConnectionStatus.ready,
            ),
          ));

  @override
  Future<void> discardConnectionSetup(String draftId) async {
    discarded.add(draftId);
  }
}

void main() {
  testWidgets('macOS HTTP preview matches the safe memory-only design state', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final setup = _SetupFixture(httpOnly: true);
    await tester.pumpWidget(
      GlassMotionScope(
        child: MaterialApp(
          theme: AggregateTheme.forPlatform(
            AggregateTheme.light,
            TargetPlatform.macOS,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<Connection>(
                  context: context,
                  builder: (_) => ConnectionSetupDialog(
                    setup: setup,
                    initialKind: ConnectionKind.mcpHttp,
                    allowedKinds: const {ConnectionKind.mcpHttp},
                    selectedTargetLabel: '本机 Mac',
                    initialValuesByAdapter: const {
                      'mcp-http': {
                        'label': '项目 MCP',
                        'url': 'https://mcp.example.com',
                        'token': 'preview-token',
                      },
                    },
                  ),
                ),
                child: const Text('打开配置'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开配置'));
    await tester.pumpAndSettle();

    expect(find.text('尚未测试'), findsOneWidget);
    expect(find.text('Bearer Token 仅留在当前进程内存，关闭后丢弃。'), findsOneWidget);
    expect(
      find.byKey(const Key('connection-setup-status-glyph')),
      findsNothing,
    );
    final tokenField = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Bearer Token（可选）',
      ),
    );
    expect(tokenField.controller?.text, 'preview-token');
    expect(tokenField.obscureText, isTrue);
    final saveButton = tester.widget<AggregateActionButton>(
      find
          .ancestor(
            of: find.text('保存连接'),
            matching: find.byType(AggregateActionButton),
          )
          .first,
    );
    expect(saveButton.onPressed, isNull);
    expect(setup.tests, 0);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('macOS music setup keeps the designed path actions and notes', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final setup = _SetupFixture(music: true, autoDetect: true);
    await tester.pumpWidget(
      GlassMotionScope(
        child: MaterialApp(
          theme: AggregateTheme.forPlatform(
            AggregateTheme.light,
            TargetPlatform.macOS,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<Connection>(
                  context: context,
                  builder: (_) => ConnectionSetupDialog(
                    setup: setup,
                    selectedTargetLabel: '本机 Mac',
                    initialValuesByAdapter: const {
                      'music': {
                        'label': '网易云音乐',
                        'executable': '/usr/local/bin/ncm-cli',
                      },
                    },
                  ),
                ),
                child: const Text('打开配置'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开配置'));
    await tester.pumpAndSettle();

    final panel = tester.getRect(
      find.byKey(const Key('connection-setup-panel')),
    );
    Rect fieldRect(String label) {
      return tester.getRect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        ),
      );
    }

    expect(fieldRect('程序').top - panel.top, closeTo(289, .1));
    expect(fieldRect('程序').width, closeTo(488, .1));
    expect(fieldRect('开放平台 App ID').top - panel.top, closeTo(345, .1));
    expect(fieldRect('Private Key（PEM）').top - panel.top, closeTo(401, .1));
    expect(
      tester
          .widget<TextField>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.labelText == '开放平台 App ID',
            ),
          )
          .decoration
          ?.hintText,
      '输入 App ID',
    );
    expect(find.text('程序路径是内存样例；不会检查磁盘或发起登录。'), findsOneWidget);
    expect(find.text('Private Key 只用于连接配置，不写入连接清单。'), findsOneWidget);
    expect(
      find.byKey(const Key('connection-setup-status-glyph')),
      findsNothing,
    );
    expect(find.byTooltip('检测程序'), findsOneWidget);
    expect(find.byTooltip('选择程序绝对路径'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('macOS connection form matches the v9 design board', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final setup = _SetupFixture();
    await tester.pumpWidget(
      GlassMotionScope(
        child: MaterialApp(
          theme: AggregateTheme.forPlatform(
            AggregateTheme.light,
            TargetPlatform.macOS,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<Connection>(
                  context: context,
                  builder: (_) => ConnectionSetupDialog(
                    setup: setup,
                    selectedTargetLabel: '本机 Mac',
                    initialValuesByAdapter: const {
                      'cli': {
                        'label': 'Git CLI',
                        'executable': '/usr/bin/git',
                        'arguments': '[]',
                      },
                    },
                  ),
                ),
                child: const Text('打开配置'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开配置'));
    await tester.pumpAndSettle();

    final panel = tester.getRect(
      find.byKey(const Key('connection-setup-panel')),
    );
    Rect fieldRect(String label) {
      return tester.getRect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        ),
      );
    }

    expect(panel.size, const Size(648, 668));
    expect(panel.left, closeTo(356, .1));
    // Widget tests omit the native title bar; compare content positions to the
    // panel so the same offsets map directly to the 1360×900 Profile window.
    expect(panel.top, closeTo(95.8, .1));
    expect(
      tester.getRect(find.byType(DropdownButtonFormField<String>)).top -
          panel.top,
      closeTo(180, .1),
    );
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.descendant(
              of: find.byType(DropdownButtonFormField<String>),
              matching: find.byType(DropdownButton<String>),
            ),
          )
          .style
          ?.fontSize,
      13,
    );
    for (final (label, top) in [
      ('名称', 233.0),
      ('程序绝对路径', 289.0),
      ('启动参数 JSON 数组', 345.0),
      ('工作目录（可选）', 415.0),
      ('动作清单 JSON（可选）', 471.0),
    ]) {
      expect(fieldRect(label).top - panel.top, closeTo(top, .1), reason: label);
    }
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '工作目录（可选）'))
          .decoration
          ?.hintText,
      '留空使用默认目录',
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '动作清单 JSON（可选）'))
          .decoration
          ?.hintText,
      '选择文件…',
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '名称'))
          .style
          ?.fontSize,
      13,
    );
    expect(
      find.byKey(const Key('connection-setup-status-glyph')),
      findsOneWidget,
    );
    expect(find.text('尚未测试 · 测试通过后才可保存'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '名称'))
          .controller
          ?.text,
      'Git CLI',
    );
    expect(find.text('本机 Mac'), findsOneWidget);
    expect(find.text('第 2 步 · 配置连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android document content stays in memory and clears on close', (
    tester,
  ) async {
    const channel = MethodChannel('aggregate/document_content');
    const fixture = 'A8.3 in-memory private-key fixture';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'pickSmallText');
          return Uint8List.fromList(utf8.encode(fixture));
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final setup = _SetupFixture(withFileContent: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<Connection>(
                context: context,
                builder: (_) => ConnectionSetupDialog(setup: setup),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'HTTP URL'),
      'https://mcp.example.test',
    );
    await tester.tap(find.byTooltip('选择Private Key'));
    await tester.pumpAndSettle();

    final privateKeyField = find.widgetWithText(TextField, 'Private Key');
    final secretController = tester
        .widget<TextField>(privateKeyField)
        .controller!;
    expect(secretController.text, fixture);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(secretController.text, isEmpty);
    expect(setup.latest, isNull);
  });

  testWidgets('actionRequired account check stays visible and incomplete', (
    tester,
  ) async {
    final setup = _SetupFixture(actionRequired: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<Connection>(
                context: context,
                builder: (_) => ConnectionSetupDialog(setup: setup),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '名称'), '网易云音乐');
    await tester.enterText(
      find.widgetWithText(TextField, '程序绝对路径'),
      '/usr/bin/ncm-cli',
    );
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(find.text('待完成 · 账号登录'), findsOneWidget);
    expect(find.text('保存后在播放器内扫码登录。'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.bySemanticsLabel('待完成：账号登录。保存后在播放器内扫码登录。'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存连接'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile form reports invalid fields beside their inputs', (
    tester,
  ) async {
    final setup = _SetupFixture(httpOnly: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<Connection>(
                context: context,
                builder: (_) => ConnectionSetupDialog(
                  setup: setup,
                  initialKind: ConnectionKind.mcpHttp,
                  allowedKinds: const {ConnectionKind.mcpHttp},
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    expect(find.text('请输入连接名称'), findsOneWidget);
    expect(find.text('请输入有效的 HTTP MCP 地址'), findsOneWidget);
    expect(setup.tests, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back cannot dismiss an in-progress save', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final pendingSave = Completer<Connection>();
    final setup = _SetupFixture(saveCompleter: pendingSave);
    Connection? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showDialog<Connection>(
                  context: context,
                  builder: (_) => ConnectionSetupDialog(setup: setup),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '名称'), '测试工具');
    await tester.enterText(
      find.widgetWithText(TextField, '程序绝对路径'),
      '/usr/bin/printf',
    );
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存连接'));
    await tester.pump();
    expect(find.text('正在保存…'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Dialog), findsOneWidget);
    expect(saved, isNull);

    pendingSave.complete(
      const Connection(
        id: ConnectionId('saved'),
        kind: ConnectionKind.cli,
        label: '测试工具',
        location: '/usr/bin/printf',
        status: ConnectionStatus.ready,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(saved?.id.value, 'saved');
    expect(tester.takeException(), isNull);
  });

  testWidgets('save requires a fresh successful connection test', (
    tester,
  ) async {
    final setup = _SetupFixture();
    Connection? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showDialog<Connection>(
                  context: context,
                  builder: (_) => ConnectionSetupDialog(setup: setup),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    FilledButton saveButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存连接'));
    expect(saveButton().onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, '名称'), '测试工具');
    await tester.enterText(
      find.widgetWithText(TextField, '程序绝对路径'),
      '/usr/bin/printf',
    );
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(saveButton().onPressed, isNotNull);
    await tester.enterText(find.widgetWithText(TextField, '名称'), '测试工具 2');
    await tester.pump();
    expect(saveButton().onPressed, isNull);
    expect(setup.discarded, contains('draft-1'));
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存连接'));
    await tester.pumpAndSettle();
    expect(saved?.id.value, 'saved');
  });

  testWidgets('adapter metadata renders and clears a secret field', (
    tester,
  ) async {
    final setup = _SetupFixture(withField: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<Connection>(
                context: context,
                builder: (_) => ConnectionSetupDialog(setup: setup),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('专用工具'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, '程序绝对路径'),
      '/usr/bin/printf',
    );
    final secret = find.widgetWithText(TextField, '令牌');
    expect(tester.widget<TextField>(secret).obscureText, isTrue);
    await tester.enterText(secret, 'fixture-secret');
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(setup.latest?.values['secret'], 'fixture-secret');
    expect(tester.widget<TextField>(secret).controller?.text, isEmpty);
  });

  testWidgets(
    'detectable adapter fills its program path and keeps manual edits',
    (tester) async {
      final setup = _SetupFixture(autoDetect: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<Connection>(
                  context: context,
                  builder: (_) => ConnectionSetupDialog(setup: setup),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, '程序绝对路径');
      expect(
        tester.widget<TextField>(field).controller?.text,
        '/usr/bin/printf',
      );
      expect(find.text('已自动找到官方程序'), findsOneWidget);
      await tester.enterText(field, '/usr/bin/env');
      await tester.tap(find.byTooltip('自动检测程序'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller?.text, '/usr/bin/env');
    },
  );

  testWidgets('phone form finds a Host executable without selecting a path', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final setup = _SetupFixture(
      executionTarget: ExecutionTarget.host('paired-mac-1'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<Connection>(
                context: context,
                builder: (_) => ConnectionSetupDialog(setup: setup),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byTooltip('关闭添加连接'), findsOneWidget);
    expect(find.byIcon(Icons.folder_open_outlined), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, '名称'), 'Mac 工具');
    await tester.enterText(find.widgetWithText(TextField, 'Host 程序名称'), 'git');
    final detect = find.byTooltip('在 Mac Host 查找程序');
    await tester.ensureVisible(detect);
    await tester.tap(detect);
    await tester.pumpAndSettle();
    expect(find.textContaining('实际路径不会传回手机'), findsOneWidget);
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(setup.latest?.spec.executionTarget.hostId, 'paired-mac-1');
    expect(setup.latest?.spec.executable, isNull);
    expect(setup.latest?.executableReference, 'host-executable-ref');
    await tester.tap(find.byTooltip('关闭添加连接'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(setup.discarded, contains('draft-1'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android local CLI field has no document path picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<Connection>(
                context: context,
                builder: (_) => ConnectionSetupDialog(setup: _SetupFixture()),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.folder_open_outlined), findsNothing);
  });

  testWidgets('Android HTTP actions remain above the keyboard inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<Connection>(
                context: context,
                builder: (_) => ConnectionSetupDialog(
                  setup: _SetupFixture(httpOnly: true),
                  initialKind: ConnectionKind.mcpHttp,
                  allowedKinds: const {ConnectionKind.mcpHttp},
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byType(DropdownButtonFormField<String>)).dy,
      greaterThan(tester.getRect(find.byType(AppBar)).bottom),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final saveButton = find.widgetWithText(FilledButton, '保存连接');
    expect(tester.getRect(saveButton).bottom, lessThanOrEqualTo(544));
    expect(find.byTooltip('关闭添加连接'), findsOneWidget);
    expect(
      tester.getRect(find.byTooltip('关闭添加连接')).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
    );
    expect(tester.takeException(), isNull);
  });
}
