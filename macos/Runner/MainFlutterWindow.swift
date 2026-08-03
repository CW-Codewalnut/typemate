import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let overlay = TypeMateOverlay()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let channel = FlutterMethodChannel(
      name: "typemate/macos",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "showOverlay":
        let arguments = call.arguments as? [String: Any]
        let state = arguments?["state"] as? String ?? "listening"
        let message = arguments?["message"] as? String ?? ""
        self?.overlay.show(state: state, message: message)
        result(nil)
      case "hideOverlay":
        self?.overlay.hide()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
