import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Notebook.updatedAt, order: .reverse) private var notebooks: [Notebook]
    @State private var search = ""
    @State private var path: [Notebook] = []
    @State private var renaming: Notebook?
    @State private var renameText = ""

    private var filtered: [Notebook] {
        guard !search.isEmpty else { return notebooks }
        return notebooks.filter { nb in
            nb.title.localizedCaseInsensitiveContains(search)
                || nb.notes.contains { $0.title.localizedCaseInsensitiveContains(search) || $0.markdown.localizedCaseInsensitiveContains(search) }
                || nb.sources.contains { $0.title.localizedCaseInsensitiveContains(search) }
        }
    }

    @State private var request: SourceKind?
    @State private var pendingNotebook: Notebook?
    @State private var autoGenerateIDs: Set<UUID> = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if #available(iOS 26.0, *) {
                    notebookList
                        .toolbar {
                            DefaultToolbarItem(kind: .search, placement: .bottomBar)
                            ToolbarSpacer(.flexible, placement: .bottomBar)
                            ToolbarItem(placement: .bottomBar) { composeMenu }
                        }
                } else {
                    notebookList
                        .toolbar {
                            ToolbarItemGroup(placement: .bottomBar) {
                                Spacer()
                                composeMenu
                            }
                        }
                }
            }
            .navigationTitle("IntelligenceBook")
            .searchable(text: $search, prompt: "ค้นหา")
            .navigationDestination(for: Notebook.self) { notebook in
                NotebookView(notebook: notebook, autoGenerate: autoGenerateIDs.contains(notebook.uuid))
            }
            .sourceImporter(request: $request, notebook: notebookForNewSource) { source in
                if let notebook = source.notebook, path.last != notebook {
                    autoGenerateIDs.insert(notebook.uuid)
                    path.append(notebook)
                }
                pendingNotebook = nil
            }
            .alert("เปลี่ยนชื่อสมุด", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("ชื่อสมุด", text: $renameText)
                Button("ยกเลิก", role: .cancel) { renaming = nil }
                Button("บันทึก") {
                    renaming?.title = renameText.isEmpty ? "สมุดไม่มีชื่อ" : renameText
                    renaming = nil
                }
            }
        }
    }

    private var notebookList: some View {
        List {
            let pinned = filtered.filter(\.isPinned)
            if !pinned.isEmpty {
                Section("ปักหมุด") {
                    ForEach(pinned) { row($0) }
                }
            }
            if !filtered.isEmpty {
                Section(pinned.isEmpty ? "ล่าสุด" : "ทั้งหมด") {
                    ForEach(filtered.filter { !$0.isPinned }) { row($0) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if notebooks.isEmpty {
                ContentUnavailableView {
                    Label("ยังไม่มีโน้ต", systemImage: "books.vertical")
                } description: {
                    Text("แตะปุ่ม \(Image(systemName: "square.and.pencil")) เพื่อโยน PDF ลิงก์ YouTube ข้อความ หรือเสียง ให้ AI สรุปเป็นโน้ต")
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }

    /// The compose button in the bottom dock: start a notebook from any kind of source.
    private var composeMenu: some View {
        Menu {
            Section("สร้างโน้ตจาก") {
                ForEach(SourceKind.allCases) { kind in
                    Button { request = kind } label: { Label(kind.addLabel, systemImage: kind.symbol) }
                }
            }
            Button(action: createNotebook) {
                Label("สมุดเปล่า", systemImage: "book.closed")
            }
        } label: {
            Label("สร้าง", systemImage: "square.and.pencil")
        }
        .accessibilityLabel("สร้างโน้ตใหม่")
    }

    private func notebookForNewSource() -> Notebook {
        if let pendingNotebook { return pendingNotebook }
        let notebook = Notebook(title: "สมุดใหม่ \(Date().formatted(date: .abbreviated, time: .shortened))")
        modelContext.insert(notebook)
        pendingNotebook = notebook
        return notebook
    }

    private func row(_ notebook: Notebook) -> some View {
        NavigationLink(value: notebook) {
            NotebookRow(notebook: notebook)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(notebook) } label: { Label("ลบ", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button { notebook.isPinned.toggle() } label: {
                Label(notebook.isPinned ? "เลิกปักหมุด" : "ปักหมุด", systemImage: notebook.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button { notebook.isPinned.toggle() } label: {
                Label(notebook.isPinned ? "เลิกปักหมุด" : "ปักหมุด", systemImage: notebook.isPinned ? "pin.slash" : "pin")
            }
            Button {
                renameText = notebook.title
                renaming = notebook
            } label: { Label("เปลี่ยนชื่อ", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { delete(notebook) } label: { Label("ลบ", systemImage: "trash") }
        }
    }

    private func createNotebook() {
        let notebook = Notebook(title: "สมุดใหม่ \(Date().formatted(date: .abbreviated, time: .omitted))")
        modelContext.insert(notebook)
        path.append(notebook)
    }

    private func delete(_ notebook: Notebook) {
        notebook.sources.forEach { FileStore.delete($0.fileName) }
        modelContext.delete(notebook)
    }
}

struct NotebookRow: View {
    let notebook: Notebook

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notebook.notes.isEmpty ? "book.closed" : "book")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(notebook.title)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(notebook.sources.count) แหล่งข้อมูล · \(notebook.notes.count) โน้ต · \(notebook.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if notebook.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("ปักหมุด")
            }
        }
        .padding(.vertical, 2)
    }
}
