import PitstopCore
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var store: UsageStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var notifyOnReset = ResetNotifier.isEnabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Pitstop").font(.headline)
                Spacer()
                if store.isRefreshing { ProgressView().controlSize(.small) }
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh now")
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

            HStack {
                Button("Edit accounts") { NSWorkspace.shared.open(PitstopPaths.accounts) }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }

            if let last = store.lastRefresh {
                Text("Updated \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { store.refreshIfStale() }
    }
}

struct AccountSection: View {
    let snapshot: AccountSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
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
                Text(window.label).font(.caption)
                Spacer()
                Text("\(percent(window.remainingPercent)) left")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(color)
            }
            ProgressView(value: min(window.usedPercent, 100), total: 100)
                .tint(color)
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
