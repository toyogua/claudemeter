import SwiftUI

@main
struct ClaudeMeterApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            UsageView()
                .environmentObject(store)
                .frame(width: 340, height: 460)
        } label: {
            // Texto + símbolo se renderizan como template — perfecto para
            // la barra de menú en claro/oscuro.
            Label(store.menuTitle, systemImage: "gauge.with.needle")
        }
        .menuBarExtraStyle(.window)
    }
}
