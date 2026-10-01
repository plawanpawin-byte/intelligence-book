import SwiftUI
import SwiftData

struct GenerateView: View {
    let notebook: Notebook

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("outputLanguage") private var languageRaw = OutputLanguage.auto.rawValue
    @AppStorage("askShareAfterGenerate") private var askShare = true

    @State private var style: NoteStyle = .summary
    @State private var selected: Set<UUID> = []
    @State private var job = GenerationJob()
    @State private var task: Task<Void, Never>?
    @State private var stage: Stage = .configure
    @State private var savedNote: Note?

    enum Stage { case configure, running, review, share }

    private var language: OutputLanguage { OutputLanguage(rawValue: languageRaw) ?? .auto }
    private var chosenSources: [Source] { notebook.readySources.filter { selected.contains($0.uuid) } }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .configure: configureView
                case .running: runningView
                case .review: reviewView
                case .share:
                    if let savedNote {
                        ShareDestinationList(note: savedNote) { dismiss() }
                    }
                }
            }
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(stage == .running)
        .onAppear {
            if selected.isEmpty { selected = Set(notebook.readySources.map(\.uuid)) }
        }
        .onDisappear { task?.cancel() }
    }

    // MARK: Configure

    private var configureView: some View {
        Form {
            Section("รูปแบบโน้ต") {
                Picker("รูปแบบโน้ต", selection: $style) {
                    ForEach(NoteStyle.allCases) { style in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.title)
                                Text(style.subtitle).font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: style.symbol)
                        }
                        .tag(style)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section {
                ForEach(notebook.readySources) { source in
                    Toggle(isOn: Binding(
                        get: { selected.contains(source.uuid) },
                        set: { if $0 { selected.insert(source.uuid) } else { selected.remove(source.uuid) } }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.title).lineLimit(2)
                                Text(source.detail ?? "").font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: source.kind.symbol).foregroundStyle(.blue)
                        }
                    }
                }
            } header: {
                Text("แหล่งข้อมูลที่ใช้")
            } footer: {
                Text("AI จะสรุปจากแหล่งที่เลือกเท่านั้น และไม่เพิ่มข้อเท็จจริงจากภายนอก")
            }

            Section {
                Picker("ภาษาโน้ต", selection: $languageRaw) {
                    ForEach(OutputLanguage.allCases) { Text($0.label).tag($0.rawValue) }
                }
                LabeledContent("โมเดล", value: DeviceProfile.selected.displayName)
            } header: {
                Text("AI บนเครื่อง")
            } footer: {
                if !DeviceProfile.isDownloaded(DeviceProfile.selected) {
                    Text("ครั้งแรกจะดาวน์โหลด \(DeviceProfile.selected.displayName) \(DeviceProfile.selected.downloadSize) (แนะนำให้ใช้ Wi-Fi) หลังจากนั้นทำงานออฟไลน์ได้")
                } else {
                    Text("ประมวลผลบนเครื่องทั้งหมด ข้อมูลไม่ถูกส่งออกไปไหน")
                }
            }
        }
        .navigationTitle("สร้างโน้ตด้วย AI")
    }

    // MARK: Running

    private var runningView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    if case .loadingModel = job.phase, case .downloading(let p) = LLMService.shared.state {
                        ProgressView(value: p)
                    } else {
                        ProgressView(value: job.progress)
                    }
                    Label(job.phaseText, systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                .padding(.bottom, 4)

                if case .writing = job.phase {
                    NoteContentView(markdown: job.output)
                } else if !job.output.isEmpty {
                    Text(job.output)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(12)
                }
            }
            .padding()
            .animation(.default, value: job.phaseText)
        }
        .navigationTitle(style.title)
    }

    // MARK: Review

    private var reviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("สร้างโดย AI (\(DeviceProfile.selected.displayName)) — ตรวจทานก่อนนำไปใช้", systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.purple)
                NoteContentView(markdown: job.output)
            }
            .padding()
        }
        .navigationTitle("ตรวจทานโน้ต")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            switch stage {
            case .configure:
                Button("ยกเลิก") { dismiss() }
            case .running:
                Button("หยุด", role: .cancel) {
                    task?.cancel()
                    stage = .configure
                }
            case .review:
                Button("ทิ้ง", role: .destructive) { dismiss() }
            case .share:
                EmptyView()
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if stage == .review {
                Button("สร้างใหม่", systemImage: "arrow.clockwise", action: start)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            switch stage {
            case .configure:
                Button("สร้าง", action: start).disabled(selected.isEmpty)
            case .running:
                EmptyView()
            case .review:
                Button("บันทึก", action: save)
            case .share:
                Button("เสร็จ") { dismiss() }
            }
        }
    }

    private func start() {
        let inputs = chosenSources.map { GenerationJob.SourceInput(title: $0.title, kind: $0.kind, text: $0.text) }
        stage = .running
        task?.cancel()
        task = Task {
            await job.run(sources: inputs, style: style, language: language)
            guard !Task.isCancelled else { return }
            if case .done = job.phase {
                stage = .review
            } else if case .failed = job.phase {
                stage = .configure
            }
        }
    }

    private func save() {
        let markdown = job.output
        let note = Note(
            title: NoteCleaner.title(from: markdown, fallback: "\(style.title) — \(notebook.title)"),
            markdown: markdown,
            style: style,
            modelName: DeviceProfile.selected.displayName,
            sourceTitles: chosenSources.map(\.title)
        )
        modelContext.insert(note)
        note.notebook = notebook
        notebook.touch()
        if notebook.notes.count == 1, notebook.title.hasPrefix("สมุดใหม่") {
            notebook.title = note.title
        }
        savedNote = note
        if askShare {
            stage = .share
        } else {
            dismiss()
        }
    }
}
