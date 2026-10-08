import Foundation

public final class VPNDiscovery {
    private let runner: CommandExecuting
    public static let ciscoExecutable = URL(fileURLWithPath: "/opt/cisco/secureclient/bin/vpn")
    public static let scutil = URL(fileURLWithPath: "/usr/sbin/scutil")

    public init(runner: CommandExecuting = CommandRunner()) { self.runner = runner }

    public func discover(_ apps: InstalledApplications) async -> [VPNGroup] {
        async let tailscale = tailscale(apps.tailscale)
        async let cisco = cisco(apps.cisco)
        async let openVPN = openVPN(apps.openVPN)
        async let system = system()
        return await [tailscale, cisco, openVPN, system].compactMap { $0 }
    }

    /// Refresh known sources without enumerating profiles or invoking OpenVPN.
    public func refreshStatuses(_ groups: [VPNGroup]) async -> [VPNGroup] {
        await withTaskGroup(of: (Int, VPNGroup).self, returning: [VPNGroup].self) { tasks in
            for (index, group) in groups.enumerated() {
                tasks.addTask { (index, await self.refreshStatus(group)) }
            }
            var results: [(Int, VPNGroup)] = []
            for await result in tasks { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    private func refreshStatus(_ group: VPNGroup) async -> VPNGroup {
        switch group.provider {
        case .tailscale:
            return await tailscale(group.applicationURL) ?? group
        case .cisco:
            let status = await ciscoState()
            let entries = group.entries.map {
                VPNEntry(id: $0.id, name: $0.name, profileID: $0.profileID, status: status, actions: $0.actions)
            }
            return VPNGroup(provider: .cisco, applicationURL: group.applicationURL, status: status,
                            entries: entries, issue: status == .unavailable
                            ? "Could not read Cisco status. Open the client to continue." : group.issue)
        case .system:
            return VPNGroup(provider: .system, applicationURL: nil, status: group.status,
                            entries: await systemEntries(group.entries), issue: group.issue)
        case .openVPN:
            return group
        }
    }

    public static func executable(in application: URL, fallback: String) -> URL {
        Bundle(url: application)?.executableURL ?? application.appendingPathComponent("Contents/MacOS/\(fallback)")
    }

    private func read(_ executable: URL, _ arguments: [String], environment: [String: String] = [:]) async throws -> String {
        let result = try await runner.run(executable, arguments: arguments, environment: environment, timeout: 5)
        guard result.exitCode == 0 else { throw CommandError.failed }
        return result.output
    }

    private func tailscale(_ app: URL?) async -> VPNGroup? {
        guard let app else { return nil }
        do {
            let text = try await read(Self.executable(in: app, fallback: "Tailscale"), ["status", "--json"],
                                      environment: ["TAILSCALE_BE_CLI": "1"])
            let status = try Parsers.tailscale(text)
            var actions: [VPNAction] = [.openClient]
            if status == .connected { actions.insert(.disconnect, at: 0) }
            if status == .disconnected || status == .needsLogin { actions.insert(.connect, at: 0) }
            return VPNGroup(provider: .tailscale, applicationURL: app, status: status,
                            entries: [VPNEntry(id: "tailscale", name: "Tailscale", status: status, actions: actions)])
        } catch {
            return VPNGroup(provider: .tailscale, applicationURL: app, status: .unavailable, entries: [],
                            issue: "Could not read Tailscale status. Open the client to continue.")
        }
    }

    private func cisco(_ app: URL?) async -> VPNGroup? {
        guard let app else { return nil }
        async let hostsResult = ciscoHosts()
        async let stateResult = ciscoState()
        let (hosts, status) = await (hostsResult, stateResult)
        let issue: String?
        if hosts == nil { issue = "Profiles unavailable. Open Cisco to choose a connection." }
        else if status == .unavailable { issue = "Could not read Cisco status. Open the client to continue." }
        else { issue = nil }
        let entries = (hosts ?? []).map {
            VPNEntry(id: "cisco:\($0)", name: $0, profileID: $0, status: status, actions: [.openClient])
        }
        return VPNGroup(provider: .cisco, applicationURL: app, status: status, entries: entries, issue: issue)
    }

    private func ciscoHosts() async -> [String]? {
        do { return try Parsers.ciscoHosts(await read(Self.ciscoExecutable, ["hosts"])) }
        catch { return nil }
    }

    private func ciscoState() async -> VPNStatus {
        do { return try Parsers.ciscoState(await read(Self.ciscoExecutable, ["state"])) }
        catch { return .unavailable }
    }

    private func openVPN(_ app: URL?) async -> VPNGroup? {
        guard let app else { return nil }
        do {
            let text = try await read(Self.executable(in: app, fallback: "OpenVPN Connect"), ["--list-profiles"])
            return VPNGroup(provider: .openVPN, applicationURL: app, status: .managedInClient,
                            entries: try Parsers.openVPNProfiles(text))
        } catch {
            return VPNGroup(provider: .openVPN, applicationURL: app, status: .managedInClient, entries: [],
                            issue: "Profiles unavailable. Open OpenVPN Connect to choose a connection.")
        }
    }

    private func system() async -> VPNGroup? {
        do {
            let entries = try Parsers.systemServices(await read(Self.scutil, ["--nc", "list"]))
            guard !entries.isEmpty else { return nil }
            return VPNGroup(provider: .system, applicationURL: nil, status: .unavailable,
                            entries: await systemEntries(entries))
        } catch {
            return VPNGroup(provider: .system, applicationURL: nil, status: .unavailable, entries: [],
                            issue: "Could not read system VPNs. Open VPN Settings to continue.")
        }
    }

    private func systemEntries(_ entries: [VPNEntry]) async -> [VPNEntry] {
        await withTaskGroup(of: VPNEntry.self, returning: [VPNEntry].self) { tasks in
            for entry in entries {
                tasks.addTask {
                    do {
                        let text = try await self.read(Self.scutil, ["--nc", "status", entry.profileID!])
                        return Parsers.systemEntry(id: entry.profileID!, name: entry.name,
                                                   status: try Parsers.systemState(text))
                    } catch {
                        return Parsers.systemEntry(id: entry.profileID!, name: entry.name, status: .unavailable)
                    }
                }
            }
            var results: [VPNEntry] = []
            for await entry in tasks { results.append(entry) }
            return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}

public final class VPNCommands {
    private let runner: CommandExecuting
    public init(runner: CommandExecuting = CommandRunner()) { self.runner = runner }

    public func perform(_ action: VPNAction, provider: Provider, application: URL?, profileID: String?) async throws {
        let executable: URL
        let arguments: [String]
        var environment: [String: String] = [:]
        switch (provider, action) {
        case (.tailscale, .connect), (.tailscale, .disconnect):
            guard let application else { throw CommandError.failed }
            executable = VPNDiscovery.executable(in: application, fallback: "Tailscale")
            arguments = [action == .connect ? "up" : "down"]
            environment = ["TAILSCALE_BE_CLI": "1"]
        case (.cisco, .disconnect):
            executable = VPNDiscovery.ciscoExecutable
            arguments = ["disconnect"]
        case (.system, .disconnect):
            guard let profileID else { throw CommandError.failed }
            executable = VPNDiscovery.scutil
            arguments = ["--nc", "stop", profileID]
        default: throw CommandError.failed
        }
        let result = try await runner.run(executable, arguments: arguments, environment: environment, timeout: 60)
        guard result.exitCode == 0 else { throw CommandError.failed }
    }
}
