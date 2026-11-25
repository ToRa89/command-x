// ContentView.swift
// Command X
//
// Main UI for settings and status. Uses Liquid Glass on macOS 26+,
// falls back to system materials on older versions.

import SwiftUI
import ApplicationServices

// MARK: - Glass helpers

private extension View {
    /// Glass card: Liquid Glass on macOS 26+, ultra-thin material before that.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
            )
        }
    }

    /// Glass button style where available.
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// Groups glass elements so they blend and render together on macOS 26+.
private struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

// MARK: - View

struct ContentView: View {
    @AppStorage("cutSoundEnabled") var cutSoundEnabled: Bool = true
    @State private var isAccessibilityGranted: Bool = AXIsProcessTrusted()
    @State private var showPermissionAlert = false
    @State private var launchAtLogin: Bool = true

    var body: some View {
        GlassGroup(spacing: 12) {
            VStack(spacing: 12) {
                header
                permissionCard
                optionsCard
                actions
            }
            .padding(16)
        }
        .frame(width: 360)
        .onAppear {
            isAccessibilityGranted = AXIsProcessTrusted()
            // Delay sync to avoid issues during view initialization
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                launchAtLogin = LaunchAtLoginManager.shared.isEnabled
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAccessibilityGranted = AXIsProcessTrusted()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.willShowNotification)) { _ in
            isAccessibilityGranted = AXIsProcessTrusted()
        }
        .onChange(of: launchAtLogin) { newValue in
            LaunchAtLoginManager.shared.isEnabled = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandXPermissionError"))) { _ in
            showPermissionAlert = true
        }
        .alert(isPresented: $showPermissionAlert) {
            Alert(
                title: Text("Permission Required"),
                message: Text("Command X needs Accessibility and Automation permissions to control Finder and System Events. Please grant these in System Settings > Privacy & Security > Accessibility (add Command X) and Automation (allow control of Finder and System Events)."),
                primaryButton: .default(Text("Open System Settings"), action: {
                    openSystemSettings()
                }),
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Command X")
                    .font(.title3.weight(.semibold))
                Text("Cut and paste files in Finder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var permissionCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isAccessibilityGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.title2)
                .foregroundStyle(isAccessibilityGranted ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(isAccessibilityGranted ? "Accessibility access granted" : "Accessibility access needed")
                    .font(.headline)
                if !isAccessibilityGranted {
                    Text("System Settings → Privacy & Security → Accessibility → add Command X and switch it on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Accessibility Settings…") { openSystemSettings() }
                        .glassButton()
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var optionsCard: some View {
        VStack(spacing: 12) {
            Toggle("Crumple sound when cutting", isOn: $cutSoundEnabled)
            Divider().opacity(0.4)
            Toggle("Launch at Login", isOn: $launchAtLogin)
        }
        .toggleStyle(.switch)
        .padding(14)
        .glassCard()
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit Command X").frame(maxWidth: .infinity)
            }
            .glassButton()
            .controlSize(.large)

            Button {
                LaunchAtLoginManager.shared.isEnabled = false
                NSApp.terminate(nil)
            } label: {
                Text("Quit and Remove from Login Items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    private func openSystemSettings() {
        // Registers Command X in the Accessibility list (unchecked) and shows the system prompt.
        // macOS does not allow an app to switch the checkbox on itself; the user must do that.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Also open System Settings > Privacy & Security > Accessibility
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
