import SwiftUI

@main
struct PitstopApp: App {
    @StateObject private var store = UsageStore()

    init() {
        LaunchAtLogin.enableOnFirstRun()
        ResetNotifier.requestPermission()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(store)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "fuelpump")
                if let remaining = store.tightestRemaining {
                    Text("\(Int(remaining.rounded()))%")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
