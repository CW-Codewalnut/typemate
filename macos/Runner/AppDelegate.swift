import Cocoa
import FlutterMacOS
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate {
  private var overlayPanel: NSPanel?
  private var overlayLabel: NSTextField?
  private var bridgeChannel: FlutterMethodChannel?
  private var isQuitRequestInFlight = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let flutterViewController =
      mainFlutterWindow?.contentViewController as? FlutterViewController
    {
      let channel = FlutterMethodChannel(
        name: "typemate/macos",
        binaryMessenger: flutterViewController.engine.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handleBridgeCall(call: call, result: result)
      }
      bridgeChannel = channel
    }
    // Surface the system Accessibility prompt at launch (it only ever
    // appears once) so the permission exists before the first dictation
    // tries to type into another app.
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Quitting first lets Dart stop the resident speech servers; Dart ends
  /// the process itself, and a delayed force-quit covers an unresponsive
  /// engine.
  override func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    guard let channel = bridgeChannel, !isQuitRequestInFlight else {
      return .terminateNow
    }
    isQuitRequestInFlight = true
    channel.invokeMethod("quitRequested", arguments: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
    return .terminateCancel
  }

  private func handleBridgeCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "showOverlay":
      let arguments = call.arguments as? [String: Any]
      showOverlay(state: arguments?["state"] as? String ?? "listening")
      result(nil)
    case "hideOverlay":
      hideOverlay()
      result(nil)
    case "ensureLaunchAtStartup":
      ensureLaunchAtStartup()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Listening overlay

  /// The dictation pill: a small non-activating panel at the bottom of the
  /// screen. It must never steal focus from the field being typed into.
  private func showOverlay(state: String) {
    let text = state == "transcribing"
      ? "Transcribing locally..." : "TypeMate is listening..."
    if overlayPanel == nil {
      let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false)
      panel.level = .statusBar
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = true
      panel.ignoresMouseEvents = true
      panel.hidesOnDeactivate = false
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

      let content = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 44))
      content.wantsLayer = true
      content.layer?.backgroundColor =
        NSColor(calibratedRed: 31 / 255, green: 34 / 255, blue: 48 / 255, alpha: 0.96).cgColor
      content.layer?.cornerRadius = 22

      let label = NSTextField(labelWithString: text)
      label.textColor = .white
      label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
      label.alignment = .center
      label.frame = NSRect(x: 8, y: 13, width: 204, height: 18)
      label.autoresizingMask = [.width, .minYMargin, .maxYMargin]
      content.addSubview(label)

      panel.contentView = content
      overlayPanel = panel
      overlayLabel = label
    }
    overlayLabel?.stringValue = text
    positionOverlay()
    overlayPanel?.orderFrontRegardless()
  }

  private func positionOverlay() {
    guard let panel = overlayPanel, let screen = NSScreen.main else { return }
    let visibleFrame = screen.visibleFrame
    panel.setFrameOrigin(
      NSPoint(x: visibleFrame.midX - panel.frame.width / 2, y: visibleFrame.minY + 28))
  }

  private func hideOverlay() {
    overlayPanel?.orderOut(nil)
  }

  // MARK: - Launch at login

  /// Registers the installed app as a login item (System Settings > Login
  /// Items). Dart gates this to /Applications so transient builds never
  /// register.
  private func ensureLaunchAtStartup() {
    if #available(macOS 13.0, *) {
      try? SMAppService.mainApp.register()
    }
  }
}
