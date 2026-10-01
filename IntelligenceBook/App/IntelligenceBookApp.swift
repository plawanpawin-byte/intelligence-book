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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tab: AppTab = .library

    enum AppTab: Hashable { case library, create, settings }

    var body: some View {
        TabView(selection: $tab) {
            LibraryView()
                .tabItem { Label("คลังโน้ต", systemImage: "books.vertical") }
                .tag(AppTab.library)

            CreateView()
                .tabItem { Label("สร้าง", systemImage: "plus.circle") }
                .tag(AppTab.create)

            SettingsView()
                .tabItem { Label("ตั้งค่า", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .task {
            SourceProcessor.shared.resumePending(in: modelContext)
        }
    }
}
