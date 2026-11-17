import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges the macOS Reduce Motion preference into the shared Flutter tree.
///
/// The Runner owns the AppKit dependency. Widgets consume this value through
/// [ValueListenable] and remain independent of macOS APIs.
final class MacReduceMotionPreference extends ValueNotifier<bool> {
  MacReduceMotionPreference({EventChannel? channel})
    : _channel = channel ?? const EventChannel('aggregate/macos_reduce_motion'),
      super(false);

  final EventChannel _channel;
  StreamSubscription<dynamic>? _subscription;

  Future<void> start() async {
    if (_subscription != null) return;

    final firstValue = Completer<void>();
    _subscription = _channel.receiveBroadcastStream().listen(
      (event) {
        if (event is bool) value = event;
        if (!firstValue.isCompleted) firstValue.complete();
      },
      onError: (Object _, StackTrace _) {
        if (!firstValue.isCompleted) firstValue.complete();
      },
      onDone: () {
        if (!firstValue.isCompleted) firstValue.complete();
      },
    );

    // The native stream sends its initial setting when the listener attaches.
    // Keep app startup bounded if the platform channel is unavailable.
    try {
      await firstValue.future.timeout(const Duration(milliseconds: 500));
    } on TimeoutException {
      // False is the safe fallback; a later stream event still updates the UI.
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
