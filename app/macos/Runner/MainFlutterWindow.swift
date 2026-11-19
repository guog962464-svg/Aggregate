import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var hostIdentityChannel: HostTlsIdentityChannel?
  private var hostSignatureChannel: HostDeviceSignatureChannel?
  private var hostPairingStoreChannel: HostPairingStoreChannel?
  private var hostBonjourChannel: HostBonjourChannel?
  private var reduceMotionChannel: MacReduceMotionChannel?
  private var windowAppearanceChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    hostIdentityChannel = HostTlsIdentityChannel(
      messenger: flutterViewController.engine.binaryMessenger
    )
    hostSignatureChannel = HostDeviceSignatureChannel(
      messenger: flutterViewController.engine.binaryMessenger
    )
    hostPairingStoreChannel = HostPairingStoreChannel(
      messenger: flutterViewController.engine.binaryMessenger
    )
    hostBonjourChannel = HostBonjourChannel(
      messenger: flutterViewController.engine.binaryMessenger
    )
    reduceMotionChannel = MacReduceMotionChannel(
      messenger: flutterViewController.engine.binaryMessenger
    )
    windowAppearanceChannel = FlutterMethodChannel(
      name: "aggregate/macos_window_appearance",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowAppearanceChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setAppearance" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let preference = call.arguments as? String else {
        result(FlutterError(
          code: "invalid_appearance",
          message: "Expected a system, light, or dark appearance value.",
          details: nil
        ))
        return
      }
      switch preference {
      case "system":
        self?.appearance = nil
      case "light":
        self?.appearance = NSAppearance(named: .aqua)
      case "dark":
        self?.appearance = NSAppearance(named: .darkAqua)
      default:
        result(FlutterError(
          code: "invalid_appearance",
          message: "Unsupported appearance value: \(preference)",
          details: nil
        ))
        return
      }
      result(nil)
    }

    super.awakeFromNib()
  }

}
