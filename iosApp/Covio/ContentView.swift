import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.isReady {
                TabView {
                    SendView()
                        .tabItem { Label("Send", systemImage: "paperplane") }
                    ReceiveView()
                        .tabItem { Label("Receive", systemImage: "tray.and.arrow.down") }
                    DevicesView()
                        .tabItem { Label("Devices", systemImage: "laptopcomputer.and.iphone") }
                }
            } else if let message = model.errorMessage {
                ContentUnavailableView {
                    Label("Covio could not start", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") {
                        model.errorMessage = nil
                        Task { await model.bootstrap() }
                    }
                }
            } else {
                ProgressView("Starting Covio…")
            }
        }
        .alert(
            "Covio",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
