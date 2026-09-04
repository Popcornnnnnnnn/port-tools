import AppKit
import Foundation
import SwiftUI

@MainActor
final class CoreStatus: ObservableObject {
    @Published var summary = "Checking bundled core…"

    func check() {
        let helper = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/port-tools-core")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            summary = "Bundled core missing"
            return
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = helper
        process.arguments = ["--self-test"]
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let runtime = object["runtime"] as? String else {
                summary = "Bundled core failed"
                return
            }
            summary = runtime
        } catch {
            summary = "Bundled core error"
        }
    }
}

@main
struct PortToolsArchitectureApp: App {
    @StateObject private var core = CoreStatus()

    var body: some Scene {
        MenuBarExtra("Port Tools", systemImage: "network") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Port Tools")
                    .font(.headline)
                Label(core.summary, systemImage: "checkmark.seal")
                    .font(.caption)
                Divider()
                Button("Recheck bundled core") {
                    core.check()
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(14)
            .frame(width: 280)
            .task {
                core.check()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
