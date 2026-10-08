import AppKit
import VPNCore

@main
struct VPNUtilityMain {
    @MainActor
    static func main() async {
        if CommandLine.arguments.contains("--check-ui") {
            NSApplication.shared.setActivationPolicy(.accessory)
            let controller = MenuController()
            let problems = controller.validateSyntheticMenus()
            for problem in problems { fputs("Menu check failed: \(problem)\n", stderr) }
            if !problems.isEmpty { exit(1) }
            print("Synthetic active menus and indicator: OK")
            return
        }
        if CommandLine.arguments.contains("--diagnose") {
            let groups = await VPNDiscovery().discover(ApplicationLocator().discover())
            NSApplication.shared.setActivationPolicy(.accessory)
            let checkController = MenuController()
            let menuProblems = withExtendedLifetime(checkController) { checkController.validateMenu(groups) }
            if !menuProblems.isEmpty {
                for problem in menuProblems { fputs("Menu check failed: \(problem)\n", stderr) }
                exit(1)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(groups), let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = MenuController()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class MenuController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let discovery = VPNDiscovery()
    private let commands = VPNCommands()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var groups: [VPNGroup] = []
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var busy = Set<String>()
    private var errors: [String: String] = [:]
    private var hasLoaded = false
    private var discoveryPending = false
    private let connectionBadge = ConnectionBadge(frame: NSRect(x: 0, y: 0, width: 6, height: 6))

    // Builds detached menus only: diagnostic checks never click controls or start VPNs.
    func validateSyntheticMenus() -> [String] {
        let groups = [
            VPNGroup(provider: .tailscale, applicationURL: nil, status: .connected,
                     entries: [VPNEntry(id: "tailscale", name: "Tailscale", status: .connected, actions: [.disconnect, .openClient])]),
            VPNGroup(provider: .cisco, applicationURL: nil, status: .connected,
                     entries: [VPNEntry(id: "one", name: "Office", status: .connected, actions: [.openClient]),
                               VPNEntry(id: "two", name: "Home", status: .connected, actions: [.openClient])]),
            VPNGroup(provider: .openVPN, applicationURL: nil, status: .managedInClient, entries: []),
            VPNGroup(provider: .system, applicationURL: nil, status: .unavailable,
                     entries: [Parsers.systemEntry(id: "native", name: "Office", status: .connected),
                               Parsers.systemEntry(id: "other", name: "Home", status: .connected)])
        ]
        return [[], groups, [VPNGroup(provider: .tailscale, applicationURL: nil, status: .unavailable, entries: [])]]
            .flatMap { validateMenu($0) }
    }

    func validateMenu(_ snapshots: [VPNGroup]) -> [String] {
        groups = snapshots
        hasLoaded = true
        render()
        var problems: [String] = []
        if connectionBadge.isHidden != ActiveConnection.observed(in: snapshots).isEmpty {
            problems.append("Incorrect connected indicator")
        }
        for active in ActiveConnection.observed(in: snapshots) {
            let expectedActions: [VPNAction] = active.canDisconnect
                ? [.disconnect, active.openAction] : [active.openAction]
            for action in expectedActions {
                let matches = menu.items.filter {
                    guard let selection = $0.representedObject as? Selection else { return false }
                    return selection.group.provider == active.group.provider
                        && selection.entry?.id == active.entry?.id && selection.action == action
                }
                if matches.count != 1 { problems.append("Missing or duplicated active VPN shortcut") }
            }
        }
        for group in snapshots {
            guard let submenu = menu.items.first(where: { $0.title == group.provider.title })?.submenu else {
                problems.append("Missing \(group.provider.title) menu")
                continue
            }
            if group.provider == .system {
                for entry in group.entries {
                    let title = "\(entry.name) — \(entry.status.title)"
                    let actions = submenu.items.first(where: { $0.title == title })?.submenu
                    if actions?.items.filter({ $0.action != nil }).count != entry.actions.count {
                        problems.append("Missing system VPN actions")
                    }
                }
            } else {
                if !submenu.items.contains(where: { $0.title == "Open Client…" && $0.action != nil }) {
                    problems.append("Missing client recovery action")
                }
                if group.provider == .cisco || group.provider == .openVPN {
                    for entry in group.entries {
                        let actions = submenu.items.first(where: { $0.title == entry.name })?.submenu
                        if actions?.items.filter({ $0.action != nil }).count != 1 {
                            problems.append("Missing profile handoff")
                        }
                    }
                }
            }
        }
        for title in ["Refresh", "Quit VPN Utility"] {
            if !menu.items.contains(where: { $0.title == title && $0.action != nil }) {
                problems.append("Missing \(title) action")
            }
        }
        return problems
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "network", accessibilityDescription: "VPN Utility")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "VPN Utility"
        if let button = statusItem.button {
            connectionBadge.frame.origin = NSPoint(x: button.bounds.maxX - 8, y: button.bounds.minY + 1)
            connectionBadge.autoresizingMask = [.minXMargin, .maxYMargin]
            connectionBadge.isHidden = true
            button.addSubview(connectionBadge)
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        render()
        refresh(discoverProfiles: true)
        scheduleRefresh(every: 15)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh(discoverProfiles: true)
        scheduleRefresh(every: 5)
    }

    private func scheduleRefresh(every interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        scheduleRefresh(every: 15)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        refreshTask?.cancel()
    }

    private func refresh(discoverProfiles: Bool = false) {
        if discoverProfiles { discoveryPending = true }
        guard refreshTask == nil, busy.isEmpty else { return }
        let fullDiscovery = discoveryPending || !hasLoaded
        discoveryPending = false
        refreshTask = Task {
            if fullDiscovery { groups = await discovery.discover(ApplicationLocator().discover()) }
            else { groups = await discovery.refreshStatuses(groups) }
            hasLoaded = true
            refreshTask = nil
            render()
            if discoveryPending { refresh() }
        }
    }

    private func label(_ text: String, in target: NSMenu) {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        target.addItem(item)
    }

    private func addAction(_ title: String, group: VPNGroup, entry: VPNEntry? = nil,
                           action: VPNAction, to target: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(selected(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = Selection(group: group, entry: entry, action: action)
        item.isEnabled = !busy.contains(key(group, entry))
        target.addItem(item)
    }

    private func key(_ group: VPNGroup, _ entry: VPNEntry?) -> String {
        group.provider == .system ? entry?.id ?? "system" : group.provider.rawValue
    }

    private func render() {
        menu.removeAllItems()
        let activeConnections = ActiveConnection.observed(in: groups)
        connectionBadge.isHidden = activeConnections.isEmpty
        if let button = statusItem?.button {
            let summary = activeConnections.isEmpty ? "No observed active VPNs"
                : "Connected: " + activeConnections.map(\.name).joined(separator: ", ")
            button.toolTip = "VPN Utility — \(summary)"
            button.setAccessibilityLabel("VPN Utility, \(summary)")
        }
        if !hasLoaded { label("Finding your VPNs…", in: menu) }
        else if groups.isEmpty { label("No supported VPNs found", in: menu) }
        if !activeConnections.isEmpty {
            label("Active VPNs", in: menu)
            for active in activeConnections {
                if active.canDisconnect {
                    addAction("Disconnect \(active.name)", group: active.group, entry: active.entry,
                              action: .disconnect, to: menu)
                }
                addAction(active.group.provider == .system ? "Open VPN Settings for \(active.name)…" : "Open \(active.name)…",
                          group: active.group, entry: active.entry, action: active.openAction, to: menu)
            }
            menu.addItem(.separator())
        }
        for group in groups {
            let title = NSMenuItem(title: group.provider.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            title.submenu = submenu
            menu.addItem(title)
            if group.provider != .system {
                let statusTitle: String
                if group.provider == .tailscale && group.status == .connected { statusTitle = "Connected to tailnet" }
                else if group.provider == .tailscale && group.status == .disconnected { statusTitle = "Disconnected from tailnet" }
                else { statusTitle = group.status.title }
                label(statusTitle, in: submenu)
            }
            if let issue = group.issue { label(issue, in: submenu) }
            if let error = errors[group.provider.rawValue] { label(error, in: submenu) }
            switch group.provider {
            case .tailscale:
                label("Status reported by Tailscale", in: submenu)
                if let entry = group.entries.first {
                    for action in entry.actions where action != .openClient {
                        addAction(action == .connect ? (entry.status == .needsLogin ? "Log In in Tailscale…" : "Connect") : "Disconnect",
                                  group: group, entry: entry, action: action, to: submenu)
                    }
                }
            case .cisco, .openVPN:
                if group.entries.isEmpty && group.issue == nil { label("No profiles found", in: submenu) }
                for entry in group.entries {
                    let profile = NSMenuItem(title: entry.name, action: nil, keyEquivalent: "")
                    let actions = NSMenu()
                    actions.autoenablesItems = false
                    profile.submenu = actions
                    let client = group.provider == .cisco ? "Cisco" : "OpenVPN Connect"
                    label("Select this profile in \(client)", in: actions)
                    addAction("Open in \(client)…", group: group, entry: entry, action: .openClient, to: actions)
                    submenu.addItem(profile)
                }
                if group.provider == .cisco && group.status == .connected {
                    addAction("Disconnect Active VPN", group: group, action: .disconnect, to: submenu)
                }
            case .system:
                for entry in group.entries {
                    let profile = NSMenuItem(title: "\(entry.name) — \(entry.status.title)", action: nil, keyEquivalent: "")
                    let actions = NSMenu()
                    actions.autoenablesItems = false
                    profile.submenu = actions
                    if let error = errors[entry.id] { label(error, in: actions) }
                    if busy.contains(entry.id) { label("Working…", in: actions) }
                    for action in entry.actions {
                        let text = action == .openSettings
                            ? (entry.status == .disconnected ? "Connect in VPN Settings…" : "Open VPN Settings…")
                            : "Disconnect"
                        addAction(text, group: group, entry: entry, action: action, to: actions)
                    }
                    submenu.addItem(profile)
                }
            }
            if busy.contains(group.provider.rawValue) { label("Working…", in: submenu) }
            if group.provider == .system && group.entries.isEmpty {
                addAction("Open VPN Settings…", group: group, action: .openSettings, to: submenu)
            } else if group.provider != .system {
                submenu.addItem(.separator())
                addAction("Open Client…", group: group, action: .openClient, to: submenu)
            }
        }
        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshSelected), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = refreshTask == nil
        menu.addItem(refresh)
        let quit = NSMenuItem(title: "Quit VPN Utility", action: #selector(quitSelected), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.update()
    }

    @objc private func refreshSelected() { refresh(discoverProfiles: true) }
    @objc private func quitSelected() { NSApplication.shared.terminate(nil) }

    @objc private func selected(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? Selection else { return }
        let group = selection.group
        let entry = selection.entry
        let action = selection.action
        let actionKey = key(group, entry)
        guard !busy.contains(actionKey) else { return }
        errors.removeValue(forKey: actionKey)
        if action == .openClient || (group.provider == .tailscale && entry?.status == .needsLogin) {
            openClient(group)
            return
        }
        if action == .openSettings { openSettings(); return }
        busy.insert(actionKey)
        render()
        Task {
            var failed = false
            do {
                try await commands.perform(action, provider: group.provider,
                                           application: group.applicationURL, profileID: entry?.profileID)
                // Wait for an existing read to finish so pre-action status cannot win the race.
                if let task = refreshTask { await task.value }
                discoveryPending = false
                groups = await discovery.discover(ApplicationLocator().discover())
                let latestGroup = groups.first { $0.provider == group.provider }
                let latestStatus = group.provider == .system
                    ? latestGroup?.entries.first { $0.id == entry?.id }?.status
                    : latestGroup?.status
                let expected: VPNStatus = action == .connect ? .connected : .disconnected
                let transition: VPNStatus = action == .connect ? .connecting : .disconnecting
                if latestStatus != expected && latestStatus != transition {
                    showError("The connection change could not be verified. Continue in the original client or VPN Settings.",
                              key: actionKey, group: group)
                }
            } catch {
                showError(error.localizedDescription, key: actionKey, group: group)
                failed = true
            }
            busy.remove(actionKey)
            render()
            if failed || discoveryPending { refresh() }
        }
    }

    private func showError(_ message: String, key: String, group: VPNGroup) {
        errors[key] = message
        let alert = NSAlert()
        alert.messageText = "VPN request could not be completed"
        alert.informativeText = message
        alert.addButton(withTitle: group.provider == .system ? "Open VPN Settings" : "Open Client")
        alert.addButton(withTitle: "OK")
        NSApplication.shared.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if group.provider == .system { openSettings() } else { openClient(group) }
        }
    }

    private func openClient(_ group: VPNGroup) {
        guard let url = group.applicationURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            if error != nil {
                Task { @MainActor in
                    self?.errors[group.provider.rawValue] = "Could not open the client. Refresh to rediscover it."
                    self?.render()
                }
            }
        }
    }

    private func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension")!
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }
}

private final class Selection: NSObject {
    let group: VPNGroup
    let entry: VPNEntry?
    let action: VPNAction
    init(group: VPNGroup, entry: VPNEntry?, action: VPNAction) {
        self.group = group
        self.entry = entry
        self.action = action
    }
}
