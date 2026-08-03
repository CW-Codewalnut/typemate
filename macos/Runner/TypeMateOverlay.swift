import Cocoa

// The dictation overlay: a 210x58 dark pill near the bottom centre with a
// label and seven capsule waveform bars. Geometry, colours, and cadence
// mirror windows/runner/type_mate_overlay.cpp. Dictation sounds are
// Dart-side (lib/src/core/platform/dictation_sounds.dart).
private let overlayWidth: CGFloat = 210
private let overlayHeight: CGFloat = 58
// The error toast is a capsule sized to its sentence: text wraps at this
// width, and padding completes the pill.
private let errorMaxTextWidth: CGFloat = 360
private let errorPadX: CGFloat = 24
private let errorPadY: CGFloat = 13
private let errorMinHeight: CGFloat = 44
private let errorAutoHideSeconds: TimeInterval = 4.5
private let overlayMarginBottom: CGFloat = 28
private let tickSeconds: TimeInterval = 0.07

private let errorTextAttributes: [NSAttributedString.Key: Any] = {
  let paragraph = NSMutableParagraphStyle()
  paragraph.alignment = .center
  paragraph.lineBreakMode = .byWordWrapping
  return [
    .font: NSFont.boldSystemFont(ofSize: 11),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
  ]
}()

private func errorTextSize(_ message: String) -> CGSize {
  let bounds = message.boundingRect(
    with: NSSize(width: errorMaxTextWidth, height: .greatestFiniteMagnitude),
    options: [.usesLineFragmentOrigin],
    attributes: errorTextAttributes)
  return CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
}

final class TypeMateOverlayView: NSView {
  var state = "listening"
  var message = ""
  var tick = 0

  // Keep the Windows top-down bar math (centre line 42px from the top).
  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    let isError = state == "error"
    // The error toast is a red pill with the failure sentence; everything
    // else is the dark pill with the animated bars.
    let background = isError
      ? NSColor(red: 96 / 255.0, green: 28 / 255.0, blue: 34 / 255.0, alpha: 1)
      : NSColor(red: 31 / 255.0, green: 34 / 255.0, blue: 48 / 255.0, alpha: 1)
    background.setFill()
    NSBezierPath(
      roundedRect: bounds, xRadius: bounds.height / 2,
      yRadius: bounds.height / 2
    ).fill()

    if isError {
      // Centered both ways: the panel was sized from this same measured
      // text, so the rect just re-centers the measured block.
      let size = errorTextSize(message)
      let textRect = NSRect(
        x: (bounds.width - size.width) / 2,
        y: (bounds.height - size.height) / 2,
        width: size.width, height: size.height)
      message.draw(in: textRect, withAttributes: errorTextAttributes)
      return
    }

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
  private var hideTimer: Timer?
  private var panelIsError = false

  func show(state: String, message: String = "") {
    let resolvedState = state.isEmpty ? "listening" : state
    let isError = resolvedState == "error"
    // The error panel is sized to its message; entering (or leaving) the
    // error state recreates the panel. The waveform states share one
    // fixed-size panel with no flicker.
    if panel != nil && (isError || panelIsError) { hide() }
    ensurePanel(isError: isError, message: message)
    view?.state = resolvedState
    view?.message = message
    view?.needsDisplay = true
    panel?.orderFrontRegardless()
    hideTimer?.invalidate()
    hideTimer = nil
    if isError {
      // The toast dismisses itself, matching the Windows auto-hide; a
      // newer non-error overlay replaces the panel and cancels this.
      let hideTimer = Timer(
        timeInterval: errorAutoHideSeconds, repeats: false
      ) { [weak self] _ in
        if self?.panelIsError == true { self?.hide() }
      }
      RunLoop.main.add(hideTimer, forMode: .common)
      self.hideTimer = hideTimer
    }
  }

  func hide() {
    timer?.invalidate()
    timer = nil
    hideTimer?.invalidate()
    hideTimer = nil
    panel?.orderOut(nil)
    panel = nil
    view = nil
  }

  private func ensurePanel(isError: Bool, message: String = "") {
    if panel != nil { return }
    panelIsError = isError
    let textSize = isError ? errorTextSize(message) : .zero
    let width = isError
      ? textSize.width + 2 * errorPadX : overlayWidth
    let height = isError
      ? max(errorMinHeight, textSize.height + 2 * errorPadY) : overlayHeight
    let screen =
      NSScreen.main?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 800, height: 600)
    let frame = NSRect(
      x: screen.midX - width / 2,
      y: screen.minY + overlayMarginBottom,
      width: width, height: height)
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
      frame: NSRect(x: 0, y: 0, width: width, height: height))
    panel.contentView = view
    self.panel = panel
    self.view = view
    // The error toast is static text; only the waveform states animate.
    if !isError {
      let timer = Timer(timeInterval: tickSeconds, repeats: true) {
        [weak self] _ in
        self?.view?.tick += 1
        self?.view?.needsDisplay = true
      }
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
    }
  }
}
