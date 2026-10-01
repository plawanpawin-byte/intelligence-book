import SwiftUI
import SwiftData
import UniformTypeIdentifiers

extension View {
    /// Handles every "add source" flow: file pickers, link/text entry and live recording.
    func sourceImporter(
        request: Binding<SourceKind?>,
        notebook: @escaping () -> Notebook,
        onAdded: @escaping (Source) -> Void = { _ in }
    ) -> some View {
        modifier(SourceImportModifier(request: request, notebook: notebook, onAdded: onAdded))
    }
}

private struct SourceImportModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Binding var request: SourceKind?
    let notebook: () -> Notebook
    let onAdded: (Source) -> Void

    @State private var importError: String?

    private var fileKind: SourceKind? {
        request == .pdf || request == .audio ? request : nil
    }

    private var sheetKind: Binding<SourceKind?> {
        Binding(
            get: { [.web, .youtube, .text, .recording].contains(request) ? request : nil },
            set: { if $0 == nil { request = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: Binding(get: { fileKind != nil }, set: { if !$0 { request = nil } }),
                allowedContentTypes: fileKind == .audio ? [.audio, .mpeg4Audio, .mp3, .wav] : [.pdf],
                allowsMultipleSelection: true
            ) { result in
                handleFiles(result)
            }
            .sheet(item: sheetKind) { kind in
                switch kind {
                case .web, .youtube:
                    LinkEntrySheet(kind: kind) { link in
                        add(Source(kind: kind, title: link, urlString: link))
                    }
                case .text:
                    TextEntrySheet { title, text in
                        add(Source(kind: .text, title: title, text: text))
                    }
                case .recording:
                    RecorderSheet { fileName, duration in
                        let title = "บันทึกเสียง \(Date().formatted(date: .abbreviated, time: .shortened)) (\(duration.clockString))"
                        add(Source(kind: .recording, title: title, fileName: fileName))
                    }
                default:
                    EmptyView()
                }
            }
            .alert("นำเข้าไม่สำเร็จ", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("ตกลง", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
    }

    private func handleFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            for url in urls {
                do {
                    let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) ?? false
                    let name = try FileStore.importFile(url)
                    let title = url.deletingPathExtension().lastPathComponent
                    add(Source(kind: isPDF ? .pdf : .audio, title: title, fileName: name))
                } catch {
                    importError = error.localizedDescription
                }
            }
        }
    }

    private func add(_ source: Source) {
        let target = notebook()
        modelContext.insert(source)
        source.notebook = target
        target.touch()
        if source.kind == .text {
            source.status = .ready
            source.detail = "\(source.text.count.formatted()) ตัวอักษร"
        } else {
            SourceProcessor.shared.process(source)
        }
        onAdded(source)
    }
}

// MARK: - Link entry

struct LinkEntrySheet: View {
    let kind: SourceKind
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @FocusState private var focused: Bool

    private var isValid: Bool {
        guard WebExtractor.normalize(link) != nil else { return false }
        return kind != .youtube || YouTubeTranscript.videoID(from: link) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(kind == .youtube ? "https://youtu.be/…" : "https://", text: $link)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(submit)
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first { link = first.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                } footer: {
                    Text(kind == .youtube
                         ? "ใช้คำบรรยายของวิดีโอ (ไทยหรืออังกฤษ) ถ้าวิดีโอไม่มีคำบรรยาย ให้คัดลอก transcript มาวางเป็นข้อความแทน"
                         : "ดึงเฉพาะเนื้อหาที่อ่านได้จากหน้าเว็บ หน้าที่ต้องล็อกอินหรือมี paywall อาจดึงไม่ได้")
                }
            }
            .navigationTitle(kind.addLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("เพิ่ม", action: submit).disabled(!isValid) }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        guard isValid else { return }
        onAdd(link.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

// MARK: - Text entry

struct TextEntrySheet: View {
    let onAdd: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ชื่อ (ไม่บังคับ)", text: $title)
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 260)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("วางหรือพิมพ์ข้อความที่นี่")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    PasteButton(payloadType: String.self) { strings in
                        text += strings.joined(separator: "\n")
                    }
                } footer: {
                    Text("\(text.count.formatted()) ตัวอักษร")
                }
            }
            .navigationTitle("วางข้อความ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("เพิ่ม") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let name = title.isEmpty ? String(trimmed.prefix(40)) : title
                        onAdd(name, trimmed)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
                }
            }
        }
    }
}

// MARK: - Recorder

struct RecorderSheet: View {
    let onFinish: (String, TimeInterval) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = AudioRecorder()
    @State private var permissionDenied = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                LevelMeter(levels: recorder.levels, active: recorder.state == .recording)
                    .frame(height: 72)
                    .padding(.horizontal)
                    .accessibilityHidden(true)

                Text(recorder.elapsed.clockString)
                    .font(.system(size: 64, weight: .light, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .accessibilityLabel("เวลาที่อัด \(recorder.elapsed.clockString)")

                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 56) {
                    Button {
                        recorder.state == .paused ? recorder.resume() : recorder.pause()
                    } label: {
                        Image(systemName: recorder.state == .paused ? "play.fill" : "pause.fill")
                            .font(.title2)
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .disabled(recorder.state == .idle)
                    .accessibilityLabel(recorder.state == .paused ? "อัดต่อ" : "หยุดชั่วคราว")

                    RecordButton(isRecording: recorder.state != .idle) {
                        if recorder.state == .idle { start() } else { finish() }
                    }

                    Color.clear.frame(width: 56, height: 56)
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("อัดเสียง")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") {
                        recorder.discard()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("เสร็จ", action: finish).disabled(recorder.state == .idle)
                }
            }
            .alert("ไม่ได้รับอนุญาตใช้ไมโครโฟน", isPresented: $permissionDenied) {
                Button("เปิดการตั้งค่า") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("ปิด", role: .cancel) {}
            } message: {
                Text("อนุญาตไมโครโฟนให้ IntelligenceBook ในการตั้งค่าเพื่ออัดเสียง")
            }
        }
        .interactiveDismissDisabled(recorder.state != .idle)
    }

    private var statusText: String {
        if let errorText { return errorText }
        switch recorder.state {
        case .idle: return "แตะปุ่มสีแดงเพื่อเริ่มอัด"
        case .recording: return "กำลังอัด…"
        case .paused: return "หยุดชั่วคราว"
        }
    }

    private func start() {
        Task {
            guard await recorder.requestPermission() else {
                permissionDenied = true
                return
            }
            do {
                try recorder.start()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func finish() {
        let duration = recorder.elapsed
        guard let name = recorder.stop() else { return }
        onFinish(name, duration)
        dismiss()
    }
}

private struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.secondary.opacity(0.5), lineWidth: 4)
                    .frame(width: 84, height: 84)
                RoundedRectangle(cornerRadius: isRecording ? 8 : 34, style: .continuous)
                    .fill(.red)
                    .frame(width: isRecording ? 34 : 68, height: isRecording ? 34 : 68)
            }
            .animation(.spring(duration: 0.3), value: isRecording)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "หยุดและบันทึก" : "เริ่มอัดเสียง")
        .sensoryFeedback(.impact, trigger: isRecording)
    }
}

private struct LevelMeter: View {
    let levels: [Float]
    let active: Bool

    var body: some View {
        GeometryReader { proxy in
            let count = levels.count
            let spacing: CGFloat = 3
            let width = max(1, (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(active ? Color.red : Color.secondary.opacity(0.4))
                        .frame(width: width, height: max(4, proxy.size.height * CGFloat(level)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
