import SwiftUI

struct HostListView: View {
    @Environment(HostStore.self) private var store
    @State private var browser = MacBrowser()
    @State private var editingHost: Host?
    @State private var activeHost: Host?
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(\.openWindow) private var openWindow
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // On iPhone, the list and the Mac are one path, from general to specific. Closed, iPhone Duo
    // shows the last step. Open, it shows both, one on each side of the fold.
    /// The Mac being shown. The list owns it, so it stays connected as the Duo folds and unfolds.
    @State private var session: SessionModel?
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    /// Where the fold runs down iPhone Duo's inner display, so the list fills the half before it.
    @State private var foldX: CGFloat?
    /// Set on iPhone Duo, which reports a hinge angle. Other iPhones don't have one.
    @State private var hingeAngle: Double?

    /// iPad and Vision Pro give each Mac a window of its own. iPhone Duo can only open new windows
    /// on its inner display, and folding shouldn't strand a session, so iPhone keeps one path.
    private var usesWindows: Bool { UIDevice.current.userInterfaceIdiom != .phone }

    /// Macs found on the network that aren't saved yet.
    private var newMacs: [DiscoveredMac] {
        browser.macs.filter { mac in !store.hosts.contains { browser.mac(matching: $0) == mac } }
    }

    var body: some View {
        if usesWindows {
            NavigationStack { macs }
        } else {
            NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
                macs
                    .navigationSplitViewColumnWidth(min: 300, ideal: foldX ?? 340, max: foldX ?? 400)
            } detail: {
                detail
            }
            .navigationSplitViewStyle(.balanced)
            .onGeometryChange(for: CGFloat?.self) { proxy in
                proxy.fold(includeFlat: true).flatMap { $0.isVertical ? $0.frame.midX : nil }
            } action: { foldX = $0 }
            .modifier(HingeAngleReader(angle: $hingeAngle))
            .onChange(of: store.hosts.map(\.id)) { _, ids in
                if let session, !ids.contains(session.host.id) { closeSession() }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let session {
            SessionView(model: session, close: closeSession, expand: horizontalSizeClass == .regular
                ? ExpandControl(isExpanded: columns == .detailOnly) { expanded in
                    columns = expanded ? .detailOnly : .all
                }
                : nil)
                .id(session.host.id)
        } else {
            ContentUnavailableView("Choose a Mac", systemImage: "desktopcomputer",
                                   description: Text("Its screen shows up here."))
        }
    }

    private var macs: some View {
        Group {
            if store.hosts.isEmpty && newMacs.isEmpty {
                ContentUnavailableView {
                    Label("No Macs yet", systemImage: "desktopcomputer")
                } description: {
                    Text("Add a Mac to see and control its screen. On the Mac, turn on Screen Sharing in System Settings > General > Sharing. Macs on this network show up here by themselves.")
                } actions: {
                    Button("Add Mac") { editingHost = Host(name: "", address: "") }
                        .glassButton(prominent: true)
                }
            } else {
                List {
                    if !store.hosts.isEmpty {
                        Section {
                            ForEach(store.hosts) { host in
                                Button {
                                    open(host)
                                } label: {
                                    HostRow(host: host, isNearby: browser.mac(matching: host) != nil)
                                }
                                .tint(.primary)
                                // Beside the Mac, the list shows which one it is.
                                .listRowBackground(session?.host.id == host.id && horizontalSizeClass == .regular
                                                   ? Color.accentColor.opacity(0.15) : nil)
                                .swipeActions(edge: .leading) {
                                    Button("Edit", systemImage: "pencil") { editingHost = host }
                                        .tint(.blue)
                                }
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editingHost = host }
                                }
                            }
                            .onDelete(perform: store.delete)
                        }
                    }
                    if !newMacs.isEmpty {
                        Section {
                            ForEach(newMacs) { mac in
                                Button {
                                    editingHost = Host(name: mac.name, address: mac.hostName, port: mac.port, model: mac.model)
                                } label: {
                                    DiscoveredRow(mac: mac)
                                }
                                .tint(.primary)
                            }
                        } header: {
                            Text("On This Network")
                        } footer: {
                            Text("Tap a Mac to add it.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Macs")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu("About Screen Door", systemImage: "info.circle") {
                    Link(destination: URL(string: "https://github.com/jondcallahan/ScreenDoor/blob/main/PRIVACY.md")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: URL(string: "https://github.com/jondcallahan/ScreenDoor")!) {
                        Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add Mac", systemImage: "plus") {
                    editingHost = Host(name: "", address: "")
                }
                .keyboardShortcut("n")
            }
        }
        .sheet(item: $editingHost) { host in
            HostEditorView(host: host, isNew: !store.hosts.contains { $0.id == host.id })
        }
        .fullScreenCover(item: $activeHost) { host in
            SessionView(host: host)
        }
        .onAppear { browser.start() }
        .onChange(of: browser.macs) {
            for host in store.hosts {
                if let model = browser.mac(matching: host)?.model { store.setModel(model, for: host.id) }
            }
        }
        .onDisappear { browser.stop() }
    }

    private func open(_ host: Host) {
        if usesWindows {
            if supportsMultipleWindows { openWindow(value: host.id) } else { activeHost = host }
            return
        }
        if session?.host.id != host.id {
            session?.disconnect()
            let model = SessionModel(host: host)
            model.connect()
            session = model
            // Opened on iPhone Duo, the Mac goes beside the list. Other iPhones are only wide in
            // landscape, which people turn to for a bigger Mac, so it starts out full screen there.
            columns = hingeAngle == nil ? .detailOnly : .all
        }
        compactColumn = .detail
    }

    private func closeSession() {
        session?.disconnect()
        session = nil
        columns = .all
        compactColumn = .sidebar
    }
}

private struct HostRow: View {
    let host: Host
    let isNearby: Bool

    private var detail: String {
        [host.name.isEmpty ? "" : host.address, host.remoteAddress.isEmpty ? "" : "Tailscale"]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: MacModel.symbolName(for: host.model))
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
                .overlay(alignment: .bottomTrailing) {
                    if isNearby {
                        Circle()
                            .fill(.green)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.background, lineWidth: 2))
                            .offset(x: 2, y: 2)
                            .accessibilityLabel("On this network")
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName)
                    .font(.body.weight(.medium))
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

private struct DiscoveredRow: View {
    let mac: DiscoveredMac

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: MacModel.symbolName(for: mac.model))
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(mac.name)
                    .font(.body.weight(.medium))
                Text(mac.hostName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}
