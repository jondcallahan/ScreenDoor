import SwiftUI
import RoyalVNCKit

#if os(iOS)
/// On iPhone Duo propped up like a laptop, the half below the fold becomes a MacBook's deck: a full
/// Mac keyboard, with a trackpad below it.
struct MacBookDeck: View {
    let model: SessionModel
    @State private var foldBottom: CGFloat = 0
    @State private var size: CGSize = .zero

    private static let padding: CGFloat = 12
    private static let spacing: CGFloat = 14
    private static let minimumTrackpadHeight: CGFloat = 90

    var body: some View {
        let width = max(0, size.width - Self.padding * 2)
        let available = max(0, size.height - foldBottom - Self.padding * 2 - Self.spacing)
        let keyboard = MacKeyboard.Metrics(width: width, maxHeight: available - Self.minimumTrackpadHeight)

        VStack(spacing: Self.spacing) {
            MacKeyboard(model: model, metrics: keyboard)
            // The screen view draws the trackpad and handles its touches, so this only marks the spot.
            Color.clear
                .frame(width: width * 0.62)
                .frame(maxHeight: .infinity)
                .allowsHitTesting(false)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.trackpadFrame = $0 }
        }
        .padding(.top, foldBottom + Self.padding)
        .padding([.horizontal, .bottom], Self.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { $0.fold()?.frame.maxY ?? 0 } action: { foldBottom = $0 }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onDisappear { model.trackpadFrame = nil }
    }
}

/// A Mac keyboard laid out like a MacBook's. Modifiers work two ways: hold one while you tap a key,
/// or tap it on its own to apply it to the next key.
struct MacKeyboard: View {
    let model: SessionModel
    let metrics: Metrics
    @State private var keys = KeyboardState()

    struct Metrics {
        /// Every row but the function row is 14.5 keys wide, counting wide keys by their width.
        static let rowUnits: CGFloat = 14.5
        let width: CGFloat
        let unit: CGFloat
        let keyHeight: CGFloat
        let gap: CGFloat

        init(width: CGFloat, maxHeight: CGFloat) {
            self.width = width
            gap = max(4, (width / Self.rowUnits) * 0.1)
            unit = (width - gap * (Self.rowUnits - 1)) / Self.rowUnits
            // Square-ish keys when there's room, shorter ones when there isn't. The function row is
            // three quarters of a key tall, as on a MacBook.
            let fitting = (maxHeight - gap * 5) / 5.75
            keyHeight = max(24, min(unit * 0.95, fitting))
        }

        func width(_ units: CGFloat) -> CGFloat { unit * units + gap * (units - 1) }
    }

    private var shiftOn: Bool { keys.held.contains(.shift) || model.latchedModifiers.contains(.shift) }

    var body: some View {
        VStack(spacing: metrics.gap) {
            functionRow
            HStack(spacing: metrics.gap) {
                ForEach(Array("`1234567890-=").indices, id: \.self) { i in
                    character(Array("`1234567890-=")[i], shifted: Array("~!@#$%^&*()_+")[i])
                }
                special("delete", symbol: "⌫", units: 1.5, label: "Delete", repeats: true) { send(.delete) }
            }
            HStack(spacing: metrics.gap) {
                special("tab", symbol: "⇥", units: 1.5, label: "Tab") { send(.tab) }
                ForEach(Array("qwertyuiop[]"), id: \.self) { character($0, shifted: Self.shifted[$0]) }
                character("\\", shifted: "|")
            }
            HStack(spacing: metrics.gap) {
                capsLock
                ForEach(Array("asdfghjkl;'"), id: \.self) { character($0, shifted: Self.shifted[$0]) }
                special("return", symbol: "⏎", units: 1.75, label: "Return") { send(.return) }
            }
            HStack(spacing: metrics.gap) {
                modifier(.shift, symbol: "⇧", word: "shift", units: 2.25, label: "Shift")
                ForEach(Array("zxcvbnm,./"), id: \.self) { character($0, shifted: Self.shifted[$0]) }
                modifier(.shift, symbol: "⇧", word: "shift", units: 2.25, label: "Right Shift")
            }
            HStack(alignment: .bottom, spacing: metrics.gap) {
                modifier(.control, symbol: "⌃", word: "control", units: 1, label: "Control")
                modifier(.option, symbol: "⌥", word: "option", units: 1, label: "Option")
                modifier(.command, symbol: "⌘", word: "command", units: 1.25, label: "Command")
                KeyCap(label: "Space", action: { send(.space) }) { Color.clear }
                    .frame(width: metrics.width(6), height: metrics.keyHeight)
                modifier(.command, symbol: "⌘", word: "command", units: 1.25, label: "Right Command")
                modifier(.option, symbol: "⌥", word: "option", units: 1, label: "Right Option")
                arrows
            }
        }
        .frame(width: metrics.width)
        .font(.system(size: metrics.keyHeight * 0.4))
    }

    // MARK: Rows

    private var functionRow: some View {
        // esc and F1–F12 share the full width.
        let keyWidth = (metrics.width - metrics.gap * 12) / 13
        let height = metrics.keyHeight * 0.75
        let fKeys: [VNCKeyCode] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]
        return HStack(spacing: metrics.gap) {
            KeyCap(label: "Escape", action: { send(.escape) }) { smallWord("esc") }
                .frame(width: keyWidth, height: height)
            ForEach(fKeys.indices, id: \.self) { i in
                KeyCap(label: "F\(i + 1)", action: { send(fKeys[i]) }) { smallWord("F\(i + 1)") }
                    .frame(width: keyWidth, height: height)
            }
        }
    }

    /// The inverted T: left and right are half height, with up stacked over down between them.
    private var arrows: some View {
        let half = (metrics.keyHeight - metrics.gap / 2) / 2
        return HStack(alignment: .bottom, spacing: metrics.gap) {
            arrow("arrowtriangle.left.fill", label: "Left arrow", .leftArrow).frame(height: half)
            VStack(spacing: metrics.gap / 2) {
                arrow("arrowtriangle.up.fill", label: "Up arrow", .upArrow).frame(height: half)
                arrow("arrowtriangle.down.fill", label: "Down arrow", .downArrow).frame(height: half)
            }
            arrow("arrowtriangle.right.fill", label: "Right arrow", .rightArrow).frame(height: half)
        }
    }

    // MARK: Keys

    private func character(_ base: Character, shifted: Character?) -> some View {
        let isLetter = base.isLetter
        let label = isLetter ? String(shiftOn || keys.capsLock ? base.uppercased() : String(base)) : String(base)
        return KeyCap(label: isLetter ? String(base).uppercased() : Self.spokenNames[base] ?? String(base),
                      action: {
                          let caps: Modifiers = isLetter && keys.capsLock ? .shift : []
                          send(VNCKeyCode(asciiCharacter: base.asciiValue!), extra: caps)
                      }) {
            if let shifted, !isLetter {
                // Symbol keys show both characters, the shifted one on top, like the keycaps.
                VStack(spacing: 0) {
                    Text(String(shifted)).font(.system(size: metrics.keyHeight * 0.3))
                    Text(label).font(.system(size: metrics.keyHeight * 0.3))
                }
            } else {
                Text(label)
            }
        }
        .frame(width: metrics.width(1), height: metrics.keyHeight)
    }

    private func special(_ word: String, symbol: String, units: CGFloat, label: String, repeats: Bool = false,
                         action: @escaping () -> Void) -> some View {
        KeyCap(label: label, repeats: repeats, action: action) {
            labeled(symbol: symbol, word: word)
        }
        .frame(width: metrics.width(units), height: metrics.keyHeight)
    }

    private var capsLock: some View {
        KeyCap(label: "Caps Lock", isOn: keys.capsLock, action: { keys.capsLock.toggle() }) {
            labeled(symbol: "⇪", word: "caps lock")
                .overlay(alignment: .topLeading) {
                    // The light that shows caps lock is on.
                    Circle()
                        .fill(keys.capsLock ? Color.green : Color.white.opacity(0.15))
                        .frame(width: 5, height: 5)
                        .padding(5)
                }
        }
        .accessibilityAddTraits(keys.capsLock ? .isSelected : [])
        .frame(width: metrics.width(1.75), height: metrics.keyHeight)
    }

    private func modifier(_ value: Modifiers, symbol: String, word: String, units: CGFloat, label: String) -> some View {
        let isOn = keys.held.contains(value) || model.latchedModifiers.contains(value)
        return KeyCap(label: label, isOn: isOn,
                      onPress: { keys.hold(value) },
                      action: { if keys.release(value) { model.toggleLatch(value) } }) {
            labeled(symbol: symbol, word: word)
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .frame(width: metrics.width(units), height: metrics.keyHeight)
    }

    private func arrow(_ systemImage: String, label: String, _ code: VNCKeyCode) -> some View {
        KeyCap(label: label, repeats: true, action: { send(code) }) {
            Image(systemName: systemImage).font(.system(size: metrics.keyHeight * 0.2))
        }
        .frame(width: metrics.width(1))
    }

    /// A symbol over its name, as on a MacBook's wide keys. The name drops out when the key is too small.
    private func labeled(symbol: String, word: String) -> some View {
        VStack(spacing: 1) {
            Text(symbol).font(.system(size: metrics.keyHeight * 0.34))
            if metrics.keyHeight >= 34 {
                smallWord(word)
            }
        }
    }

    private func smallWord(_ word: String) -> some View {
        Text(word)
            .font(.system(size: max(8, metrics.keyHeight * 0.22)))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 2)
    }

    private func send(_ code: VNCKeyCode, extra: Modifiers = []) {
        keys.markChorded()
        model.press(code, modifiers: keys.held.union(extra))
    }

    private static let shifted: [Character: Character] = [
        "[": "{", "]": "}", ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?",
    ]

    private static let spokenNames: [Character: String] = [
        "`": "Grave accent", "-": "Hyphen", "=": "Equals", "[": "Left bracket", "]": "Right bracket",
        "\\": "Backslash", ";": "Semicolon", "'": "Apostrophe", ",": "Comma", ".": "Period", "/": "Slash",
    ]
}

/// Mac shortcuts that are awkward to press on the deck's keyboard, for the toolbar beside it.
struct MacShortcuts: View {
    let model: SessionModel

    var body: some View {
        shortcut("Mission Control", systemImage: "rectangle.3.group", .upArrow, [.control])
        shortcut("Spotlight", systemImage: "magnifyingglass", .space, [.command])
        shortcut("Switch Apps", systemImage: "square.on.square", .tab, [.command])
        shortcut("Screenshot", systemImage: "camera.viewfinder", VNCKeyCode(asciiCharacter: 0x35), [.command, .shift])
        shortcut("Lock Screen", systemImage: "lock", VNCKeyCode(asciiCharacter: 0x71), [.control, .command])
    }

    private func shortcut(_ title: String, systemImage: String, _ key: VNCKeyCode, _ modifiers: Modifiers) -> some View {
        Button(title, systemImage: systemImage) {
            Haptic(.light).play()
            model.press(key, modifiers: modifiers)
        }
    }
}

/// What the deck's modifier keys are doing.
@Observable
private final class KeyboardState {
    /// Modifiers with a finger on them right now.
    var held: Modifiers = []
    var capsLock = false
    /// Held modifiers that another key was pressed with. Letting go of one of these doesn't latch it.
    @ObservationIgnored private var chorded: Modifiers = []

    func hold(_ modifier: Modifiers) {
        held.insert(modifier)
        chorded.remove(modifier)
    }

    /// Returns true if the modifier was tapped on its own, so it should apply to the next key.
    func release(_ modifier: Modifiers) -> Bool {
        held.remove(modifier)
        return chorded.remove(modifier) == nil
    }

    func markChorded() { chorded.formUnion(held) }
}

/// One key. It acts when you lift your finger, except keys that repeat, which act straight away
/// and again every so often while held, like delete and the arrows on a Mac.
private struct KeyCap<Content: View>: View {
    let label: String
    var isOn = false
    var repeats = false
    var onPress: (() -> Void)?
    let action: () -> Void
    @ViewBuilder var content: Content

    @State private var isPressed = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        content
            .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.88))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isPressed ? Color.white.opacity(0.32) : isOn ? Color.accentColor : Color.white.opacity(0.15))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.07))
                    }
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        Haptic(.light).play(intensity: 0.7)
                        onPress?()
                        if repeats { startRepeating() }
                    }
                    .onEnded { _ in
                        isPressed = false
                        if repeats { repeatTask?.cancel() } else { action() }
                    }
            )
            .onDisappear { repeatTask?.cancel() }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isKeyboardKey)
            .accessibilityAction { onPress?(); action() }
    }

    private func startRepeating() {
        action()
        repeatTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            while !Task.isCancelled {
                action()
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
    }
}
#endif
