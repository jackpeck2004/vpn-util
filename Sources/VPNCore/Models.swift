import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable {
    case tailscale, cisco, openVPN, system

    public var title: String {
        switch self {
        case .tailscale: return "Tailscale"
        case .cisco: return "Cisco Secure Client"
        case .openVPN: return "OpenVPN Connect"
        case .system: return "macOS VPN"
        }
    }
}

public enum VPNStatus: String, Codable, Sendable {
    case connected, disconnected, connecting, disconnecting, needsLogin, unavailable, managedInClient

    public var title: String {
        switch self {
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        case .needsLogin: return "Login required"
        case .unavailable: return "Status unavailable"
        case .managedInClient: return "Status in OpenVPN Connect"
        }
    }
}

public enum VPNAction: String, Codable, Sendable {
    case connect, disconnect, openClient, openSettings
}

public struct VPNEntry: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let profileID: String?
    public let status: VPNStatus
    public let actions: [VPNAction]

    public init(id: String, name: String, profileID: String? = nil,
                status: VPNStatus, actions: [VPNAction]) {
        self.id = id
        self.name = name
        self.profileID = profileID
        self.status = status
        self.actions = actions
    }
}

public struct VPNGroup: Codable, Sendable {
    public let provider: Provider
    public let applicationURL: URL?
    public let status: VPNStatus
    public let entries: [VPNEntry]
    public let issue: String?

    public init(provider: Provider, applicationURL: URL?, status: VPNStatus,
                entries: [VPNEntry], issue: String? = nil) {
        self.provider = provider
        self.applicationURL = applicationURL
        self.status = status
        self.entries = entries
        self.issue = issue
    }
}

public struct InstalledApplications {
    public var tailscale: URL?
    public var cisco: URL?
    public var openVPN: URL?

    public init(tailscale: URL? = nil, cisco: URL? = nil, openVPN: URL? = nil) {
        self.tailscale = tailscale
        self.cisco = cisco
        self.openVPN = openVPN
    }
}

public enum ApplicationPaths {
    public static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.map { $0.resolvingSymlinksInPath().standardizedFileURL }
            .filter { seen.insert($0.path).inserted }
    }
}
