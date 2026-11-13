import 'dart:async';

import 'package:aggregate/features/invocation/terminal_page.dart';
import 'package:aggregate_contracts/aggregate_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_view/terminal_view.dart';

void main() {
  testWidgets('mobile toolbar sends terminal keys and Ctrl input', (
    tester,
  ) async {
    _usePhoneSize(tester);
    final runtime = _TerminalRuntime();
    await _showTerminal(tester, runtime, dark: true, textScale: 1.8);

    await tester.tap(find.byTooltip('启用 Ctrl'));
    tester
        .widget<TerminalView>(find.byType(TerminalView))
        .terminal
        .textInput('c');
    await tester.pump();
    await tester.pump();
    await _tapToolbarKey(tester, '方向键上');
    await _tapToolbarKey(tester, '发送 Esc 键');
    await _tapToolbarKey(tester, '发送 Tab 键');

    expect(runtime.writes, ['\x03', '\x1b[A', '\x1b', '\t']);
    expect(find.text('Ctrl 已按下，点按一个按键以发送控制字符'), findsNothing);

    final sizesBeforeRotation = runtime.resizes.length;
    tester.view.physicalSize = const Size(844, 390);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(runtime.resizes.length, greaterThan(sizesBeforeRotation));

    await tester.tap(find.byTooltip('中断程序'));
    await tester.pump();
    expect(runtime.interruptCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(runtime.closeCalls, 1);
  });

  testWidgets('paste sends bounded clipboard text and copy uses selection', (
    tester,
  ) async {
    _usePhoneSize(tester);
    final runtime = _TerminalRuntime();
    String? copiedText;
    var clipboardText = 'paste this';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, Object?>{'text': clipboardText};
      }
      if (call.method == 'Clipboard.setData') {
        copiedText =
            (call.arguments as Map<Object?, Object?>)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _showTerminal(tester, runtime);

    await tester.ensureVisible(find.byKey(const Key('terminal-paste')));
    await tester.tap(find.byKey(const Key('terminal-paste')));
    await tester.pump();
    await tester.pump();
    expect(runtime.writes, ['paste this']);

    clipboardText = List<String>.filled(256 * 1024 + 1, 'x').join();
    await tester.ensureVisible(find.byKey(const Key('terminal-paste')));
    await tester.tap(find.byKey(const Key('terminal-paste')));
    await tester.pump();
    await tester.pump();
    expect(runtime.writes, ['paste this']);
    expect(find.textContaining('粘贴内容超过 256 KiB'), findsOneWidget);

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    view.terminal.write('copy me');
    final buffer = view.terminal.buffer;
    final line = buffer.lines[buffer.cursorY];
    view.controller!.setSelection(
      CellAnchor(0, owner: line),
      CellAnchor(8, owner: line),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('terminal-copy')));
    await tester.tap(find.byKey(const Key('terminal-copy')));
    await tester.pump();
    expect(copiedText, 'copy me');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(runtime.closeCalls, 1);
  });

  testWidgets('stream completion leaves readable output and closes the PTY', (
    tester,
  ) async {
    _usePhoneSize(tester);
    final runtime = _TerminalRuntime();
    await _showTerminal(tester, runtime);

    runtime.output.add('last output');
    await tester.pump();
    await runtime.output.close();
    await tester.pump();
    await tester.pump();
    expect(find.text('终端会话已结束，输出仍可查看。'), findsOneWidget);
    expect(
      tester.widget<TerminalView>(find.byType(TerminalView)).readOnly,
      isTrue,
    );
    expect(runtime.closeCalls, 1);
    expect(runtime.subscriptionCancelled, isTrue);
    final upButton = tester.widget<IconButton>(
      find.byKey(const Key('terminal-key-arrowUp')),
    );
    expect(upButton.onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(runtime.closeCalls, 1);
  });

  testWidgets('failed PTY writes switch the terminal to read-only', (
    tester,
  ) async {
    _usePhoneSize(tester);
    final runtime = _TerminalRuntime()..failWrites = true;
    await _showTerminal(tester, runtime);

    tester
        .widget<TerminalView>(find.byType(TerminalView))
        .terminal
        .textInput('x');
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('终端输入失败'), findsOneWidget);
    expect(
      tester.widget<TerminalView>(find.byType(TerminalView)).readOnly,
      isTrue,
    );
    expect(runtime.closeCalls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

void _usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _showTerminal(
  WidgetTester tester,
  _TerminalRuntime runtime, {
  bool dark = false,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark
          ? ThemeData.dark(useMaterial3: true)
          : ThemeData(useMaterial3: true),
      builder: textScale == 1
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
      home: TerminalPage(
        runtime: runtime,
        command: const CliCommand(ConnectionId('test'), ['--help']),
        source: '配对 Mac',
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  expect(find.byType(TerminalView), findsOneWidget);
  expect(
    tester.widget<TerminalView>(find.byType(TerminalView)).keyboardType,
    TextInputType.text,
  );
  expect(tester.takeException(), isNull);
}

Future<void> _tapToolbarKey(WidgetTester tester, String tooltip) async {
  final finder = find.byTooltip(tooltip);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.pump();
}

final class _TerminalRuntime implements RuntimePort {
  final StreamController<String> output = StreamController<String>();
  final List<String> writes = [];
  final List<(int, int)> resizes = [];
  int interruptCalls = 0;
  int closeCalls = 0;
  bool failWrites = false;
  bool subscriptionCancelled = false;

  _TerminalRuntime() {
    output.onCancel = () => subscriptionCancelled = true;
  }

  @override
  Future<TerminalSession> openTerminal(CliCommand command) async =>
      const TerminalSession('test-session');

  @override
  Stream<String> watchTerminal(TerminalSession session) => output.stream;

  @override
  Future<void> writeTerminal(TerminalSession session, String text) async {
    if (failWrites) throw StateError('write failed');
    writes.add(text);
  }

  @override
  Future<void> resizeTerminal(
    TerminalSession session,
    int columns,
    int rows,
  ) async {
    resizes.add((columns, rows));
  }

  @override
  Future<void> interruptTerminal(TerminalSession session) async {
    interruptCalls++;
  }

  @override
  Future<void> closeTerminal(TerminalSession session) async {
    closeCalls++;
  }

  @override
  bool get isPreview => false;

  @override
  RuntimeFeatures get features => RuntimeFeatures.httpOnly;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
