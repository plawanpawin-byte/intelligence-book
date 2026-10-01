import SwiftUI
import SwiftData
import PDFKit

/// Home screen: a two-column card grid of notebooks (Apple Notes gallery style) with
/// a small glass search button and a glass compose button floating at the bottom.
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Notebook.updatedAt, order: .reverse) private var notebooks: [Notebook]

    @State private var search = ""
    /// NavigationPath (not [Notebook]) so notebooks can push notes and sources too.
    @State private var path = NavigationPath()
    @State private var renaming: Notebook?
    @State private var renameText = ""

    @State private var request: SourceKind?
    @State private var pendingNotebook: Notebook?
    @State private var autoGenerateIDs: Set<UUID> = []

    /// Selection mode started from the top-right menu (pin or delete several notes).
    @State private var selectAction: SelectAction?
    @State private var selection: Set<UUID> = []
    @State private var confirmDelete = false

    enum SelectAction { case pin, delete }

    private var filtered: [Notebook] {
        let base = notebooks.sorted { ($0.isPinned ? 1 : 0, $0.updatedAt) > ($1.isPinned ? 1 : 0, $1.updatedAt) }
        guard !search.isEmpty else { return base }
        return base.filter { nb in
            nb.title.localizedCaseInsensitiveContains(search)
                || nb.notes.contains { $0.title.localizedCaseInsensitiveContains(search) || $0.markdown.localizedCaseInsensitiveContains(search) }
                || nb.sources.contains { $0.title.localizedCaseInsensitiveContains(search) }
        }
    }

    private var selectedNotebooks: [Notebook] { notebooks.filter { selection.contains($0.uuid) } }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("โน้ต")
                .navigationBarTitleDisplayMode(.inline)
                .hideNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { topMenu }
                }
                .modifier(BottomDock(search: $search, trailing: { dockButton }))
                .navigationDestination(for: Notebook.self) { notebook in
                    NotebookView(notebook: notebook, autoGenerate: autoGenerateIDs.contains(notebook.uuid))
                }
                .sourceImporter(request: $request, notebook: notebookForNewSource) { source in
                    if let notebook = source.notebook, path.isEmpty {
                        autoGenerateIDs.insert(notebook.uuid)
                        path.append(notebook)
                    }
                    pendingNotebook = nil
                }
                .alert("เปลี่ยนชื่อ", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                    TextField("ชื่อโน้ต", text: $renameText)
                    Button("ยกเลิก", role: .cancel) { renaming = nil }
                    Button("บันทึก") {
                        renaming?.title = renameText.isEmpty ? "ไม่มีชื่อ" : renameText
                        renaming = nil
                    }
                }
                .confirmationDialog(
                    "ลบ \(selection.count) โน้ต?",
                    isPresented: $confirmDelete,
                    titleVisibility: .visible
                ) {
                    Button("ลบ", role: .destructive) {
                        for notebook in selectedNotebooks { delete(notebook) }
                        endSelection()
                    }
                } message: {
                    Text("โน้ตและแหล่งข้อมูลจะถูกลบออกจากเครื่อง")
                }
        }
    }

    // MARK: Grid

    private var content: some View {
        ScrollView {
            MasonryGrid(items: filtered, spacing: 14, height: NotebookCard.estimatedHeight) { notebook in
                card(notebook)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .animation(.snappy, value: filtered.map(\.uuid))
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .overlay {
            if notebooks.isEmpty {
                ContentUnavailableView {
                    Label("ยังไม่มีโน้ต", systemImage: "square.and.pencil")
                } description: {
                    Text("แตะปุ่ม \(Image(systemName: "square.and.pencil")) เพื่อโยน PDF ลิงก์ YouTube ข้อความ หรือเสียง ให้ AI สรุปเป็นโน้ต")
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }

    private func card(_ notebook: Notebook) -> some View {
        let isSelected = selection.contains(notebook.uuid)
        return Button {
            if selectAction != nil {
                if isSelected { selection.remove(notebook.uuid) } else { selection.insert(notebook.uuid) }
            } else {
                path.append(notebook)
            }
        } label: {
            NotebookCard(notebook: notebook)
                .overlay(alignment: .topTrailing) {
                    if selectAction != nil {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(isSelected ? Color(.systemBackground) : Color.secondary, isSelected ? Color.primary : Color.clear)
                            .background(Circle().fill(.ultraThinMaterial))
                            .padding(10)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .scaleEffect(selectAction != nil && isSelected ? 0.96 : 1)
        }
        .buttonStyle(CardPressStyle())
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
        .animation(.snappy, value: selectAction != nil)
        .animation(.snappy, value: isSelected)
    }

    // MARK: Menus

    /// Top-right ≡ button: pin notes, delete notes, AI model (Apple Intelligence).
    @ViewBuilder
    private var topMenu: some View {
        if selectAction != nil {
            Button("เสร็จ", action: endSelection)
                .fontWeight(.semibold)
        } else {
            Menu {
                Button { beginSelection(.pin) } label: { Label("ปักหมุดโน้ต", systemImage: "pin") }
                    .disabled(notebooks.isEmpty)
                Button(role: .destructive) { beginSelection(.delete) } label: { Label("ลบโน้ต", systemImage: "trash") }
                    .disabled(notebooks.isEmpty)
                Menu {
                    Section(DeviceProfile.isDownloaded(DeviceProfile.selected)
                            ? "ดาวน์โหลดแล้ว · ประมวลผลบนเครื่อง"
                            : "จะดาวน์โหลด \(DeviceProfile.selected.downloadSize) ตอนสร้างโน้ตครั้งแรก") {
                        Button {} label: {
                            Label(DeviceProfile.selected.displayName, systemImage: "checkmark")
                        }
                        .disabled(true)
                    }
                } label: {
                    Label("โมเดล AI", systemImage: "cpu")
                    Text(DeviceProfile.selected.displayName)
                }
                Section {
                    Text("เวอร์ชัน \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                }
            } label: {
                Label("ตัวเลือก", systemImage: "line.3.horizontal.decrease")
            }
        }
    }

    /// Bottom-right glass button: compose normally, or the pin / delete action while selecting.
    @ViewBuilder
    private var dockButton: some View {
        switch selectAction {
        case .pin:
            let allPinned = !selectedNotebooks.isEmpty && selectedNotebooks.allSatisfy(\.isPinned)
            Button {
                withAnimation(.snappy) { selectedNotebooks.forEach { $0.isPinned = !allPinned } }
                endSelection()
            } label: {
                Label(allPinned ? "เลิกปักหมุด" : "ปักหมุด", systemImage: allPinned ? "pin.slash" : "pin")
            }
            .disabled(selection.isEmpty)
        case .delete:
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("ลบ", systemImage: "trash")
            }
            .disabled(selection.isEmpty)
        case nil:
            composeMenu
        }
    }

    private var composeMenu: some View {
        Menu {
            Section("สร้างโน้ตจาก") {
                ForEach(SourceKind.allCases) { kind in
                    Button { request = kind } label: { Label(kind.addLabel, systemImage: kind.symbol) }
                }
            }
            Button(action: createNotebook) {
                Label("โน้ตเปล่า", systemImage: "book.closed")
            }
        } label: {
            Label("สร้าง", systemImage: "square.and.pencil")
        }
        .accessibilityLabel("สร้างโน้ตใหม่")
    }

    // MARK: Actions

    private func beginSelection(_ action: SelectAction) {
        selection = []
        withAnimation(.snappy) { selectAction = action }
    }

    private func endSelection() {
        withAnimation(.snappy) {
            selectAction = nil
            selection = []
        }
    }

    private func notebookForNewSource() -> Notebook {
        if let pendingNotebook { return pendingNotebook }
        let notebook = Notebook(title: "สมุดใหม่ \(Date().formatted(date: .abbreviated, time: .shortened))")
        modelContext.insert(notebook)
        pendingNotebook = notebook
        return notebook
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

// MARK: - Bottom dock

/// iOS 26: small glass search button (expands into a field) + glass trailing button, floating over content.
/// Earlier iOS: search in the navigation bar, trailing button in the bottom toolbar.
private struct BottomDock<Trailing: View>: ViewModifier {
    @Binding var search: String
    @ViewBuilder var trailing: () -> Trailing

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .searchable(text: $search, prompt: "ค้นหา")
                .searchToolbarBehavior(.minimize)
                .toolbar {
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) { trailing() }
                }
        } else {
            content
                .searchable(text: $search, prompt: "ค้นหา")
                .toolbar {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Spacer()
                        trailing()
                    }
                }
        }
    }
}

private extension View {
    @ViewBuilder
    func hideNavigationTitle() -> some View {
        if #available(iOS 18.0, *) {
            toolbar(removing: .title)
        } else {
            self
        }
    }
}

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Masonry grid

/// Two columns; each item goes into the currently shorter column (by estimated height).
struct MasonryGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    var spacing: CGFloat = 14
    let height: (Item) -> CGFloat
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        let columns = split()
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<2, id: \.self) { column in
                LazyVStack(spacing: spacing) {
                    ForEach(columns[column]) { cell($0) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func split() -> [[Item]] {
        var columns: [[Item]] = [[], []]
        var heights: [CGFloat] = [0, 0]
        for item in items {
            let target = heights[0] <= heights[1] ? 0 : 1
            columns[target].append(item)
            heights[target] += height(item) + spacing
        }
        return columns
    }
}

// MARK: - Card

struct NotebookCard: View {
    let notebook: Notebook

    private var preview: String { NotebookCard.previewText(for: notebook) }
    private var cover: CardCover? { CardCover(notebook: notebook) }

    var body: some View {
        Group {
            if let cover, preview.isEmpty {
                imageCard(cover)
            } else {
                textCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 30, style: .continuous) }

    private var header: some View {
        HStack(spacing: 4) {
            if notebook.isPinned { Image(systemName: "pin.fill").imageScale(.small) }
            if notebook.sources.contains(where: { $0.status == .processing }) {
                ProgressView().controlSize(.mini)
            }
            Text(NotebookCard.dateLabel(notebook.updatedAt))
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private var title: some View {
        Text(notebook.title)
            .font(.title3.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(4)
            .multilineTextAlignment(.leading)
    }

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            title
            if !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(cover == nil ? 5 : 3)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 2)
            }
            if let cover {
                CoverImage(cover: cover)
                    .frame(height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.top, 8)
                    .padding(.horizontal, -8)
                    .padding(.bottom, -8)
            }
        }
        .padding(18)
    }

    private func imageCard(_ cover: CardCover) -> some View {
        CoverImage(cover: cover)
            .frame(height: 230)
            .overlay {
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NotebookCard.dateLabel(notebook.updatedAt))
                        .font(.footnote.weight(.medium))
                        .opacity(0.85)
                    Text(notebook.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(.white)
                .padding(18)
            }
    }

    // MARK: Helpers

    static func estimatedHeight(_ notebook: Notebook) -> CGFloat {
        let hasCover = CardCover(notebook: notebook) != nil
        let preview = previewText(for: notebook)
        if hasCover && preview.isEmpty { return 230 }
        let titleLines = min(4, max(1, CGFloat(notebook.title.count) / 14))
        var height: CGFloat = 36 + 22 + titleLines * 26
        if !preview.isEmpty { height += min(CGFloat(preview.count) / 22, hasCover ? 3 : 5) * 20 }
        if hasCover { height += 140 }
        return height
    }

    /// First readable sentences of the newest note (skipping the title), else of the first source.
    static func previewText(for notebook: Notebook) -> String {
        if let note = notebook.sortedNotes.first {
            var parts: [String] = []
            func collect(_ blocks: [NoteBlock]) {
                for block in blocks where parts.joined().count < 220 {
                    switch block.kind {
                    case .paragraph(let t), .bullet(let t, _), .numbered(_, let t, _), .quote(let t):
                        parts.append(InlineMarkdown.plain(t))
                    case .callout(_, _, let children):
                        collect(children)
                    default: break
                    }
                }
            }
            collect(NoteParser.parse(note.markdown))
            let text = parts.joined(separator: " ")
            if !text.isEmpty { return String(text.prefix(240)) }
        }
        if let source = notebook.readySources.first {
            return String(source.text.prefix(240))
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    static func dateLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "เมื่อวาน" }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Cover images

enum CardCover: Equatable {
    case remote(URL)
    case pdf(URL)

    init?(notebook: Notebook) {
        let sources = notebook.sortedSources.reversed()
        if let remote = sources.lazy.compactMap({ $0.imageURL }).compactMap({ URL(string: $0) }).first {
            self = .remote(remote)
        } else if let pdf = sources.first(where: { $0.kind == .pdf && $0.status == .ready }), let url = pdf.fileURL {
            self = .pdf(url)
        } else {
            return nil
        }
    }
}

struct CoverImage: View {
    let cover: CardCover
    @State private var pdfImage: UIImage?

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                switch cover {
                case .remote(let url):
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else if phase.error != nil {
                            Image(systemName: "photo").foregroundStyle(.tertiary)
                        }
                    }
                case .pdf:
                    if let pdfImage {
                        Image(uiImage: pdfImage).resizable().scaledToFill()
                    } else {
                        Image(systemName: "doc.richtext").font(.title).foregroundStyle(.tertiary)
                    }
                }
            }
            .clipped()
            .task(id: cover) {
                if case .pdf(let url) = cover { pdfImage = await PDFThumbnails.image(for: url) }
            }
    }
}

@MainActor
enum PDFThumbnails {
    private static let cache = NSCache<NSURL, UIImage>()

    static func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: 480, height: 640), for: .cropBox)
        }.value
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}
