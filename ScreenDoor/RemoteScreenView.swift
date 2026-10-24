import SwiftUI
import UIKit
import RoyalVNCKit

struct RemoteScreen: UIViewRepresentable {
    let model: SessionModel

    func makeUIView(context: Context) -> RemoteScreenView {
        RemoteScreenView(model: model)
    }

    func updateUIView(_ view: RemoteScreenView, context: Context) {
        view.apply(mode: model.mode)
        view.setKeyboardActive(model.isKeyboardActive)
        view.setControlsTop(model.controlsTop)
        view.setTabletopFold(model.tabletopFold)
        view.setScreenAreaBottom(model.screenAreaBottom)
        view.setTrackpadFrame(model.trackpadFrame)
        // Read here, not later, so SwiftUI calls this again when they change.
        let canTakeFocus = model.status == .connected && model.credentialRequest == nil && !model.isKeyboardActive
        if canTakeFocus { view.claimKeyboardFocus() }
    }
}

/// Shows the Mac's screen in a zoomable scroll view and turns touches into pointer events.
///
/// On Vision Pro, Mouse mode points directly: you look at something and tap to click it, instead of
/// dragging the pointer across the screen like a trackpad.
final class RemoteScreenView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate, UIPointerInteractionDelegate {
    private let model: SessionModel
    private let scrollView = UIScrollView()
    private let screenView = UIView()
    private let cursorLayer = CALayer()
    /// The MacBook deck's trackpad, below the keyboard when iPhone Duo is propped up like a laptop.
    /// It doesn't take touches, so they reach this view's Mouse gestures.
    private let trackpadSurface = UIView()
    private let keyInput: KeyInputView

    private var mode: InputMode = .view
    private var cursorPosition = CGPoint.zero
    private var cursorHotspot = CGPoint.zero
    private var pendingFramebuffer: VNCFramebuffer?
    private var displayLink: CADisplayLink?
    private var hasFittedOnce = false
    /// Height at the bottom covered by the controls and, when it's up, the keyboard.
    private var obscuredBottom: CGFloat = 0
    /// Top edge of the bottom controls, in window coordinates. Zero when there are none.
    private var controlsTop: CGFloat = 0
    /// While iPhone Duo is propped up like a laptop, the fold. The screen goes above it.
    private var tabletopFold: CGRect?
    /// Where the MacBook deck wants its trackpad, in window coordinates.
    private var trackpadFrame: CGRect?
    /// While folding toward the laptop pose, where the screen area ends. It follows the hinge.
    private var screenAreaBottom: CGFloat?
    /// Where the user last clicked, or tapped in Look around mode, in screen coordinates. This is
    /// usually the text field they're about to type in, so it's what stays above the keyboard.
    private var focusPoint: CGPoint?

    // Mouse-mode gestures
    private lazy var movePan = UIPanGestureRecognizer(target: self, action: #selector(handleMove(_:)))
    private lazy var scrollPan = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
    private lazy var dragPress = UILongPressGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
    private lazy var clickTap = UITapGestureRecognizer(target: self, action: #selector(handleClick(_:)))
    private lazy var rightClickTap = UITapGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
    private lazy var pointerRightClick = UITapGestureRecognizer(target: self, action: #selector(handlePointerRightClick(_:)))
    private lazy var hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
    private lazy var zoomPinch = UIPinchGestureRecognizer(target: self, action: #selector(handleZoomPinch(_:)))
    // View-mode gestures
    private lazy var zoomTap = UITapGestureRecognizer(target: self, action: #selector(handleZoomTap(_:)))
    private lazy var focusTap = UITapGestureRecognizer(target: self, action: #selector(handleFocusTap(_:)))

    private var mouseGestures: [UIGestureRecognizer] {
        // Pointing directly, a one-finger drag scrolls, so there's no trackpad-style pointer movement.
        (Platform.isVision ? [] : [movePan])
            + [scrollPan, zoomPinch, dragPress, clickTap, rightClickTap, pointerRightClick, hover]
    }

    private let clickFeedback = Haptic(.light)
    private let rightClickFeedback = Haptic(.rigid)
    private let dragFeedback = Haptic(.medium)
    private let edgeFeedback = Haptic(.soft)
    private var isCursorAtEdge = false

    private var lastPanTranslation = CGPoint.zero
    private var lastDragLocation = CGPoint.zero
    private var scrollRemainder = CGPoint.zero
    /// What a two-finger gesture in Mouse mode turned out to be. It's decided once, early,
    /// so scrolling the Mac and zooming the view never happen at the same time.
    private enum TwoFingerIntent { case undecided, scroll, zoom }
    private var twoFingerIntent = TwoFingerIntent.undecided
    private var zoomBase: CGFloat = 1
    private var momentumLink: CADisplayLink?
    private var momentumVelocity = CGPoint.zero
    /// Whether the Mac's pointer is the text cursor (I-beam), meaning it's over something you can type in.
    private var isTextCursor = false
    private var lastTouchWasPointer = false
    /// Pointing directly, a touch and hold only becomes a drag once it moves. Letting go without
    /// moving right-clicks instead.
    private var dragStart: CGPoint?

    init(model: SessionModel) {
        self.model = model
        self.keyInput = KeyInputView(model: model)
        super.init(frame: .zero)
        backgroundColor = .black

        scrollView.delegate = self
        scrollView.backgroundColor = .black
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        addSubview(scrollView)

        trackpadSurface.isUserInteractionEnabled = false
        trackpadSurface.backgroundColor = UIColor(white: 1, alpha: 0.06)
        trackpadSurface.layer.cornerRadius = 28
        trackpadSurface.layer.cornerCurve = .continuous
        trackpadSurface.layer.borderWidth = 1
        trackpadSurface.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        trackpadSurface.alpha = 0
        addSubview(trackpadSurface)

        screenView.layer.magnificationFilter = .linear
        screenView.layer.minificationFilter = .trilinear
        screenView.isAccessibilityElement = true
        screenView.accessibilityLabel = "Screen of \(model.host.displayName)"
        scrollView.addSubview(screenView)

        cursorLayer.zPosition = 10
        showDefaultCursor()
        screenView.layer.addSublayer(cursorLayer)

        addSubview(keyInput)

        configureGestures()

        model.onFramebufferUpdate = { [weak self] framebuffer in
            self?.pendingFramebuffer = framebuffer
        }
        model.onCursorUpdate = { [weak self] cursor in
            self?.updateCursorImage(cursor)
        }
        // Mid-session, show the screen straight away instead of waiting for it to change.
        pendingFramebuffer = model.latestFramebuffer
        if let cursor = model.latestCursor { updateCursorImage(cursor) }
        addInteraction(UIPointerInteraction(delegate: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(renderIfNeeded))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if window == nil {
            displayLink?.invalidate()
            displayLink = nil
            stopMomentum()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let oldSize = scrollView.bounds.size
        var screenArea = bounds
        if let screenAreaBottom {
            screenArea.size.height = min(bounds.height, max(0, screenAreaBottom))
        }
        scrollView.frame = screenArea
        layoutTrackpad()
        if oldSize != screenArea.size {
            updateZoomLimits(refit: !hasFittedOnce || scrollView.zoomScale <= scrollView.minimumZoomScale + 0.001)
        }
    }

    private func layoutTrackpad() {
        guard tabletopFold != nil, let trackpadFrame, window != nil else {
            trackpadSurface.alpha = 0
            return
        }
        trackpadSurface.frame = convert(trackpadFrame, from: nil)
        trackpadSurface.alpha = 1
    }

    func setTrackpadFrame(_ frame: CGRect?) {
        guard frame != trackpadFrame else { return }
        trackpadFrame = frame
        layoutTrackpad()
    }

    /// Called with the fold while iPhone Duo is propped up like a laptop, and nil otherwise.
    func setTabletopFold(_ fold: CGRect?) {
        guard fold != tabletopFold else { return }
        tabletopFold = fold
        layoutTrackpad()
        setControlsTop(controlsTop)
    }

    /// Follows the hinge. Updates arrive at the system's pace, so each one eases into place.
    func setScreenAreaBottom(_ bottom: CGFloat?) {
        guard bottom != screenAreaBottom else { return }
        screenAreaBottom = bottom
        // The screen area changes size, so the screen refits to it unless it's zoomed in.
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction]) {
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
        setControlsTop(controlsTop)
    }

    // MARK: Rendering

    /// Coalesces framebuffer updates to at most one image per display refresh.
    @objc private func renderIfNeeded() {
        guard let framebuffer = pendingFramebuffer else { return }
        pendingFramebuffer = nil

        let size = framebuffer.cgSize
        if screenView.bounds.size != size {
            // The Mac's resolution changed. A view's frame can't be set while the zoom transform
            // is applied, so drop back to 1× first and fit the new size afterwards.
            scrollView.minimumZoomScale = min(scrollView.minimumZoomScale, 1)
            scrollView.maximumZoomScale = max(scrollView.maximumZoomScale, 1)
            scrollView.zoomScale = 1
            screenView.frame = CGRect(origin: .zero, size: size)
            scrollView.contentSize = size
            cursorPosition = CGPoint(x: size.width / 2, y: size.height / 2)
            focusPoint = nil
            positionCursorLayer()
            hasFittedOnce = false
            updateZoomLimits(refit: true)
            matchWindowToScreen(size)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        screenView.layer.contents = framebuffer.cgImage
        CATransaction.commit()
    }

    private func updateCursorImage(_ cursor: VNCCursor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if cursor.isEmpty {
            showDefaultCursor()
            isTextCursor = false
        } else {
            cursorLayer.contents = cursor.cgImage
            cursorLayer.bounds = CGRect(origin: .zero, size: cursor.cgSize)
            cursorHotspot = cursor.cgHotspot
            let visible = cursor.cgImage.flatMap { image in
                // The hotspot is in the cursor's points, which may not be the image's pixels.
                Self.visibleBounds(of: image).map { bounds in
                    let scale = CGFloat(image.width) / max(cursor.cgSize.width, 1)
                    return CGRect(x: bounds.minX / scale, y: bounds.minY / scale,
                                  width: bounds.width / scale, height: bounds.height / scale)
                }
            }
            isTextCursor = visible.map { Self.looksLikeTextCursor(visible: $0, hotspot: cursor.cgHotspot) } ?? false
            CursorLog.record(size: cursor.cgSize, visible: visible, hotspot: cursor.cgHotspot, isText: isTextCursor)
        }
        positionCursorLayer()
        CATransaction.commit()
    }

    /// VNC doesn't say what's under the pointer, but its shape does. The text cursor (I-beam) is
    /// tall and narrow with its hotspot in the middle. Arrows and the pointing hand have theirs at
    /// the tip, and crosshairs and most resize cursors are about as wide as they are tall.
    /// macOS pads pointer images, so this looks at the visible part, not the whole image.
    static func looksLikeTextCursor(visible: CGRect, hotspot: CGPoint) -> Bool {
        guard visible.width > 0, visible.height > 0 else { return false }
        let x = (hotspot.x - visible.minX) / visible.width
        let y = (hotspot.y - visible.minY) / visible.height
        return visible.width <= visible.height * 0.6 && (0.2...0.8).contains(x) && (0.3...0.7).contains(y)
    }

    /// The box around the pointer's non-transparent pixels, in the image's pixels.
    static func visibleBounds(of image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, width * height <= 256 * 256 else { return nil }
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where alpha[y * width + x] > 32 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        // Rows in the bitmap run top to bottom, like the pointer's hotspot.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Some servers don't send a cursor shape. Draw a standard arrow so mouse mode always has a pointer.
    private func showDefaultCursor() {
        let config = UIImage.SymbolConfiguration(pointSize: 30, weight: .regular)
        guard let arrow = UIImage(systemName: "cursorarrow", withConfiguration: config) else { return }
        let size = CGSize(width: arrow.size.width + 4, height: arrow.size.height + 4)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let white = arrow.withTintColor(.white, renderingMode: .alwaysOriginal)
            for dx in [-1.5, 0, 1.5] { for dy in [-1.5, 0, 1.5] {
                white.draw(at: CGPoint(x: 2 + dx, y: 2 + dy))
            } }
            arrow.withTintColor(.black, renderingMode: .alwaysOriginal).draw(at: CGPoint(x: 2, y: 2))
        }
        cursorLayer.contents = image.cgImage
        cursorLayer.contentsScale = image.scale
        cursorLayer.bounds = CGRect(origin: .zero, size: size)
        cursorHotspot = CGPoint(x: size.width * 0.3, y: size.height * 0.14)
    }

    private func positionCursorLayer() {
        cursorLayer.anchorPoint = .zero
        cursorLayer.position = CGPoint(x: cursorPosition.x - cursorHotspot.x,
                                       y: cursorPosition.y - cursorHotspot.y)
    }

    /// On Vision Pro, shapes the window like the Mac's screen, with no black bars, and keeps that
    /// shape when you resize it.
    private func matchWindowToScreen(_ size: CGSize) {
        #if os(visionOS)
        guard let scene = window?.windowScene, size.width > 0, size.height > 0 else { return }
        let width = max(bounds.width, 960)
        scene.requestGeometryUpdate(.Vision(size: CGSize(width: width, height: width * size.height / size.width),
                                            resizingRestrictions: .uniform))
        #endif
    }

    // MARK: Zooming

    private func updateZoomLimits(refit: Bool) {
        let content = screenView.bounds.size
        let area = scrollView.bounds.size
        guard content.width > 0, area.width > 0, area.height > 0 else { return }
        let fit = min(area.width / content.width, area.height / content.height)
        scrollView.minimumZoomScale = fit
        scrollView.maximumZoomScale = max(fit * 8, 2)
        if refit {
            scrollView.zoomScale = fit
            hasFittedOnce = true
        } else if scrollView.zoomScale < fit {
            scrollView.zoomScale = fit
        }
        centerContent()
        if refit {
            // The whole screen fits, so show all of it. The old scroll position belongs to the old
            // size, and as the screen area shrinks toward the fold it would cut off the top.
            scrollView.contentOffset = clampedOffset(CGPoint(x: -scrollView.contentInset.left,
                                                             y: -scrollView.contentInset.top))
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { screenView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    /// Keeps the screen centered when it's smaller than the viewport.
    private func centerContent() {
        let content = screenView.frame.size
        let area = scrollView.bounds.size
        let insetX = max(0, (area.width - content.width) / 2)
        let insetY = max(0, (area.height - content.height) / 2)
        // The extra bottom inset lets the screen slide up above the keyboard.
        scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY + obscuredBottom, right: insetX)
    }

    /// Called with the top edge of the bottom controls, in window coordinates. The controls ride on
    /// top of the keyboard, so this also tracks the keyboard.
    func setControlsTop(_ controlsTop: CGFloat) {
        guard window != nil else { return }
        self.controlsTop = controlsTop
        // Below the fold, the controls cover the deck, not the screen.
        let bottom = convert(scrollView.frame, to: nil).maxY
        let newValue = controlsTop > 0 ? max(0, bottom - controlsTop) : 0
        guard abs(newValue - obscuredBottom) > 0.5 else { return }
        obscuredBottom = newValue
        UIView.animate(withDuration: 0.35, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.centerContent()
            self.keepVisible(self.focusPoint ?? self.cursorPosition, animated: false)
        }
    }

    @objc private func handleZoomTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale * 1.05 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: screenView)
            let scale = min(scrollView.minimumZoomScale * 2.5, scrollView.maximumZoomScale)
            let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
            scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
        }
    }

    // MARK: Modes

    func apply(mode newMode: InputMode) {
        guard newMode != mode else { return }
        mode = newMode
        stopMomentum()
        let isMouse = newMode == .mouse
        mouseGestures.forEach { $0.isEnabled = isMouse }
        zoomTap.isEnabled = !isMouse
        focusTap.isEnabled = !isMouse
        // In mouse mode, one finger drives the pointer, so the view follows the pointer instead of panning.
        scrollView.panGestureRecognizer.isEnabled = !isMouse
        // Zooming in mouse mode goes through `zoomPinch`, which waits to see if two fingers mean scroll.
        scrollView.pinchGestureRecognizer?.isEnabled = !isMouse
        scrollView.bounces = !isMouse
        if isMouse {
            model.mouseMove(to: cursorPosition)
            keepCursorVisible(animated: true)
        }
    }

    /// Called from SwiftUI's view update. Showing or hiding the keyboard animates and lays out the
    /// window, and doing that inside the update can send SwiftUI into an update cycle, so wait
    /// until the update has finished.
    func setKeyboardActive(_ active: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.model.isKeyboardActive == active else { return }
            if active, !self.keyInput.isFirstResponder {
                self.keyInput.becomeFirstResponder()
            } else if !active, self.keyInput.isFirstResponder {
                _ = self.keyInput.resignFirstResponder()
                self.claimKeyboardFocus()
            }
        }
    }

    /// While the on-screen keyboard is hidden, this view holds keyboard focus, so a hardware
    /// keyboard on iPad or Vision Pro types on the Mac without opening it.
    override var canBecomeFirstResponder: Bool { true }

    func claimKeyboardFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, self.model.status == .connected,
                  self.model.credentialRequest == nil, !self.model.isKeyboardActive,
                  !self.isFirstResponder, !self.keyInput.isFirstResponder else { return }
            self.becomeFirstResponder()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = keyInput.send(presses, down: true)
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = keyInput.send(presses, down: false)
        if !unhandled.isEmpty { super.pressesEnded(unhandled, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = keyInput.send(presses, down: false)
        if !unhandled.isEmpty { super.pressesCancelled(unhandled, with: event) }
    }

    // MARK: Gestures

    private func configureGestures() {
        zoomTap.numberOfTapsRequired = 2
        screenView.addGestureRecognizer(zoomTap)
        focusTap.require(toFail: zoomTap)
        screenView.addGestureRecognizer(focusTap)
        screenView.isUserInteractionEnabled = true

        movePan.maximumNumberOfTouches = 1
        movePan.allowedScrollTypesMask = []

        // Pointing directly, a pinch and drag scrolls, as it does everywhere on Vision Pro.
        scrollPan.minimumNumberOfTouches = Platform.isVision ? 1 : 2
        scrollPan.maximumNumberOfTouches = Platform.isVision ? 1 : 2
        scrollPan.allowedScrollTypesMask = .all

        dragPress.minimumPressDuration = 0.35
        dragPress.allowableMovement = 12

        rightClickTap.numberOfTouchesRequired = 2
        clickTap.require(toFail: rightClickTap)

        pointerRightClick.buttonMaskRequired = .secondary

        for gesture in mouseGestures {
            gesture.delegate = self
            gesture.isEnabled = false
            addGestureRecognizer(gesture)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // On Vision Pro, a tap lands where you look, so it's handled like a click from a trackpad.
        let isPointer = touch.type == .indirectPointer || Platform.isVision
        // `buttonMaskRequired` only applies to trackpads and mice. Without this check, a plain
        // finger tap also satisfies the secondary-button recognizer and becomes a right-click.
        if gestureRecognizer === pointerRightClick { return touch.type == .indirectPointer }
        // A finger on the glass catches a flick, like on any iOS scroll view.
        stopMomentum()
        lastTouchWasPointer = isPointer
        clickFeedback.prepare()
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Both see every two-finger gesture, and `twoFingerIntent` decides which one acts.
        (gestureRecognizer === scrollPan && other === zoomPinch)
            || (other === scrollPan && gestureRecognizer === zoomPinch)
            || gestureRecognizer === hover || other === hover
    }

    /// Converts a finger movement on the glass into a pointer movement on the Mac.
    private func pointerDelta(for translation: CGPoint) -> CGPoint {
        let scale = scrollView.zoomScale
        let speed = hypot(translation.x, translation.y)
        // Gentle acceleration: slow moves are precise, fast flicks cover more ground.
        let gain = 1.2 + min(speed / 18, 1.6)
        return CGPoint(x: translation.x / scale * gain, y: translation.y / scale * gain)
    }

    private func moveCursor(by delta: CGPoint) {
        let size = screenView.bounds.size
        cursorPosition.x = min(max(cursorPosition.x + delta.x, 0), size.width - 1)
        cursorPosition.y = min(max(cursorPosition.y + delta.y, 0), size.height - 1)
        let atEdge = cursorPosition.x <= 0 || cursorPosition.y <= 0
            || cursorPosition.x >= size.width - 1 || cursorPosition.y >= size.height - 1
        if atEdge, !isCursorAtEdge { edgeFeedback.play() }
        isCursorAtEdge = atEdge
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        positionCursorLayer()
        CATransaction.commit()
        keepCursorVisible(animated: false)
    }

    @objc private func handleMove(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            lastPanTranslation = .zero
        case .changed:
            let translation = gesture.translation(in: self)
            let step = CGPoint(x: translation.x - lastPanTranslation.x, y: translation.y - lastPanTranslation.y)
            lastPanTranslation = translation
            moveCursor(by: pointerDelta(for: step))
            model.mouseMove(to: cursorPosition)
        default:
            break
        }
    }

    @objc private func handleDrag(_ gesture: UILongPressGestureRecognizer) {
        let location = gesture.location(in: self)
        if Platform.isVision {
            handleDirectDrag(gesture)
            return
        }
        switch gesture.state {
        case .began:
            lastDragLocation = location
            dragFeedback.play()
            model.mouseDown(.left, at: cursorPosition)
        case .changed:
            let step = CGPoint(x: location.x - lastDragLocation.x, y: location.y - lastDragLocation.y)
            lastDragLocation = location
            moveCursor(by: pointerDelta(for: step))
            model.mouseMove(to: cursorPosition)
        default:
            dragFeedback.play(intensity: 0.5)
            model.mouseUp(.left, at: cursorPosition)
        }
    }

    /// Touch and hold where you look, then drag to select or move things. Hold and let go to right-click.
    private func handleDirectDrag(_ gesture: UILongPressGestureRecognizer) {
        let point = clampedToScreen(gesture.location(in: screenView))
        switch gesture.state {
        case .began:
            dragStart = point
            pointAt(point)
        case .changed:
            if let start = dragStart {
                let distance = hypot(point.x - start.x, point.y - start.y) * scrollView.zoomScale
                guard distance > 8 else { return }
                dragStart = nil
                model.mouseDown(.left, at: start)
            }
            pointAt(point)
        case .ended:
            if dragStart != nil {
                model.click(.right, at: cursorPosition)
            } else {
                model.mouseUp(.left, at: cursorPosition)
            }
            dragStart = nil
        default:
            if dragStart == nil { model.mouseUp(.left, at: cursorPosition) }
            dragStart = nil
        }
    }

    /// Moves the Mac's pointer straight to a point on its screen.
    private func pointAt(_ point: CGPoint) {
        cursorPosition = point
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        positionCursorLayer()
        CATransaction.commit()
        model.mouseMove(to: point)
    }

    private func clampedToScreen(_ point: CGPoint) -> CGPoint {
        let size = screenView.bounds.size
        return CGPoint(x: min(max(point.x, 0), max(size.width - 1, 0)),
                       y: min(max(point.y, 0), max(size.height - 1, 0)))
    }

    @objc private func handleClick(_ gesture: UITapGestureRecognizer) {
        if lastTouchWasPointer {
            pointAt(clampedToScreen(gesture.location(in: screenView)))
        }
        clickFeedback.play()
        model.click(.left, at: cursorPosition)
        setFocus(cursorPosition)
        // Clicking with the text cursor almost always means a text field. Open the keyboard for it,
        // unless the MacBook deck's keyboard is already there.
        if isTextCursor, !model.isKeyboardActive, tabletopFold == nil {
            model.isKeyboardActive = true
        }
    }

    /// In Look around mode a tap doesn't click, but it still marks the spot to keep above the
    /// keyboard. At the Mac's login screen, for example, the password field already has focus.
    @objc private func handleFocusTap(_ gesture: UITapGestureRecognizer) {
        setFocus(gesture.location(in: screenView))
    }

    private func setFocus(_ point: CGPoint) {
        focusPoint = point
        if obscuredBottom > 0 { keepVisible(point, animated: true) }
    }

    @objc private func handleRightClick(_ gesture: UITapGestureRecognizer) {
        rightClickFeedback.play()
        model.click(.right, at: cursorPosition)
    }

    @objc private func handlePointerRightClick(_ gesture: UITapGestureRecognizer) {
        cursorPosition = gesture.location(in: screenView)
        positionCursorLayer()
        rightClickFeedback.play()
        model.click(.right, at: cursorPosition)
    }

    /// A trackpad or mouse attached to an iPad moves the Mac's pointer directly.
    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        cursorPosition = gesture.location(in: screenView)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        positionCursorLayer()
        CATransaction.commit()
        model.mouseMove(to: cursorPosition)
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            scrollRemainder = .zero
            lastPanTranslation = .zero
            // Scroll whatever you're looking at.
            if Platform.isVision { pointAt(clampedToScreen(gesture.location(in: screenView))) }
        case .changed:
            let translation = gesture.translation(in: self)
            if twoFingerIntent == .undecided {
                if isPinching {
                    twoFingerIntent = .zoom
                } else if hypot(translation.x, translation.y) > 10 {
                    twoFingerIntent = .scroll
                }
            }
            guard twoFingerIntent == .scroll else {
                lastPanTranslation = translation
                return
            }
            sendScroll(CGPoint(x: translation.x - lastPanTranslation.x, y: translation.y - lastPanTranslation.y))
            lastPanTranslation = translation
        case .ended:
            if twoFingerIntent == .scroll { startMomentum(gesture.velocity(in: self)) }
            twoFingerGestureEnded()
        default:
            twoFingerGestureEnded()
        }
    }

    /// Turns finger travel into scroll wheel steps on the Mac.
    private func sendScroll(_ delta: CGPoint) {
        scrollRemainder.x += delta.x
        scrollRemainder.y += delta.y
        let stepSize: CGFloat = 10
        let vertical = Int(scrollRemainder.y / stepSize)
        if vertical != 0 {
            // Natural scrolling: fingers moving down reveal content above.
            model.scroll(vertical > 0 ? .up : .down, steps: UInt32(abs(vertical)), at: cursorPosition)
            scrollRemainder.y -= CGFloat(vertical) * stepSize
        }
        let horizontal = Int(scrollRemainder.x / stepSize)
        if horizontal != 0 {
            model.scroll(horizontal > 0 ? .left : .right, steps: UInt32(abs(horizontal)), at: cursorPosition)
            scrollRemainder.x -= CGFloat(horizontal) * stepSize
        }
    }

    // MARK: Momentum

    /// Keeps scrolling after a flick, slowing down the way iOS scroll views do.
    private func startMomentum(_ velocity: CGPoint) {
        stopMomentum()
        var velocity = velocity
        // A mostly vertical flick shouldn't drift sideways, and the other way round.
        if abs(velocity.y) > abs(velocity.x) * 2 { velocity.x = 0 }
        else if abs(velocity.x) > abs(velocity.y) * 2 { velocity.y = 0 }
        guard hypot(velocity.x, velocity.y) > 250 else { return }
        momentumVelocity = velocity
        let link = CADisplayLink(target: self, selector: #selector(stepMomentum(_:)))
        link.add(to: .main, forMode: .common)
        momentumLink = link
    }

    @objc private func stepMomentum(_ link: CADisplayLink) {
        let dt = link.targetTimestamp - link.timestamp
        sendScroll(CGPoint(x: momentumVelocity.x * dt, y: momentumVelocity.y * dt))
        // UIScrollView's normal deceleration rate, per millisecond.
        let decay = pow(0.998, dt * 1000)
        momentumVelocity.x *= decay
        momentumVelocity.y *= decay
        if hypot(momentumVelocity.x, momentumVelocity.y) < 20 { stopMomentum() }
    }

    private func stopMomentum() {
        momentumLink?.invalidate()
        momentumLink = nil
        momentumVelocity = .zero
    }

    /// The fingers have spread or closed enough that this is a pinch, not a scroll.
    private var isPinching: Bool {
        (zoomPinch.state == .began || zoomPinch.state == .changed) && abs(zoomPinch.scale - 1) > 0.12
    }

    @objc private func handleZoomPinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            if twoFingerIntent == .undecided, isPinching {
                twoFingerIntent = .zoom
                // Start from the current zoom so the view doesn't jump by the threshold.
                zoomBase = scrollView.zoomScale / gesture.scale
            }
            // One finger left means the pinch is ending, and its centroid jumps. Skip that frame.
            guard twoFingerIntent == .zoom, gesture.numberOfTouches != 1 else { return }
            zoom(to: zoomBase * gesture.scale, keeping: gesture.location(in: self))
        default:
            twoFingerGestureEnded()
        }
    }

    private func twoFingerGestureEnded() {
        let active: [UIGestureRecognizer.State] = [.began, .changed]
        if !active.contains(scrollPan.state), !active.contains(zoomPinch.state) {
            twoFingerIntent = .undecided
        }
    }

    /// Zooms the view, keeping the point under the fingers where it is.
    private func zoom(to scale: CGFloat, keeping centroid: CGPoint) {
        let anchor = screenView.convert(centroid, from: self)
        let scale = min(max(scale, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        scrollView.zoomScale = scale
        scrollView.contentOffset = clampedOffset(CGPoint(x: anchor.x * scale - centroid.x,
                                                         y: anchor.y * scale - centroid.y))
    }

    private func keepCursorVisible(animated: Bool) {
        keepVisible(cursorPosition, animated: animated)
    }

    /// Scrolls the viewport so a point on the Mac's screen stays visible. When the keyboard
    /// covers it, the whole screen slides up.
    private func keepVisible(_ screenPoint: CGPoint, animated: Bool) {
        let point = screenView.convert(screenPoint, to: scrollView)
        let margin: CGFloat = 60
        let bottomMargin: CGFloat = 32
        var visible = CGRect(origin: scrollView.contentOffset, size: scrollView.bounds.size)
        visible.size.height -= obscuredBottom
        visible = visible.inset(by: UIEdgeInsets(top: margin, left: margin, bottom: bottomMargin, right: margin))

        var offset = scrollView.contentOffset
        if point.x < visible.minX { offset.x -= visible.minX - point.x }
        if point.x > visible.maxX { offset.x += point.x - visible.maxX }
        if point.y > visible.maxY { offset.y += point.y - visible.maxY }
        else if point.y < visible.minY { offset.y -= visible.minY - point.y }

        offset = clampedOffset(offset)
        if offset != scrollView.contentOffset {
            scrollView.setContentOffset(offset, animated: animated)
        }
    }

    /// Limits a content offset to what the scroll view could reach by scrolling.
    private func clampedOffset(_ offset: CGPoint) -> CGPoint {
        let inset = scrollView.contentInset
        return CGPoint(
            x: min(max(offset.x, -inset.left), max(-inset.left, scrollView.contentSize.width - scrollView.bounds.width + inset.right)),
            y: min(max(offset.y, -inset.top), max(-inset.top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)))
    }

    // MARK: Pointer

    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        // Hide the iPad pointer in mouse mode so only the Mac's pointer shows.
        mode == .mouse ? .hidden() : nil
    }
}

/// In debug builds, records each pointer shape the Mac sends in Documents/cursor-shapes.log,
/// to check how well `looksLikeTextCursor` tells them apart.
private enum CursorLog {
    private static var seen = Set<String>()

    static func record(size: CGSize, visible: CGRect?, hotspot: CGPoint, isText: Bool) {
        #if DEBUG
        let shown = visible.map { " visible \(Int($0.width))×\(Int($0.height)) at \(Int($0.minX)),\(Int($0.minY))" } ?? ""
        let line = "\(Int(size.width))×\(Int(size.height))\(shown) hotspot \(Int(hotspot.x)),\(Int(hotspot.y))"
            + (isText ? " text" : "")
        guard seen.insert(line).inserted,
              let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appending(path: "cursor-shapes.log") else { return }
        let previous = (try? String(contentsOf: url, encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
        guard !previous.contains(line) else { return }
        try? (previous.suffix(49) + [line]).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        #endif
    }
}
