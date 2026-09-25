import PitstopCore
import SwiftUI

/// App Store version string ("0.2.0"), falling back to "" if Info.plist is missing it
/// (e.g. running via `swift run` instead of a real .app bundle).
private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

struct MenuContentView: View {
    @EnvironmentObject private var store: UsageStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var notifyOnReset = ResetNotifier.isEnabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pitstop").font(.headline)
                    if let appVersion {
                        Text("v\(appVersion)").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    if store.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else if let last = store.lastRefresh {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text("Updated \(relativeTime(last, now: context.date))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Refresh") { store.refresh() }
                        .font(.caption2)
                        .controlSize(.small)
                }
            }

            if let problem = store.accountsProblem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if store.snapshots.isEmpty && !store.isRefreshing {
                Text("Sign in to Claude Code or Codex on this Mac, then refresh.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(store.snapshots) { AccountSection(snapshot: $0) }

            Divider()

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    guard enabled != LaunchAtLogin.isEnabled else { return }
                    do {
                        try LaunchAtLogin.set(enabled)
                        loginError = nil
                    } catch {
                        loginError = "Couldn't change login item: \(error.localizedDescription)"
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }

            Toggle("Notify when limits reset", isOn: $notifyOnReset)
                .onChange(of: notifyOnReset) { _, enabled in
                    ResetNotifier.isEnabled = enabled
                    if enabled { ResetNotifier.schedule(for: store.snapshots) } else { ResetNotifier.cancelAll() }
                }

            MenuRow("Edit accounts") { NSWorkspace.shared.open(PitstopPaths.accounts) }

            Divider()

            MenuRow("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { store.refreshIfStale() }
    }
}

/// A full-width, borderless, left-aligned row for the bottom of the menu
/// (Edit accounts, Quit), with a subtle hover highlight.
struct MenuRow: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .background(hovering ? Color.primary.opacity(0.06) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// "just now" / "3m ago" / "2h ago" for the header's Updated label.
private func relativeTime(_ date: Date, now: Date = .now) -> String {
    let seconds = Int(now.timeIntervalSince(date))
    if seconds < 60 { return "just now" }
    if seconds < 3_600 { return "\(seconds / 60)m ago" }
    return "\(seconds / 3_600)h ago"
}

/// Each tool's logo, from the bundled asset catalog.
struct ProviderBadge: View {
    let provider: ProviderKind
    var size: CGFloat = 15

    private var fileName: String {
        switch provider {
        case .claude: return "claude-logo"
        case .codex: return "codex-logo"
        }
    }

    var body: some View {
        Group {
            if let url = Bundle.module.url(forResource: fileName, withExtension: "png"),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage).resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
    }
}

struct AccountSection: View {
    let snapshot: AccountSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                ProviderBadge(provider: snapshot.account.provider)
                Text(snapshot.account.provider.displayName).font(.subheadline.weight(.semibold))
                Text(snapshot.account.name).font(.caption).foregroundStyle(.secondary)
            }
            if let error = snapshot.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            ForEach(snapshot.windows) { WindowRow(window: $0) }
            if let note = snapshot.note {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct WindowRow: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(percent(window.remainingPercent)) left")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(color)
            }
            ThinProgressBar(fraction: min(window.usedPercent, 100) / 100, tint: color)
            if let resets = window.resetsAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("Resets in \(countdown(to: resets, from: context.date)), \(resetClock(resets, now: context.date))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var color: Color {
        switch window.remainingPercent {
        case ..<15: return .red
        case ..<40: return .orange
        default: return .green
        }
    }
}

/// A slimmer bar than the stock `ProgressView`, since the default is too thick for a menu-bar popover.
struct ThinProgressBar: View {
    let fraction: Double
    let tint: Color
    private let height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(tint).frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: height)
    }
}