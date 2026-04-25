import SwiftUI
import VoxCore

struct SettingsView: View {
    var body: some View {
        TabView {
            EmbedDemoTab()
                .tabItem { Label("Embed Demo", systemImage: "waveform.and.mic") }

            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            BridgeTab()
                .tabItem { Label("Bridge", systemImage: "network") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 700, minHeight: 560)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @EnvironmentObject var monitor: DaemonMonitor
    @State private var launchAgentInstalled = LaunchAgentManager.isInstalled()

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

                if let startedAt = monitor.startedAt {
                    LabeledContent("Uptime") {
                        UptimeText(startedAt: startedAt)
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
                    }

                    if !launchAgentInstalled {
                        Button("Install LaunchAgent") {
                            LaunchAgentManager.install()
                            launchAgentInstalled = LaunchAgentManager.isInstalled()
                        }
                        .tint(.accentColor)
                    }
                }

                Toggle("Start at login", isOn: .constant(launchAgentInstalled))
                    .disabled(true)
            } header: {
                Text("Actions")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAgentInstalled = LaunchAgentManager.isInstalled()
        }
    }
}

// MARK: - Bridge Tab

struct BridgeTab: View {
    @EnvironmentObject var bridgeState: BridgeState

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

                if let statusDetail = bridgeState.statusDetail, !statusDetail.isEmpty {
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(bridgeState.isRunning ? Color.secondary : Color.red)
                }
            } header: {
                Text("HTTP Bridge")
            }

            Section {
                Text("Web apps from allowed origins can connect to the local bridge for transcription and alignment.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField(
                        "https://app.example.com or http://localhost:*",
                        text: Binding(
                            get: { bridgeState.draftOrigin },
                            set: { newValue in
                                bridgeState.draftOrigin = newValue
                                bridgeState.clearOriginError()
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Button("Add") {
                        bridgeState.addDraftOrigin()
                    }
                    .disabled(!bridgeState.canAddOrigin)
                }

                if let message = bridgeState.originsErrorMessage, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Allowed Origins")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Origins must be full browser origins. Paths are not allowed.")
                    Text("Wildcard ports are only supported for localhost, 127.0.0.1, and ::1. Example: http://localhost:*")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !bridgeState.userOrigins.isEmpty {
                Section {
                    ForEach(bridgeState.userOrigins, id: \.self) { origin in
                        HStack {
                            Text(origin)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button("Remove") {
                                bridgeState.removeOrigin(origin)
                            }
                        }
                    }
                } header: {
                    Text("Added In Vox")
                }
            }

            if !bridgeState.integrationOrigins.isEmpty {
                Section {
                    ForEach(bridgeState.integrationOrigins, id: \.self) { origin in
                        Text(origin)
                            .font(.system(.body, design: .monospaced))
                    }
                } header: {
                    Text("Integration Registrations")
                }
            }

            Section {
                ForEach(bridgeState.builtinOrigins, id: \.self) { origin in
                    Text(origin)
                        .font(.system(.body, design: .monospaced))
                }
            } header: {
                Text("Built-In Origins")
            }

            Section {
                LabeledContent("User File") {
                    Text("~/.vox/origins.json")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                LabeledContent("Integration Drop-Ins") {
                    Text("~/.vox/origins.d/")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                Text("Integrations can register origins by writing a JSON file such as {\"origins\":[\"https://app.example.com\"]} into ~/.vox/origins.d/. Vox merges those entries with the built-in and user-managed lists.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Configuration")
            }
        }
        .formStyle(.grouped)
        .task {
            await bridgeState.refreshOrigins()
        }
    }
}

private struct UptimeText: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(formatUptime(context.date.timeIntervalSince(startedAt)))
                .monospacedDigit()
        }
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
