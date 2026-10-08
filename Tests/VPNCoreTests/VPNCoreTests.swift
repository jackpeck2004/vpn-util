import Foundation
import VPNCore

final class VPNCoreTests {
    private let listing = """
    Available network connection services in the current set (*=enabled):
    * (Disconnected)   00000000-0000-4000-8000-000000000001 VPN (io.tailscale.ipn.macsys) "Tailscale" [VPN:io.tailscale.ipn.macsys]
    * (Disconnected)   00000000-0000-4000-8000-000000000002 PPP --> L2TP "Office \"VPN\" $HOME; $(test)" [PPP:L2TP]
    * (Connected)   00000000-0000-4000-8000-000000000003 IPSec "Home" [IPSec]
    """

    func testSystemServicesExcludeThirdPartyAndPreserveNames() throws {
        let entries = try Parsers.systemServices(listing)
        expectEqual(entries.count, 2)
        expectEqual(entries[0].name, "Office \"VPN\" $HOME; $(test)")
        expectEqual(entries[0].profileID, "00000000-0000-4000-8000-000000000002")
        expectEqual(entries[0].actions, [.openSettings])
        expectEqual(entries[1].actions, [.disconnect, .openSettings])
        expectEqual(try Parsers.systemServices(listing + "\n" + listing).count, 2)
        expectThrows(try Parsers.systemServices("permission denied"))
    }

    func testStatusParsingDoesNotConfuseDisconnectedWithConnected() throws {
        expectEqual(try Parsers.ciscoState(">> state: Connected\n>> state: Disconnected\n"), .disconnected)
        expectEqual(try Parsers.systemState("Disconnected\nMore output"), .disconnected)
        expectEqual(try Parsers.tailscale(#"{"BackendState":"NeedsLogin"}"#), .needsLogin)
        expectEqual(try Parsers.tailscale(#"{"BackendState":"Stopped"}"#), .disconnected)
        expectEqual(try Parsers.tailscale(#"{"BackendState":"Running"}"#), .connected)
        expectEqual(try Parsers.tailscale(#"{"BackendState":"FutureState"}"#), .unavailable)
        expectThrows(try Parsers.ciscoState("No state"))
        expectThrows(try Parsers.systemState("VPN service failed"))
        expectThrows(try Parsers.tailscale("{}"))
    }

    func testProfileParsingAndDeduplication() throws {
        let hosts = try Parsers.ciscoHosts("Cisco client\n[hosts]:\n > Office VPN\n > Office VPN\n > $(never-run); $HOME\n")
        expectEqual(hosts, ["Office VPN", "$(never-run); $HOME"])
        expectThrows(try Parsers.ciscoHosts("unable to attach"))
        expectEqual(try Parsers.ciscoHosts("[hosts]:\n"), [])
        let profiles = try Parsers.openVPNProfiles(#"[{"id":"one","name":"VPN ; $(test)","username":"ignore"},{"id":"one","name":"Duplicate"}]"#)
        expectEqual(profiles.count, 1)
        expectEqual(profiles[0].name, "VPN ; $(test)")
        expectEqual(profiles[0].actions, [.openClient])
        expectThrows(try Parsers.openVPNProfiles(#"{"error":"consent required"}"#))
    }

    func testMissingClientsAndFailureIsolation() async {
        let runner = MockRunner()
        await runner.set(["--nc", "list"], result: .success(CommandResult(output: "Available network connection services in the current set (*=enabled):")))
        let discovery = VPNDiscovery(runner: runner)
        let empty = await discovery.discover(InstalledApplications())
        expectTrue(empty.isEmpty)
        await runner.set(["status", "--json"], result: .success(CommandResult(output: #"{"BackendState":"Running"}"#)))
        let groups = await discovery.discover(InstalledApplications(tailscale: URL(fileURLWithPath: "/missing/Tailscale.app"),
                                                                  cisco: URL(fileURLWithPath: "/missing/Cisco.app"),
                                                                  openVPN: URL(fileURLWithPath: "/missing/OpenVPN.app")))
        expectEqual(groups.map(\.provider), [.tailscale, .cisco, .openVPN])
        expectEqual(groups[0].status, .connected)
        expectNotNil(groups[1].issue)
        expectNotNil(groups[2].issue)
        let calls = await runner.calls
        expectTrue(calls.allSatisfy { $0.timeout == 5 })
        expectFalse(calls.contains { $0.arguments.contains("up") || $0.arguments.contains("disconnect") })
    }

    func testCommandArgumentsAreNotShellInterpolated() async throws {
        let runner = MockRunner()
        let profile = "quoted profile ; $(touch /tmp/never-create)"
        await runner.set(["--nc", "stop", profile], result: .success(CommandResult(output: "")))
        try await VPNCommands(runner: runner).perform(.disconnect, provider: .system, application: nil, profileID: profile)
        let call = await runner.calls.last!
        expectEqual(call.executable.path, "/usr/sbin/scutil")
        expectEqual(call.arguments, ["--nc", "stop", profile])
        expectEqual(call.timeout, 60)
    }

    func testNativeConnectDoesNotStartWithoutSystemAuthentication() async {
        let runner = MockRunner()
        let profile = "00000000-0000-4000-8000-000000000002"
        await runner.set(["--nc", "start", profile], result: .success(CommandResult(output: "")))
        do {
            try await VPNCommands(runner: runner).perform(.connect, provider: .system,
                                                         application: nil, profileID: profile)
            fail("Native connect must hand off to VPN Settings")
        } catch {}
        let calls = await runner.calls
        expectTrue(calls.isEmpty)
        expectEqual(Parsers.systemEntry(id: profile, name: "Office", status: .disconnected).actions, [.openSettings])
        expectEqual(Parsers.systemEntry(id: profile, name: "Office", status: .connected).actions, [.disconnect, .openSettings])
    }

    func testTailscaleUsesCLIEnvironmentAndNoConfigurationFlags() async throws {
        let runner = MockRunner()
        await runner.set(["up"], result: .success(CommandResult(output: "")))
        try await VPNCommands(runner: runner).perform(.connect, provider: .tailscale,
                                                     application: URL(fileURLWithPath: "/missing/Tailscale.app"), profileID: nil)
        let call = await runner.calls.last!
        expectEqual(call.arguments, ["up"])
        expectEqual(call.environment["TAILSCALE_BE_CLI"], "1")
    }

    func testCanonicalPathsDeduplicateAliases() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("App.app")
        let alias = root.appendingPathComponent("Alias.app")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        expectEqual(ApplicationPaths.unique([real, alias]).count, 1)
    }

    func testRealRunnerDrainsLargeOutputWithoutDeadlock() async throws {
        let result = try await CommandRunner().run(URL(fileURLWithPath: "/usr/bin/seq"), arguments: ["1", "20000"], timeout: 5)
        expectEqual(result.exitCode, 0)
        expectTrue(result.output.hasSuffix("20000\n"))
    }

    func testRealRunnerTimeoutTerminatesProcess() async {
        let start = Date()
        do {
            _ = try await CommandRunner().run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.1)
            fail("Expected timeout")
        } catch {
            expectEqual(error as? CommandError, .timedOut)
        }
        expectLessThan(Date().timeIntervalSince(start), 3)
    }

    func testExitedProcessDoesNotWaitForInheritedPipes() async throws {
        let start = Date()
        let result = try await CommandRunner().run(URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf done; sleep 2 &"], timeout: 5)
        expectEqual(result.output, "done")
        expectEqual(result.exitCode, 0)
        expectLessThan(Date().timeIntervalSince(start), 1)
    }

    func testOversizedOutputIsRejected() async {
        do {
            _ = try await CommandRunner().run(URL(fileURLWithPath: "/usr/bin/seq"), arguments: ["1", "100000"], timeout: 5)
            fail("Expected an output limit error")
        } catch { expectEqual(error as? CommandError, .outputTooLarge) }
    }

    func testTimeoutKillsProcessIgnoringTermination() async {
        let start = Date()
        do {
            _ = try await CommandRunner().run(URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; exec sleep 10"], timeout: 0.1)
            fail("Expected timeout")
        } catch { expectEqual(error as? CommandError, .timedOut) }
        expectLessThan(Date().timeIntervalSince(start), 3)
    }
}

private actor MockRunner: CommandExecuting {
    struct Call {
        let executable: URL
        let arguments: [String]
        let environment: [String: String]
        let timeout: TimeInterval
    }
    var calls: [Call] = []
    private var results: [[String]: Result<CommandResult, Error>] = [:]

    func set(_ arguments: [String], result: Result<CommandResult, Error>) { results[arguments] = result }

    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval) async throws -> CommandResult {
        calls.append(Call(executable: executable, arguments: arguments, environment: environment, timeout: timeout))
        return try (results[arguments] ?? .failure(CommandError.failed)).get()
    }
}


// Portable checks: no XCTest or Xcode dependency. All checks run sequentially.
private enum Assertions {
    static var failures: [String] = []
}

private func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    Assertions.failures.append("\(file):\(line): \(message)")
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { fail("Expected \(expected), got \(actual)", file: file, line: line) }
}

private func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value { fail("Expected true", file: file, line: line) }
}

private func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if value { fail("Expected false", file: file, line: line) }
}

private func expectNotNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value == nil { fail("Expected a value", file: file, line: line) }
}

private func expectLessThan<T: Comparable>(_ actual: T, _ bound: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual >= bound { fail("Expected \(actual) < \(bound)", file: file, line: line) }
}

private func expectThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); fail("Expected an error", file: file, line: line) }
    catch {}
}

@main
private struct TestMain {
    static func main() async {
        let checks = VPNCoreTests()
        let cases: [(String, () async throws -> Void)] = [
            ("native discovery and names", { try checks.testSystemServicesExcludeThirdPartyAndPreserveNames() }),
            ("status parsing", { try checks.testStatusParsingDoesNotConfuseDisconnectedWithConnected() }),
            ("profile parsing and deduplication", { try checks.testProfileParsingAndDeduplication() }),
            ("missing clients and failure isolation", { await checks.testMissingClientsAndFailureIsolation() }),
            ("safe command arguments", { try await checks.testCommandArgumentsAreNotShellInterpolated() }),
            ("native authentication handoff", { await checks.testNativeConnectDoesNotStartWithoutSystemAuthentication() }),
            ("Tailscale CLI environment", { try await checks.testTailscaleUsesCLIEnvironmentAndNoConfigurationFlags() }),
            ("application alias deduplication", { try checks.testCanonicalPathsDeduplicateAliases() }),
            ("pipe draining", { try await checks.testRealRunnerDrainsLargeOutputWithoutDeadlock() }),
            ("process timeout", { await checks.testRealRunnerTimeoutTerminatesProcess() }),
            ("inherited pipe lifetime", { try await checks.testExitedProcessDoesNotWaitForInheritedPipes() }),
            ("output size limit", { await checks.testOversizedOutputIsRejected() }),
            ("forced timeout termination", { await checks.testTimeoutKillsProcessIgnoringTermination() })
        ]
        for (name, test) in cases {
            let before = Assertions.failures.count
            do { try await test() } catch { fail("\(name): \(error)") }
            print("\(Assertions.failures.count == before ? "PASS" : "FAIL") \(name)")
        }
        if !Assertions.failures.isEmpty {
            for message in Assertions.failures { print(message) }
            exit(1)
        }
        print("All \(cases.count) checks passed.")
    }
}
