import AppKit
import VPNCore

@MainActor
struct ApplicationLocator {
    func discover() -> InstalledApplications {
        InstalledApplications(
            tailscale: find(ids: ["io.tailscale.ipn.macsys", "io.tailscale.ipn.macos"], paths: ["Tailscale.app"]),
            cisco: find(ids: ["com.cisco.secureclient.gui"], paths: ["Cisco/Cisco Secure Client.app", "Cisco Secure Client.app"]),
            openVPN: find(ids: ["org.openvpn.client.app"], paths: ["OpenVPN Connect/OpenVPN Connect.app", "OpenVPN Connect.app"])
        )
    }

    private func find(ids: [String], paths: [String]) -> URL? {
        let workspace = NSWorkspace.shared
        let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true),
                     FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
        let candidates = ids.compactMap { workspace.urlForApplication(withBundleIdentifier: $0) }
            + roots.flatMap { root in paths.map { root.appendingPathComponent($0, isDirectory: true) } }
        return ApplicationPaths.unique(candidates).first {
            guard FileManager.default.fileExists(atPath: $0.path), let bundle = Bundle(url: $0),
                  let id = bundle.bundleIdentifier else { return false }
            return ids.contains(id)
        }
    }
}
