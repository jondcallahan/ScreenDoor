import SwiftUI
import RoyalVNCKit

/// On iPhone Duo's inner display, the Mac sits beside the list of Macs or takes the whole display.
/// The same button switches between the two.
struct ExpandControl {
    var isExpanded: Bool
    var setExpanded: (Bool) -> Void
}

struct SessionView: View {
    @Environment(\.dismiss) private var dismissCover
    /// Closes the session: the Mac's own window on iPad and Vision Pro, or its pane on iPhone.
    /// Without it, the session is a full-screen cover.
    var closeWindow: (() -> Void)?
    /// Present when the Mac can sit beside the list of Macs or take the whole display.
    var expand: ExpandControl?
    @State private var model: SessionModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// Whether this view connects when it appears and disconnects when it goes. On iPhone the list
    /// owns the session instead, so it survives the view being rebuilt as the Duo folds and unfolds.
    private let ownsSession: Bool
    @State private var hint: String?
    @State private var username = ""
    @State private var password = ""
    /// On iPhone Duo, whether a fold runs down the middle, so the controls go to either side of it.
    @State private var splitsControls = false
    /// The mode to go back to when iPhone Duo stops being propped up like a laptop.
    @State private var modeBeforeTabletop: InputMode?
    /// Whether the Mac had the whole display before iPhone Duo was propped up like a laptop.
    @State private var expandedBeforeTabletop: Bool?
    /// On iPhone Duo, the fold when it runs across the screen view, flat or not, and the view's height.
    @State private var acrossFold: Fold?
    @State private var screenHeight: CGFloat = 0
    /// The hinge angle in radians, while the device reports one.
    @State private var hingeAngle: Double?

    /// Folding from flat to here takes the layout all the way to the laptop pose.
    private static let laptopAngle = Double.pi * 0.75

    /// How far the device has folded toward the laptop pose, from 0 to 1.
    private var tabletopProgress: CGFloat {
        guard let acrossFold else { return 0 }
        guard let hingeAngle else { return acrossFold.isActive ? 1 : 0 }
        return CGFloat(min(max((Double.pi - hingeAngle) / (Double.pi - Self.laptopAngle), 0), 1))
    }

    private func updateTabletop() {
        let progress = tabletopProgress
        model.tabletopProgress = progress
        if let fold = acrossFold?.frame, progress > 0 {
            // From the bottom of the view up to the fold, as the hinge closes.
            model.screenAreaBottom = screenHeight + (fold.minY - screenHeight) * progress
            model.tabletopFold = progress >= 0.5 ? fold : nil
        } else {
            model.screenAreaBottom = nil
            model.tabletopFold = nil
        }
    }

    init(host: Host, closeWindow: (() -> Void)? = nil) {
        _model = State(initialValue: SessionModel(host: host))
        self.closeWindow = closeWindow
        ownsSession = true
    }

    /// Shows a session someone else connects and disconnects.
    init(model: SessionModel, close: @escaping () -> Void, expand: ExpandControl?) {
        _model = State(initialValue: model)
        closeWindow = close
        self.expand = expand
        ownsSession = false
    }

    /// On iPhone, the system toolbar takes the place of the floating header.
    private var usesToolbar: Bool { !ownsSession }

    /// Beside the list of Macs, the session's dark look stays in its own pane.
    private var fillsWindow: Bool { expand?.isExpanded ?? true }

    private func dismiss() {
        if let closeWindow { closeWindow() } else { dismissCover() }
    }

    var body: some View {
        #if os(iOS)
        // On iPhone the session sits in the list's navigation and uses the system toolbar, which
        // moves to the right place as the phone opens, closes and rotates. On iPhone Duo, iOS stands
        // it up in the strip beside the screen.
        session
            .toolbar { if usesToolbar { sessionToolbar } }
            .toolbar(usesToolbar ? .visible : .hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationTitle(model.host.displayName)
            .navigationSubtitle(subtitle ?? "")
            .navigationBarTitleDisplayMode(.inline)
            // The X closes the session. A swipe from the edge is the trackpad's, not a way back.
            .navigationBarBackButtonHidden()
        #else
        session
        #endif
    }

    private var session: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RemoteScreen(model: model)
                // Measured inside `ignoresSafeArea`, so the fold is in the same coordinates as the screen view.
                .onGeometryChange(for: Fold?.self) { proxy in
                    proxy.fold(includeFlat: true).flatMap { $0.isVertical ? nil : $0 }
                } action: { acrossFold = $0; updateTabletop() }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { screenHeight = $0; updateTabletop() }
                .modifier(HingeAngleReader(angle: $hingeAngle))
                .onChange(of: hingeAngle) { updateTabletop() }
                // With the toolbar, the top or a side holds the bar, and a side can hold the list of
                // Macs floating over this pane. The background goes under them, but the screen stays
                // clear. It still goes under the bottom controls, to stay as big as it can.
                .ignoresSafeArea(edges: usesToolbar ? .bottom : .all)
                .opacity(model.status == .connected ? 1 : 0)

            statusOverlay
                .avoidsFold()

            #if os(iOS)
            if model.status == .connected, model.tabletopProgress > 0 {
                // The deck rises into place as the hinge closes.
                let progress = model.tabletopProgress
                MacBookDeck(model: model)
                    .opacity(min(max((progress - 0.25) / 0.5, 0), 1))
                    .offset(y: (1 - progress) * 160)
                    .animation(.smooth(duration: 0.2), value: progress)
                    .allowsHitTesting(progress >= 0.5)
            }
            #endif
        }
        .animation(.smooth, value: model.tabletopFold != nil)
        #if os(visionOS)
        // The window's own controls close it, and the session's controls sit below it.
        .ornament(visibility: model.status == .connected ? .visible : .hidden,
                  attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
            controls.padding(.top, 12)
        }
        .onChange(of: model.status) { _, status in
            if status == .connected { showHint(Self.mouseHint) }
        }
        #else
        .safeAreaInset(edge: .top) { if !usesToolbar { header } }
        .safeAreaInset(edge: .bottom) {
            // They fade as the deck takes their place.
            controls
                .opacity(min(max(1 - model.tabletopProgress / 0.5, 0), 1))
                .animation(.smooth(duration: 0.2), value: model.tabletopProgress)
        }
        .onChange(of: model.tabletopFold != nil) { _, isTabletop in
            if isTabletop {
                // The bottom half becomes a MacBook's keyboard and trackpad, which drives the pointer.
                modeBeforeTabletop = model.mode
                model.mode = .mouse
                model.isKeyboardActive = false
            } else if let mode = modeBeforeTabletop {
                modeBeforeTabletop = nil
                model.mode = mode
            }
        }
        .onChange(of: model.tabletopProgress > 0) { _, isFolding in
            // The deck needs the whole display. Taking it as soon as folding starts keeps the change
            // small, and skipping the animation leaves the motion to the hinge.
            var instant = Transaction()
            instant.disablesAnimations = true
            if isFolding, let expand {
                expandedBeforeTabletop = expand.isExpanded
                withTransaction(instant) { expand.setExpanded(true) }
            } else if !isFolding, let wasExpanded = expandedBeforeTabletop {
                expandedBeforeTabletop = nil
                withTransaction(instant) { expand?.setExpanded(wasExpanded) }
            }
        }
        #endif
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(fillsWindow ? .dark : nil)
        .sensoryFeedback(.selection, trigger: model.mode)
        .sensoryFeedback(.impact(weight: .light), trigger: model.isKeyboardActive)
        .sensoryFeedback(.selection, trigger: model.latchedModifiers)
        .sensoryFeedback(trigger: model.status) { _, status in
            switch status {
            case .connected: .success
            case .failed, .signInRejected: .error
            default: nil
            }
        }
        .persistentSystemOverlays(fillsWindow ? .hidden : .automatic)
        .task { if ownsSession { model.connect() } }
        .onDisappear { if ownsSession { model.disconnect() } }
        .onChange(of: model.mode) { _, mode in
            // Propped up like a laptop, the deck explains itself.
            guard model.tabletopFold == nil else { return }
            showHint(mode == .mouse ? Self.mouseHint : Self.lookHint)
        }
        .alert("Sign in to \(model.host.displayName)", isPresented: credentialAlertBinding) {
            if model.credentialRequest?.needsUsername == true {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            SecureField("Password", text: $password)
                .textContentType(.password)
            Button("Cancel", role: .cancel) {
                model.credentialRequest?.completion(nil)
            }
            Button("Sign in") {
                guard let request = model.credentialRequest else { return }
                let credential = SessionModel.credential(needsUsername: request.needsUsername,
                                                         username: username, password: password)
                password = ""
                request.completion(credential)
            }
        } message: {
            Text(model.credentialRequest?.needsUsername == true
                 ? "Enter the username and password you use to log in to this Mac."
                 : "Enter the Screen Sharing password for this Mac.")
        }
        .onChange(of: model.credentialRequest == nil) { _, isNil in
            if !isNil { username = model.host.username }
        }
    }

    #if os(visionOS)
    private static let mouseHint = "Look at something and tap to click. Pinch and drag to scroll. Pinch and hold, then drag to select, or let go to right-click."
    private static let lookHint = "Pinch and drag to look around. Pinch with both hands to zoom."
    #else
    private static let mouseHint = "Drag to move the pointer. Tap to click. Tap with two fingers to right-click. Touch and hold, then drag to select."
    private static let lookHint = "Drag to look around. Pinch or double-tap to zoom."
    #endif
    private var credentialAlertBinding: Binding<Bool> {
        Binding(
            get: { model.credentialRequest != nil },
            set: { if !$0, let request = model.credentialRequest { request.completion(nil) } }
        )
    }

    // MARK: Toolbar

    #if os(iOS)
    @ToolbarContentBuilder
    private var sessionToolbar: some ToolbarContent {
        // Close sits first, at the top of a vertical bar.
        ToolbarItem(placement: .cancellationAction) {
            Button("Disconnect", systemImage: "xmark") {
                model.disconnect()
                dismiss()
            }
        }
        if let expand {
            // One button goes full screen, and the same button comes back beside the list.
            ToolbarItem(placement: .primaryAction) {
                Button(expand.isExpanded ? "Show Macs" : "Full Screen",
                       systemImage: expand.isExpanded
                           ? "arrow.down.right.and.arrow.up.left"
                           : "arrow.up.left.and.arrow.down.right") {
                    withAnimation(.smooth) { expand.setExpanded(!expand.isExpanded) }
                }
                .contentTransition(.symbolEffect(.replace))
            }
        }
        // With a keyboard up, its key row has the modifiers, and the room goes to typing.
        if model.status == .connected, !model.isKeyboardActive {
            if horizontalSizeClass == .compact && verticalSizeClass == .regular {
                // Upright on a narrow screen, one menu leaves room for the Mac's name.
                ToolbarItem(placement: .primaryAction) {
                    Menu("Mac Shortcuts", systemImage: "command") {
                        MacShortcuts(model: model)
                    }
                }
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    MacShortcuts(model: model)
                }
            }
        }
    }
    #endif

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.host.displayName)
                    .font(.headline)
                    .lineLimit(1)
                // Until the screen shows, the centre of the screen carries the status.
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .glass(in: .capsule)

            Spacer(minLength: 0)

            if let expand {
                // One button goes full screen, and the same button comes back beside the list.
                Button {
                    withAnimation(.smooth) { expand.setExpanded(!expand.isExpanded) }
                } label: {
                    Label(expand.isExpanded ? "Show Macs" : "Full Screen",
                          systemImage: expand.isExpanded
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .contentShape(.circle)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .glass(in: .circle, interactive: true)
            }

            Button {
                model.disconnect()
                dismiss()
            } label: {
                Label("Disconnect", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glass(in: .circle, interactive: true)
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .animation(.default, value: subtitle)
    }

    private var subtitle: String? {
        guard model.status == .connected else { return nil }
        return (model.mode == .mouse || model.isKeyboardActive ? "You're in control" : "Viewing")
            + (model.route?.kind == .remote ? " · via Tailscale" : "")
    }

    /// The Mac's name is in the header, so this is just the step.
    private var stepDescription: String {
        switch model.step {
        case .finding: "Looking on your network and Tailscale…"
        case .connecting: model.route?.kind == .remote ? "Connecting through Tailscale…" : "Connecting…"
        case .signingIn: "Signing in…"
        case .loadingScreen: "Loading screen…"
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        // Propped up like a laptop, the MacBook deck takes the place of these.
        if model.status == .connected, model.tabletopFold == nil {
            VStack(spacing: 12) {
                if let hint {
                    Text(hint)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        #if os(visionOS)
                        // The ornament doesn't limit its width, so keep the hint to a few short lines.
                        .frame(width: 460)
                        #endif
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glass(in: .rect(cornerRadius: 18))
                        // With the controls split, the hint sits above the mode switch, clear of the fold.
                        .frame(maxWidth: splitsControls ? 360 : nil, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: splitsControls ? .leading : .center)
                        .padding(.horizontal, splitsControls ? 20 : 32)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .onTapGesture { withAnimation { self.hint = nil } }
                }

                if model.isKeyboardActive {
                    KeyRow(model: model, splits: splitsControls)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                GlassGroup(spacing: 12) {
                    HStack(spacing: 12) {
                        #if os(visionOS)
                        // Vision Pro windows have no title, so the Mac's name goes here.
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.host.displayName)
                                .font(.headline)
                            if let subtitle {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 20)
                        .frame(height: 56)
                        .glass(in: .capsule)
                        #endif
                        HStack(spacing: 0) {
                            modeButton("Look around", systemImage: "hand.draw", mode: .view)
                            modeButton("Mouse", systemImage: "cursorarrow", mode: .mouse)
                        }
                        .padding(4)
                        .glass(in: .capsule)

                        // Held open with both hands, each thumb gets one, and neither sits on the fold.
                        if splitsControls { Spacer(minLength: 0) }

                        toggleButton(model.isKeyboardActive ? "Hide keyboard" : "Show keyboard",
                                     systemImage: "keyboard",
                                     isOn: model.isKeyboardActive) {
                            model.isKeyboardActive.toggle()
                        }
                    }
                    .padding(.horizontal, splitsControls ? 20 : 0)
                }
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: Bool.self) { proxy in
                // Checked with the device flat too, so the controls stay put as it folds.
                guard let fold = proxy.fold(includeFlat: true), fold.isVertical else { return false }
                return abs(fold.frame.midX - proxy.size.width / 2) < proxy.size.width / 4
            } action: { splitsControls = $0 }
            #if !os(visionOS)
            // On Vision Pro the controls and keyboard float outside the window, so nothing covers the screen.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { model.controlsTop = $0 }
            #endif
            .animation(.smooth, value: model.isKeyboardActive)
            .animation(.smooth, value: hint)
            .animation(.smooth, value: splitsControls)
        }
    }

    private func modeButton(_ title: String, systemImage: String, mode: InputMode) -> some View {
        let isSelected = model.mode == mode
        return Button {
            model.mode = mode
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 64, height: 48)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background {
                    if isSelected {
                        Capsule().fill(Color.accentColor)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.snappy, value: model.mode)
    }

    private func toggleButton(_ title: String, systemImage: String, isOn: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 64, height: 56)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glass(in: .capsule, tint: isOn ? .accentColor : nil, interactive: true)
        .accessibilityLabel(title)
    }

    // MARK: Status

    @ViewBuilder
    private var statusOverlay: some View {
        switch model.status {
        case .connecting:
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text(stepDescription)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.default, value: model.step)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't connect to \(model.host.displayName)", systemImage: "exclamationmark.triangle")
            } description: {
                Text([message, model.host.remoteAddress.isEmpty
                      ? "Make sure the Mac is awake, Screen Sharing is on, and you're on the same network."
                      : "Make sure the Mac is awake and Screen Sharing is on. If you're away from home, turn on Tailscale."]
                    .compactMap { $0 }.joined(separator: "\n\n"))
            } actions: {
                Button("Try again") { model.connect() }
                    .glassButton(prominent: true)
                Button("Close") { dismiss() }
                    .glassButton()
            }
        case .signInRejected:
            ContentUnavailableView {
                Label("Sign-in didn't work", systemImage: "person.badge.key")
            } description: {
                Text("\(model.host.displayName) didn't accept that username and password. Use the ones you log in to the Mac with.")
            } actions: {
                Button("Try again") { model.connect() }
                    .glassButton(prominent: true)
                Button("Close") { dismiss() }
                    .glassButton()
            }
        case .closed:
            ContentUnavailableView {
                Label("Disconnected", systemImage: "desktopcomputer")
            } actions: {
                Button("Reconnect") { model.connect() }
                    .glassButton(prominent: true)
            }
        case .connected:
            EmptyView()
        }
    }

    private func showHint(_ text: String) {
        withAnimation { hint = text }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if hint == text { withAnimation { hint = nil } }
        }
    }
}

/// Mac keys the iOS keyboard doesn't have. Modifiers latch and apply to the next key you type.
private struct KeyRow: View {
    let model: SessionModel
    /// On iPhone Duo's inner display, the arrows go to the far side of the fold, as on a Mac keyboard.
    var splits = false

    var body: some View {
        #if os(visionOS)
        // The ornament is as wide as its content, so there's nothing to scroll.
        keys
        #else
        if splits {
            keys
        } else {
            ScrollView(.horizontal, showsIndicators: false) { keys }
                .scrollClipDisabled()
        }
        #endif
    }

    private var keys: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                key("esc", label: "Escape") { model.press(.escape) }
                key("tab", label: "Tab") { model.press(.tab) }
                modifier("⌃", label: "Control", .control)
                modifier("⌥", label: "Option", .option)
                modifier("⌘", label: "Command", .command)
                modifier("⇧", label: "Shift", .shift)
                if splits { Spacer(minLength: 24) }
                key(systemImage: "arrow.left", label: "Left arrow") { model.press(.leftArrow) }
                key(systemImage: "arrow.up", label: "Up arrow") { model.press(.upArrow) }
                key(systemImage: "arrow.down", label: "Down arrow") { model.press(.downArrow) }
                key(systemImage: "arrow.right", label: "Right arrow") { model.press(.rightArrow) }
            }
            .padding(.horizontal, splits ? 20 : 16)
        }
    }

    private func key(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic(.light).play()
            action()
        } label: {
            Text(title).font(.callout.weight(.medium)).frame(minWidth: 44, minHeight: 40)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .glass(in: .rect(cornerRadius: 12), interactive: true)
        .accessibilityLabel(label)
    }

    private func key(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic(.light).play()
            action()
        } label: {
            Image(systemName: systemImage).font(.callout.weight(.semibold)).frame(width: 44, height: 40)
        }
        .buttonStyle(.plain)
        .glass(in: .rect(cornerRadius: 12), interactive: true)
        .accessibilityLabel(label)
    }

    private func modifier(_ symbol: String, label: String, _ value: Modifiers) -> some View {
        let isOn = model.latchedModifiers.contains(value)
        return Button {
            model.toggleLatch(value)
        } label: {
            Text(symbol).font(.title3).frame(width: 44, height: 40)
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .glass(in: .rect(cornerRadius: 12), tint: isOn ? .accentColor : nil, interactive: true)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
