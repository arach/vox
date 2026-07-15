import AppKit
import SwiftUI
import VoxCore

struct MinivoxSettingsView: View {
    @ObservedObject var model: MinivoxModel

    @AppStorage("minivox.appearance") private var appearanceRawValue = MinivoxAppearance.system.rawValue
    @AppStorage(MinivoxModel.autoPasteDefaultsKey) private var autoPaste = true
    @AppStorage(MinivoxModel.warmUpOnLaunchDefaultsKey) private var warmUpOnLaunch = false
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    settingsSection
                    modelSection
                }
                .padding(14)
            }

            HStack {
                Text("Minivox \(version) · local-first")
                Spacer()
            }
            .font(.system(size: 8, weight: .regular, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(palette.strip)
            .overlay(alignment: .top) {
                Rectangle().fill(palette.border).frame(height: 0.5)
            }
        }
        .frame(height: 330)
        .background(palette.background)
        .environment(\.colorScheme, effectiveColorScheme)
        .preferredColorScheme(selectedAppearance.colorScheme)
        .onAppear {
            model.refreshAutoPasteAccess()
        }
        .onDisappear {
            model.cancelShortcutCapture()
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("General")

            VStack(spacing: 0) {
                HStack {
                    Text("Appearance")
                    Spacer()

                    Picker("Appearance", selection: $appearanceRawValue) {
                        Image(systemName: "circle.lefthalf.filled")
                            .tag(MinivoxAppearance.system.rawValue)
                        Image(systemName: "sun.max")
                            .tag(MinivoxAppearance.light.rawValue)
                        Image(systemName: "moon")
                            .tag(MinivoxAppearance.dark.rawValue)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 108)
                    .tint(palette.accent)
                }
                .frame(minHeight: 40)

                divider

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dictation shortcut")
                        Text(model.isCapturingShortcut ? "Press a combo · Esc cancels" : "Click to edit")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button {
                        if model.isCapturingShortcut {
                            model.cancelShortcutCapture()
                        } else {
                            model.beginShortcutCapture()
                        }
                    } label: {
                        Text(
                            model.isCapturingShortcut
                                ? "…"
                                : model.dictationShortcut?.title ?? "Set"
                        )
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 10)
                        .frame(minWidth: 46, minHeight: 24)
                        .background(
                            model.isCapturingShortcut ? palette.accent.opacity(0.16) : palette.controlSurface,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(
                                    model.isCapturingShortcut ? palette.accent.opacity(0.6) : palette.border,
                                    lineWidth: 0.5
                                )
                        }
                    }
                    .buttonStyle(.plain)

                    if model.dictationShortcut != nil && !model.isCapturingShortcut {
                        Button {
                            model.disableShortcut()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .help("Clear shortcut")
                    }
                }
                .frame(minHeight: 48)

                divider

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Paste automatically")
                        Text(autoPasteDetail)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Toggle("", isOn: $autoPaste)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(palette.accent)
                        .onChange(of: autoPaste) { _, isEnabled in
                            model.autoPastePreferenceDidChange(isEnabled: isEnabled)
                        }
                }
                .frame(minHeight: 44)

                divider

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Warm up on launch")
                        Text("Keep Parakeet resident")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Toggle("", isOn: $warmUpOnLaunch)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(palette.accent)
                }
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 12)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 0.5)
            }

            if model.isCapturingShortcut || !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Model")

            HStack {
                Text("Engine")
                Spacer()
                Text("Parakeet · on-device")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 0.5)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 7.5, weight: .medium, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(.tertiary)
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.border)
            .frame(height: 0.5)
    }

    private var autoPasteDetail: String {
        if !autoPaste { return "Copy only" }
        return model.autoPasteAccessGranted ? "Insert in active app" : "Needs Accessibility"
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var selectedAppearance: MinivoxAppearance {
        MinivoxAppearance(rawValue: appearanceRawValue) ?? .system
    }

    private var effectiveColorScheme: ColorScheme {
        selectedAppearance.colorScheme ?? systemColorScheme
    }

    private var palette: MinivoxPalette {
        MinivoxPalette(colorScheme: effectiveColorScheme)
    }
}

struct MinivoxHistoryView: View {
    @ObservedObject var model: MinivoxModel

    @AppStorage("minivox.appearance") private var appearanceRawValue = MinivoxAppearance.system.rawValue
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var isConfirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if model.historyRecords.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("No dictations yet")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        Text("Finished transcripts stay on this Mac.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.historyRecords.enumerated()), id: \.element.id) { index, record in
                                historyRow(record)

                                if index < model.historyRecords.count - 1 {
                                    Rectangle()
                                        .fill(palette.border)
                                        .frame(height: 0.5)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Text("\(model.historyRecords.count) dictation\(model.historyRecords.count == 1 ? "" : "s") · local")
                Spacer()

                if !model.historyRecords.isEmpty {
                    Button("Clear all", role: .destructive) {
                        isConfirmingClear = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 8.5, weight: .regular, design: .monospaced))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(palette.strip)
            .overlay(alignment: .top) {
                Rectangle().fill(palette.border).frame(height: 0.5)
            }
        }
        .frame(height: 240)
        .background(palette.background)
        .environment(\.colorScheme, effectiveColorScheme)
        .preferredColorScheme(selectedAppearance.colorScheme)
        .task {
            model.loadHistory()
        }
        .alert("Clear Minivox history?", isPresented: $isConfirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear all", role: .destructive) {
                model.clearHistory()
            }
        } message: {
            Text("This removes Minivox dictations stored on this Mac.")
        }
    }

    private func historyRow(_ record: SpeechHistoryRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(record.text ?? "")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .lineSpacing(3)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(relativeDate(record.completedAt))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Button {
                model.copyHistoryRecord(record)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(palette.controlSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy")
        }
        .padding(.vertical, 12)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var selectedAppearance: MinivoxAppearance {
        MinivoxAppearance(rawValue: appearanceRawValue) ?? .system
    }

    private var effectiveColorScheme: ColorScheme {
        selectedAppearance.colorScheme ?? systemColorScheme
    }

    private var palette: MinivoxPalette {
        MinivoxPalette(colorScheme: effectiveColorScheme)
    }
}
