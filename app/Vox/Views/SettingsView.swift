import SwiftUI
import VoxCore

struct SettingsView: View {
    @EnvironmentObject var monitor: DaemonMonitor
    @EnvironmentObject var bridgeState: BridgeState

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            BridgeTab()
                .tabItem { Label("Bridge", systemImage: "network") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 460, minHeight: 360)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @EnvironmentObject var monitor: DaemonMonitor

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(monitor.isRunning ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(monitor.isRunning ? "Running" : "Stopped")
                            .foregroundStyle(monitor.isRunning ? .primary : .secondary)
                    }
                }

                if let port = monitor.port {
                    LabeledContent("Daemon Port") {
                        Text("\(port)")
                            .monospacedDigit()
                    }
                }

                if let pid = monitor.pid {
                    LabeledContent("PID") {
                        Text("\(pid)")
                            .monospacedDigit()
                    }
                }

                if let uptime = monitor.uptime {
                    LabeledContent("Uptime") {
                        Text(formatUptime(uptime))
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Daemon")
            }

            Section {
                LabeledContent("Model") {
                    Text("Parakeet TDT v3")
                }

                LabeledContent("Backend") {
                    Text("FluidAudio (CoreML)")
                }
            } header: {
                Text("Model")
            }

            Section {
                HStack {
                    Button("Restart Daemon") {
                        LaunchAgentManager.restart()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            monitor.checkNow()
                        }
                    }

                    if !LaunchAgentManager.isInstalled() {
                        Button("Install LaunchAgent") {
                            LaunchAgentManager.install()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                monitor.checkNow()
                            }
                        }
                        .tint(.accentColor)
                    }
                }

                Toggle("Start at login", isOn: .constant(LaunchAgentManager.isInstalled()))
                    .disabled(true)
            } header: {
                Text("Actions")
            }
        }
        .formStyle(.grouped)
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Bridge Tab

struct BridgeTab: View {
    @EnvironmentObject var bridgeState: BridgeState
    @State private var newOrigin = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(bridgeState.isRunning ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(bridgeState.isRunning ? "Listening" : "Stopped")
                    }
                }

                LabeledContent("Port") {
                    Text("\(bridgeState.port)")
                        .monospacedDigit()
                }

                LabeledContent("Address") {
                    Text("http://127.0.0.1:\(bridgeState.port)")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            } header: {
                Text("HTTP Bridge")
            }

            Section {
                Text("Web apps from allowed origins can connect to the local bridge for transcription and alignment.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("https://uselinea.com")
                        .font(.system(.body, design: .monospaced))
                    Text("https://www.uselinea.com")
                        .font(.system(.body, design: .monospaced))
                }
                .padding(.vertical, 2)
            } header: {
                Text("Allowed Origins")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version") {
                    Text(VoxVersion.current)
                }

                LabeledContent("Runtime") {
                    Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                }

                LabeledContent("Data") {
                    Text("~/.vox/")
                        .font(.system(.body, design: .monospaced))
                }
            } header: {
                Text("Vox Companion")
            }

            Section {
                Text("Vox is a local-first transcription runtime for macOS. It runs an on-device ASR model and exposes it to web apps and developer tools via a localhost bridge.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
    }
}
