import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Shared keyboard convention for the device showing the Flutter UI.
/// The RuntimePort may execute on another machine, so shortcuts follow the
/// UI platform rather than the runtime's location.
final class ShortcutScheme {
  const ShortcutScheme(this.platform);

  final TargetPlatform platform;

  bool get usesCommand =>
      platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;

  SingleActivator get search => SingleActivator(
    LogicalKeyboardKey.keyK,
    meta: usesCommand,
    control: !usesCommand,
  );

  SingleActivator get run => SingleActivator(
    LogicalKeyboardKey.enter,
    meta: usesCommand,
    control: !usesCommand,
  );

  String get searchLabel => usesCommand ? '⌘ K' : 'Ctrl+K';
  String get runLabel => usesCommand ? '⌘ ↵' : 'Ctrl+Enter';
}
