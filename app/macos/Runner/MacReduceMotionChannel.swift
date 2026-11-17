import AppKit
import FlutterMacOS
import Foundation

final class MacReduceMotionChannel {
  private let eventChannel: FlutterEventChannel
  private let streamHandler = ReduceMotionStreamHandler()

  init(messenger: FlutterBinaryMessenger) {
    eventChannel = FlutterEventChannel(
      name: "aggregate/macos_reduce_motion",
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(streamHandler)
  }
}

private final class ReduceMotionStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var observer: NSObjectProtocol?

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    removeObserver()
    eventSink = events

    let workspace = NSWorkspace.shared
    observer = workspace.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: workspace,
      queue: .main
    ) { [weak self] _ in
      self?.publishCurrentValue()
    }
    publishCurrentValue()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    removeObserver()
    eventSink = nil
    return nil
  }

  private func publishCurrentValue() {
    eventSink?(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
  }

  private func removeObserver() {
    if let observer {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      self.observer = nil
    }
  }
}
