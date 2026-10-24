import Foundation
import Observation
import OSLog
import RoyalVNCKit

enum InputMode {
    /// Pan and zoom only. Nothing is sent to the Mac.
    case view
    /// The screen acts like a trackpad that drives the Mac's pointer.
    case mouse
}

struct Modifiers: OptionSet, Hashable {
    let rawValue: Int
    static let control = Modifiers(rawValue: 1 << 0)
    static let option = Modifiers(rawValue: 1 << 1)
    static let command = Modifiers(rawValue: 1 << 2)
    static let shift = Modifiers(rawValue: 1 << 3)

    var keyCodes: [VNCKeyCode] {
        var codes: [VNCKeyCode] = []
        if contains(.control) { codes.append(.control) }
        if contains(.option) { codes.append(.option) }
        if contains(.command) { codes.append(.command) }
        if contains(.shift) { codes.append(.shift) }
        return codes
    }
}

struct CredentialRequest {
    let needsUsername: Bool
    /// The user's answer. Nil means they cancelled.
    let completion: (VNCCredential?) -> Void
    /// Tells RoyalVNCKit nobody will answer, when the session ends with the prompt still up.
    let abandon: () -> Void
}

/// RoyalVNCKit waits on its credential callback, which must run exactly once.
private final class AnswerOnce {
    private var answered = false
    func claim() -> Bool {
        guard !answered else { return false }
        answered = true
        return true
    }
}

@MainActor
@Observable
final class SessionModel {
    enum Status: Equatable {
        case connecting
        case connected
        /// The message explains a known cause. Nil means the Mac didn't answer.
        case failed(String?)
        case signInRejected
        case closed
    }

    /// Where a connection has got to, shown while `status` is `.connecting`.
    enum Step {
        case finding
        case connecting
        case signingIn
        case loadingScreen
    }

    private static let log = Logger(subsystem: "ScreenDoor", category: "Session")

    let host: Host
    /// Becomes `.connected` once the first picture of the screen arrives.
    private(set) var status: Status = .connecting
    private(set) var step: Step = .connecting
    private(set) var framebufferSize: CGSize = .zero
    /// On Vision Pro, the window is big enough to use without zooming, so it starts in Mouse mode.
    var mode: InputMode = Platform.isVision ? .mouse : .view
    var isKeyboardActive = false
    /// Modifiers the user latched from the key row. They apply to the next key, then clear.
    var latchedModifiers: Modifiers = []
    var credentialRequest: CredentialRequest?
    /// Top edge of the bottom controls in window coordinates, so the screen can slide above them.
    var controlsTop: CGFloat = 0
    /// On iPhone Duo propped up like a laptop, the fold in the screen view's coordinates. The Mac's
    /// screen goes above it, and the half below it is a trackpad.
    var tabletopFold: CGRect?
    /// How far iPhone Duo has folded toward the laptop pose: 0 lying flat, 1 propped up. The screen
    /// and the deck follow it as the hinge moves, and the pose takes over at halfway.
    var tabletopProgress: CGFloat = 0
    /// While folding toward the laptop pose, where the screen area ends, in the screen view's
    /// coordinates. It moves from the bottom of the view up to the fold.
    var screenAreaBottom: CGFloat?
    /// Where the MacBook deck puts its trackpad, in window coordinates.
    var trackpadFrame: CGRect?
    /// The address this session is using, once one answered.
    private(set) var route: Route?

    @ObservationIgnored private var connection: VNCConnection?
    @ObservationIgnored private var timeline = ConnectTimeline()
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var bridge: DelegateBridge?
    @ObservationIgnored private var triedSavedCredentials = false
    /// The Mac turned down the saved password this session, so retries ask for it instead.
    @ObservationIgnored private var savedPasswordRejected = false
    @ObservationIgnored private var userClosed = false
    @ObservationIgnored private var cancelledSignIn = false

    /// Called on the main thread when the framebuffer changes. The view pulls a fresh image.
    @ObservationIgnored var onFramebufferUpdate: ((VNCFramebuffer) -> Void)?
    @ObservationIgnored var onCursorUpdate: ((VNCCursor) -> Void)?
    /// The latest picture and pointer, for a screen view that appears mid-session. On iPhone Duo,
    /// folding and unfolding can rebuild the view while the session carries on.
    @ObservationIgnored private(set) var latestFramebuffer: VNCFramebuffer?
    @ObservationIgnored private(set) var latestCursor: VNCCursor?

    init(host: Host) {
        self.host = host
    }

    // MARK: Connection

    func connect() {
        userClosed = false
        cancelledSignIn = false
        triedSavedCredentials = false
        status = .connecting
        step = host.routes.count > 1 ? .finding : .connecting
        route = nil
        timeline = ConnectTimeline()

        routeTask?.cancel()
        routeTask = Task { [weak self, host] in
            let route = await RouteFinder.choose(host.routes, port: host.port)
            self?.timeline.mark("route")
            guard let self, !Task.isCancelled, !self.userClosed else { return }
            guard let route else {
                self.status = .failed(nil)
                return
            }
            self.route = route
            self.step = .connecting
            self.open(route)
        }
    }

    private func open(_ route: Route) {
        let settings = VNCConnection.Settings(
            isDebugLoggingEnabled: false,
            hostname: route.address,
            port: host.port,
            isShared: true,
            isScalingEnabled: false,
            useDisplayLink: false,
            inputMode: .forwardKeyboardShortcutsEvenIfInUseLocally,
            isClipboardRedirectionEnabled: false,
            colorDepth: .depth24Bit,
            frameEncodings: .default
        )
        let connection = VNCConnection(settings: settings)
        let bridge = DelegateBridge(model: self)
        connection.delegate = bridge
        self.connection = connection
        self.bridge = bridge
        connection.connect()
    }

    func disconnect() {
        userClosed = true
        routeTask?.cancel()
        connection?.disconnect()
        endInput()
        status = .closed
    }

    /// Without a session there's nothing to type into. The key row and the keyboard toggle are
    /// gone too, so the keyboard would cover the error screen with no way to close it. A sign-in
    /// prompt still waiting for an answer is answered for the library, so it doesn't wait forever.
    private func endInput() {
        isKeyboardActive = false
        latchedModifiers = []
        let pending = credentialRequest
        credentialRequest = nil
        pending?.abandon()
    }

    fileprivate func stateChanged(_ state: VNCConnection.ConnectionState) {
        switch state.status {
        case .connecting:
            status = .connecting
        case .connected:
            // Signed in. The screen shows once its first picture arrives.
            timeline.mark("signed in")
            step = .loadingScreen
        case .disconnecting:
            break
        case .disconnected:
            connection?.delegate = nil
            connection = nil
            bridge = nil
            endInput()
            guard !userClosed, !cancelledSignIn else { status = .closed; return }
            if let error = state.error {
                if let vncError = error as? VNCError, vncError.isAuthenticationError {
                    if triedSavedCredentials { savedPasswordRejected = true }
                    status = .signInRejected
                } else if let vncError = error as? VNCError, !vncError.shouldDisplayToUser {
                    status = .closed
                } else {
                    // The library's messages are technical, such as "NWError error 61". Log them and
                    // show the plain guidance instead.
                    Self.log.error("Connection to \(self.host.displayName, privacy: .private) failed: \(error.localizedDescription, privacy: .private)")
                    status = .failed(nil)
                }
            } else {
                status = .failed("The Mac ended the session.")
            }
        @unknown default:
            break
        }
    }

    fileprivate func credentialNeeded(for type: VNCAuthenticationType,
                                      completion: @escaping (VNCCredential?) -> Void) {
        timeline.mark("handshake")
        step = .signingIn
        let saved = Keychain.password(for: host.id)
        if !triedSavedCredentials, !savedPasswordRejected, let saved, !saved.isEmpty,
           !type.requiresUsername || !host.username.isEmpty {
            triedSavedCredentials = true
            completion(credential(for: type, username: host.username, password: saved))
            return
        }
        let once = AnswerOnce()
        credentialRequest = CredentialRequest(needsUsername: type.requiresUsername, completion: { [weak self] credential in
            guard once.claim() else { return }
            if credential == nil { self?.cancelledSignIn = true }
            completion(credential)
            self?.credentialRequest = nil
        }, abandon: {
            // Not a user cancel, so the session keeps its real ending.
            if once.claim() { completion(nil) }
        })
    }

    func credential(for type: VNCAuthenticationType, username: String, password: String) -> VNCCredential {
        Self.credential(needsUsername: type.requiresUsername, username: username, password: password)
    }

    /// Apple's sign-in packs the username and password into 64-byte fields. RoyalVNCKit measures
    /// them in bytes but trims them in characters, which crashes on long passwords with accented
    /// or other multi-byte characters. Trimming to 63 bytes here, on a character boundary, keeps
    /// it on its safe path.
    static func credential(needsUsername: Bool, username: String, password: String) -> VNCCredential {
        needsUsername
            ? VNCUsernamePasswordCredential(username: username.utf8Prefix(63), password: password.utf8Prefix(63))
            : VNCPasswordCredential(password: password)
    }

    fileprivate func framebufferCreated(_ framebuffer: VNCFramebuffer) {
        framebufferSize = framebuffer.cgSize
        latestFramebuffer = framebuffer
        onFramebufferUpdate?(framebuffer)
    }

    fileprivate func cursorUpdated(_ cursor: VNCCursor) {
        latestCursor = cursor
        onCursorUpdate?(cursor)
    }

    fileprivate func framebufferUpdated(_ framebuffer: VNCFramebuffer) {
        latestFramebuffer = framebuffer
        onFramebufferUpdate?(framebuffer)
        guard status == .connecting, step == .loadingScreen else { return }
        status = .connected
        timeline.mark("first picture")
        timeline.save(summary: "\(host.displayName) via \(route?.kind == .remote ? "Tailscale" : "local"), "
                      + "\(Int(framebufferSize.width))×\(Int(framebufferSize.height))")
    }

    // MARK: Mouse

    func mouseMove(to point: CGPoint) {
        guard let (x, y) = clamp(point) else { return }
        connection?.mouseMove(x: x, y: y)
    }

    func mouseDown(_ button: VNCMouseButton, at point: CGPoint) {
        guard let (x, y) = clamp(point) else { return }
        connection?.mouseButtonDown(button, x: x, y: y)
    }

    func mouseUp(_ button: VNCMouseButton, at point: CGPoint) {
        guard let (x, y) = clamp(point) else { return }
        connection?.mouseButtonUp(button, x: x, y: y)
    }

    func click(_ button: VNCMouseButton, at point: CGPoint) {
        mouseDown(button, at: point)
        mouseUp(button, at: point)
    }

    func scroll(_ wheel: VNCMouseWheel, steps: UInt32, at point: CGPoint) {
        guard steps > 0, let (x, y) = clamp(point) else { return }
        connection?.mouseWheel(wheel, x: x, y: y, steps: steps)
    }

    private func clamp(_ point: CGPoint) -> (UInt16, UInt16)? {
        guard framebufferSize != .zero else { return nil }
        let x = min(max(point.x, 0), framebufferSize.width - 1)
        let y = min(max(point.y, 0), framebufferSize.height - 1)
        return (UInt16(x), UInt16(y))
    }

    // MARK: Keyboard

    /// Sends one key press, wrapped in any held or latched modifiers.
    func press(_ key: VNCKeyCode, modifiers: Modifiers = []) {
        let all = modifiers.union(latchedModifiers)
        let modifierKeys = all.keyCodes
        modifierKeys.forEach { connection?.keyDown($0) }
        connection?.keyDown(key)
        connection?.keyUp(key)
        modifierKeys.reversed().forEach { connection?.keyUp($0) }
        latchedModifiers = []
    }

    func typeText(_ text: String) {
        for character in text {
            if character.isNewline {
                press(.return)
            } else {
                for key in VNCKeyCode.withCharacter(character) {
                    press(key)
                }
            }
        }
    }

    func keyDown(_ key: VNCKeyCode) { connection?.keyDown(key) }
    func keyUp(_ key: VNCKeyCode) { connection?.keyUp(key) }

    func toggleLatch(_ modifier: Modifiers) {
        latchedModifiers.formSymmetricDifference(modifier)
    }
}

/// RoyalVNCKit calls its delegate on background queues. This hops each call to the main actor.
private final class DelegateBridge: VNCConnectionDelegate {
    weak var model: SessionModel?

    init(model: SessionModel) {
        self.model = model
    }

    func connection(_ connection: VNCConnection, stateDidChange connectionState: VNCConnection.ConnectionState) {
        Task { @MainActor [weak self] in self?.model?.stateChanged(connectionState) }
    }

    func connection(_ connection: VNCConnection,
                    credentialFor authenticationType: VNCAuthenticationType,
                    completion: @escaping (VNCCredential?) -> Void) {
        Task { @MainActor [weak self] in
            guard let model = self?.model else { completion(nil); return }
            model.credentialNeeded(for: authenticationType, completion: completion)
        }
    }

    func connection(_ connection: VNCConnection, didCreateFramebuffer framebuffer: VNCFramebuffer) {
        Task { @MainActor [weak self] in self?.model?.framebufferCreated(framebuffer) }
    }

    func connection(_ connection: VNCConnection, didResizeFramebuffer framebuffer: VNCFramebuffer) {
        Task { @MainActor [weak self] in self?.model?.framebufferCreated(framebuffer) }
    }

    func connection(_ connection: VNCConnection,
                    didUpdateFramebuffer framebuffer: VNCFramebuffer,
                    x: UInt16, y: UInt16, width: UInt16, height: UInt16) {
        Task { @MainActor [weak self] in self?.model?.framebufferUpdated(framebuffer) }
    }

    func connection(_ connection: VNCConnection, didUpdateCursor cursor: VNCCursor) {
        Task { @MainActor [weak self] in self?.model?.cursorUpdated(cursor) }
    }
}

/// Times each step of connecting. Debug builds keep the last few results in
/// Documents/connect-timing.log, to see where a slow connection spends its time.
struct ConnectTimeline {
    private let start = ContinuousClock.now
    private var last = ContinuousClock.now
    private var steps: [String] = []

    mutating func mark(_ step: String) {
        let now = ContinuousClock.now
        steps.append("\(step) \(Self.ms(now - last))")
        last = now
    }

    func save(summary: String) {
        #if DEBUG
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(summary): "
            + steps.joined(separator: ", ") + ", total \(Self.ms(ContinuousClock.now - start))"
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appending(path: "connect-timing.log") else { return }
        let previous = (try? String(contentsOf: url, encoding: .utf8))?
            .split(separator: "\n").suffix(19).map(String.init) ?? []
        try? (previous + [line]).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        #endif
    }

    /// Release builds don't keep diagnostics. Remove any that a development build left behind.
    static func removeDevelopmentLogs() {
        #if !DEBUG
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        for name in ["connect-timing.log", "cursor-shapes.log"] {
            try? FileManager.default.removeItem(at: documents.appending(path: name))
        }
        #endif
    }

    private static func ms(_ duration: Duration) -> String {
        "\(Int(duration / .milliseconds(1)))ms"
    }
}

extension String {
    /// The longest leading part of the string that fits in `maxBytes` of UTF-8, without splitting a character.
    func utf8Prefix(_ maxBytes: Int) -> String {
        guard utf8.count > maxBytes else { return self }
        var result = ""
        var bytes = 0
        for character in self {
            let size = character.utf8.count
            guard bytes + size <= maxBytes else { break }
            result.append(character)
            bytes += size
        }
        return result
    }
}
