import SwiftUI
import SwiftData

struct NotebookView: View {
    @Bindable var notebook: Notebook
    var autoGenerate: Bool = false

    @Environment(\.modelContext) private var modelContext
    @State private var request: SourceKind?
    @State private var showGenerate = false
    @State private var didAutoGenerate = false
    @State private var renaming = false
    @State private var renameText = ""

    private var hasReadySource: Bool { !notebook.readySources.isEmpty }
    private var isProcessing: Bool { notebook.sources.contains { $0.status == .processing } }

    var body: some View {
        List {
            if !notebook.notes.isEmpty {
                Section("โน้ต") {
                    ForEach(notebook.sortedNotes) { note in
                        NavigationLink(value: note) { NoteRow(note: note) }
                    }
                    .onDelete { offsets in
                        let notes = notebook.sortedNotes
                        for index in offsets { modelContext.delete(notes[index]) }
                    }
                }
            }

            Section {
                ForEach(notebook.sortedSources) { source in
                    NavigationLink(value: source) { SourceRow(source: source) }
                }
                .onDelete { offsets in
                    let sources = notebook.sortedSources
                    for source in offsets.map({ sources[$0] }) {
                        SourceProcessor.shared.cancel(source)
                        FileStore.delete(source.fileName)
                        modelContext.delete(source)
                    }
                }
                addSourceMenu
            } header: {
                Text("แหล่งข้อมูล")
            } footer: {
                if notebook.sources.isEmpty {
                    Text("เพิ่ม PDF ลิงก์ YouTube ข้อความ ไฟล์เสียง หรืออัดเสียงสด ๆ")
                }
            }
        }
        .navigationTitle(notebook.title)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: Note.self) { NoteView(note: $0) }
        .navigationDestination(for: Source.self) { SourceDetailView(source: $0) }
        .safeAreaInset(edge: .bottom) {
            generateBar
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        renameText = notebook.title
                        renaming = true
                    } label: { Label("เปลี่ยนชื่อ", systemImage: "pencil") }
                    Button { notebook.isPinned.toggle() } label: {
                        Label(notebook.isPinned ? "เลิกปักหมุด" : "ปักหมุด", systemImage: notebook.isPinned ? "pin.slash" : "pin")
                    }
                } label: {
                    Label("ตัวเลือก", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("เปลี่ยนชื่อสมุด", isPresented: $renaming) {
            TextField("ชื่อสมุด", text: $renameText)
            Button("ยกเลิก", role: .cancel) {}
            Button("บันทึก") { if !renameText.isEmpty { notebook.title = renameText } }
        }
        .sourceImporter(request: $request, notebook: { notebook })
        .sheet(isPresented: $showGenerate) {
            GenerateView(notebook: notebook)
        }
        .onChange(of: hasReadySource, initial: true) { _, ready in
            guard autoGenerate, ready, !didAutoGenerate, notebook.notes.isEmpty else { return }
            didAutoGenerate = true
            showGenerate = true
        }
    }

    private var addSourceMenu: some View {
        Menu {
            ForEach(SourceKind.allCases) { kind in
                Button { request = kind } label: { Label(kind.addLabel, systemImage: kind.symbol) }
            }
        } label: {
            Label("เพิ่มแหล่งข้อมูล", systemImage: "plus.circle.fill")
        }
    }

    private var generateBar: some View {
        VStack(spacing: 6) {
            Button {
                showGenerate = true
            } label: {
                Label("สร้างโน้ตด้วย AI", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasReadySource)

            if isProcessing {
                Label("กำลังประมวลผลแหล่งข้อมูล…", systemImage: "hourglass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: note.style.symbol)
                .foregroundStyle(.purple)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.title).font(.body.weight(.medium)).lineLimit(2)
                Text("\(note.style.title) · \(note.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SourceRow: View {
    let source: Source

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: source.kind.symbol)
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(source.title).lineLimit(2)
                Text([source.kind.label, source.detail ?? source.status.label].joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(source.status == .failed ? Color.red : Color.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            switch source.status {
            case .processing: ProgressView()
            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            case .ready: EmptyView()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SourceDetailView: View {
    @Bindable var source: Source
    @State private var player = AudioPlayer()

    var body: some View {
        List {
            Section {
                LabeledContent("ชนิด", value: source.kind.label)
                LabeledContent("สถานะ") {
                    HStack(spacing: 6) {
                        if source.status == .processing { ProgressView() }
                        Text(source.detail ?? source.status.label)
                            .foregroundStyle(source.status == .failed ? Color.red : Color.secondary)
                    }
                }
                LabeledContent("เพิ่มเมื่อ", value: source.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let link = source.urlString, let url = URL(string: link) {
                    Link(destination: url) { Label("เปิดต้นฉบับ", systemImage: "safari") }
                }
                if source.status == .failed {
                    Button { SourceProcessor.shared.process(source) } label: {
                        Label("ลองอีกครั้ง", systemImage: "arrow.clockwise")
                    }
                }
            }

            if (source.kind == .audio || source.kind == .recording), source.fileURL != nil {
                Section("เสียง") {
                    PlayerControls(player: player)
                }
            }

            if !source.text.isEmpty {
                Section("ข้อความที่ดึงได้") {
                    Text(source.text.count > 30_000 ? String(source.text.prefix(30_000)) + "\n…" : source.text)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if let url = source.fileURL, source.kind == .audio || source.kind == .recording { player.load(url) } }
        .onDisappear { player.stop() }
    }
}

private struct PlayerControls: View {
    @Bindable var player: AudioPlayer

    var body: some View {
        VStack(spacing: 10) {
            Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }), in: 0...max(player.duration, 1))
            HStack {
                Text(player.currentTime.clockString).monospacedDigit()
                Spacer()
                Text("-" + max(0, player.duration - player.currentTime).clockString).monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 36) {
                Button { player.skip(-15) } label: { Image(systemName: "gobackward.15") }
                    .accessibilityLabel("ย้อน 15 วินาที")
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title)
                }
                .accessibilityLabel(player.isPlaying ? "หยุด" : "เล่น")
                Button { player.skip(15) } label: { Image(systemName: "goforward.15") }
                    .accessibilityLabel("ข้าม 15 วินาที")
                Menu {
                    Picker("ความเร็ว", selection: $player.rate) {
                        ForEach([Float(0.75), 1, 1.25, 1.5, 2], id: \.self) { Text("\($0.formatted())×").tag($0) }
                    }
                } label: {
                    Text("\(player.rate.formatted())×").font(.subheadline.monospacedDigit())
                }
            }
            .buttonStyle(.borderless)
            .font(.title3)
        }
        .padding(.vertical, 6)
    }
}
