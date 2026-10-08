import Foundation

/// Observed connected sources only. A client-level state must not imply that
/// every profile in that client is active.
public struct ActiveConnection {
    public let group: VPNGroup
    public let entry: VPNEntry?

    public var name: String { entry?.name ?? group.provider.title }
    public var canDisconnect: Bool {
        if group.provider == .cisco { return true }
        return entry?.actions.contains(.disconnect) == true
    }
    public var openAction: VPNAction { group.provider == .system ? .openSettings : .openClient }

    public static func observed(in groups: [VPNGroup]) -> [ActiveConnection] {
        groups.flatMap { group -> [ActiveConnection] in
            switch group.provider {
            case .system:
                return group.entries.filter { $0.status == .connected }
                    .map { ActiveConnection(group: group, entry: $0) }
            case .tailscale:
                guard group.status == .connected else { return [] }
                return [ActiveConnection(group: group, entry: group.entries.first)]
            case .cisco:
                guard group.status == .connected else { return [] }
                return [ActiveConnection(group: group, entry: nil)]
            case .openVPN:
                // There is no supported live connection status for this client.
                return []
            }
        }
    }
}
