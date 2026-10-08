import Foundation

public enum ParseError: Error { case malformed }

public enum Parsers {
    public static func tailscale(_ text: String) throws -> VPNStatus {
        struct Status: Decodable { let BackendState: String }
        let state = try JSONDecoder().decode(Status.self, from: Data(text.utf8)).BackendState
        switch state {
        case "Running": return .connected
        case "Stopped": return .disconnected
        case "Starting": return .connecting
        case "NeedsLogin": return .needsLogin
        default: return .unavailable
        }
    }

    public static func ciscoState(_ text: String) throws -> VPNStatus {
        let expression = try NSRegularExpression(pattern: #"(?im)^\s*(?:>>\s*)?state:\s*(connected|disconnected|connecting|disconnecting)\s*$"#)
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let match = matches.last, let range = Range(match.range(at: 1), in: text),
              let status = VPNStatus(rawValue: text[range].lowercased()) else { throw ParseError.malformed }
        return status
    }

    public static func ciscoHosts(_ text: String) throws -> [String] {
        guard let marker = text.range(of: "[hosts]:", options: .caseInsensitive) else { throw ParseError.malformed }
        var seen = Set<String>()
        return text[marker.upperBound...].split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix(">"), !trimmed.hasPrefix(">>") else { return nil }
            let name = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return name
        }
    }

    public static func openVPNProfiles(_ text: String) throws -> [VPNEntry] {
        struct Profile: Decodable { let id: String; let name: String }
        let profiles = try JSONDecoder().decode([Profile].self, from: Data(text.utf8))
        var seen = Set<String>()
        return profiles.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }.map {
            VPNEntry(id: "openVPN:\($0.id)", name: $0.name, profileID: $0.id,
                     status: .managedInClient, actions: [.openClient])
        }
    }

    public static func systemServices(_ text: String) throws -> [VPNEntry] {
        guard text.contains("Available network connection services") else { throw ParseError.malformed }
        let expression = try NSRegularExpression(pattern: #"(?m)^\*?\s*\(([^)]+)\)\s+([0-9A-Fa-f-]{36})\s+(.+?)\s+"(.*)"\s+\["#)
        var seen = Set<String>()
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            func field(_ index: Int) -> String {
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
            let kind = field(3).trimmingCharacters(in: .whitespaces)
            // Third-party Network Extensions are owned by their clients, not this integration.
            guard kind == "PPP --> L2TP" || kind == "IPSec" else { return nil }
            let id = field(2).uppercased()
            guard seen.insert(id).inserted else { return nil }
            return systemEntry(id: id, name: field(4), status: status(field(1)))
        }
    }

    public static func systemState(_ text: String) throws -> VPNStatus {
        guard let first = text.split(separator: "\n").first else { throw ParseError.malformed }
        let parsed = status(first.trimmingCharacters(in: .whitespaces))
        guard parsed != .unavailable else { throw ParseError.malformed }
        return parsed
    }

    public static func systemEntry(id: String, name: String, status: VPNStatus) -> VPNEntry {
        var actions: [VPNAction] = [.openSettings]
        if status == .connected { actions.insert(.disconnect, at: 0) }
        // scutil start supplies authentication overrides even without credentials.
        // Let macOS use its saved authentication through the original settings UI.
        return VPNEntry(id: "system:\(id)", name: name, profileID: id, status: status, actions: actions)
    }

    private static func status(_ text: String) -> VPNStatus {
        VPNStatus(rawValue: text.lowercased()) ?? .unavailable
    }
}
