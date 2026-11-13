import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var hostIdentityChannel: HostTlsIdentityChannel?
  private var hostSignatureChannel: HostDeviceSignatureChannel?

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

    super.awakeFromNib()
  }
}
