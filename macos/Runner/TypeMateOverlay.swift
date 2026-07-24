import Cocoa

// The dictation overlay: a 210x58 dark pill near the bottom centre with a
// label and seven capsule waveform bars. Geometry, colours, cadence, and
// the appearance chime mirror windows/runner/type_mate_overlay.cpp.
private let overlayWidth: CGFloat = 210
private let overlayHeight: CGFloat = 58
private let overlayMarginBottom: CGFloat = 28
private let tickSeconds: TimeInterval = 0.07

final class TypeMateOverlayView: NSView {
  var state = "listening"
  var tick = 0

  // Keep the Windows top-down bar math (centre line 42px from the top).
  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    let background = NSColor(
      red: 31 / 255.0, green: 34 / 255.0, blue: 48 / 255.0, alpha: 1)
    background.setFill()
    NSBezierPath(
      roundedRect: bounds, xRadius: overlayHeight / 2,
      yRadius: overlayHeight / 2
    ).fill()

    let label =
      state == "transcribing"
      ? "Transcribing locally..." : "TypeMate is listening..."
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.boldSystemFont(ofSize: 11),
      .foregroundColor: NSColor.white,
    ]
    let size = label.size(withAttributes: attributes)
    label.draw(
      at: NSPoint(x: (overlayWidth - size.width) / 2, y: 18 - size.height / 2),
      withAttributes: attributes)

    let accent = NSColor(
      red: 122 / 255.0, green: 139 / 255.0, blue: 255 / 255.0, alpha: 1)
    accent.setFill()
    let barCount = 7
    let barWidth = 5.0
    let gap = 6.0
    let minHeight = 5.0
    let maxHeight = 18.0
    let totalWidth = Double(barCount) * barWidth + Double(barCount - 1) * gap
    let startX = (Double(overlayWidth) - totalWidth) / 2
    let centerY = 42.0
    for i in 0..<barCount {
      // Same wave as Windows and Linux: 0.55 rad per 70 ms frame.
      let phase = Double(tick + i * 2) * 0.55
      let height = minHeight + ((sin(phase) + 1) / 2) * (maxHeight - minHeight)
      let x = startX + Double(i) * (barWidth + gap)
      let y = centerY - height / 2
      NSBezierPath(
        roundedRect: NSRect(x: x, y: y, width: barWidth, height: height),
        xRadius: barWidth / 2, yRadius: barWidth / 2
      ).fill()
    }
  }
}

final class TypeMateOverlay {
  private var panel: NSPanel?
  private var view: TypeMateOverlayView?
  private var timer: Timer?
  private var chime: NSSound?

  func show(state: String) {
    let appearing = panel == nil
    ensurePanel()
    view?.state = state.isEmpty ? "listening" : state
    view?.needsDisplay = true
    panel?.orderFrontRegardless()
    if appearing {
      // Once per appearance, not on the listening->transcribing update.
      playChime()
    }
  }

  func hide() {
    timer?.invalidate()
    timer = nil
    panel?.orderOut(nil)
    panel = nil
    view = nil
  }

  private func ensurePanel() {
    if panel != nil { return }
    let screen =
      NSScreen.main?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 800, height: 600)
    let frame = NSRect(
      x: screen.midX - overlayWidth / 2,
      y: screen.minY + overlayMarginBottom,
      width: overlayWidth, height: overlayHeight)
    // A non-activating borderless panel: visible over everything but never
    // steals focus from the field being dictated into.
    let panel = NSPanel(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.level = .statusBar
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    let view = TypeMateOverlayView(
      frame: NSRect(x: 0, y: 0, width: overlayWidth, height: overlayHeight))
    panel.contentView = view
    self.panel = panel
    self.view = view
    let timer = Timer(timeInterval: tickSeconds, repeats: true) {
      [weak self] _ in
      self?.view?.tick += 1
      self?.view?.needsDisplay = true
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func playChime() {
    guard let data = Data(base64Encoded: overlayChimeWavBase64) else { return }
    chime = NSSound(data: data)
    chime?.play()
  }
}
