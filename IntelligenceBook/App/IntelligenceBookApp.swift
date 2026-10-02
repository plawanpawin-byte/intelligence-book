import SwiftUI
import SwiftData

@main
struct IntelligenceBookApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Notebook.self, Source.self, Note.self])
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        LibraryView()
            .tint(.accentColor)
            .task {
                SourceProcessor.shared.resumePending(in: modelContext)
                await Task.detached(priority: .background) { DeviceProfile.removeUnusedDownloads() }.value
            }
    }
}
