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

    private var sheetKind: Binding<SourceKind?> {
        Binding(
            get: { request },
            set: { if $0 == nil { request = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: sheetKind) { kind in
                switch kind {
                case .pdf, .audio:
                    DocumentPicker(types: kind == .audio ? [.audio, .mpeg4Audio, .mp3, .wav] : [.pdf]) { urls in
                        handleFiles(.success(urls))
                    }
                    .ignoresSafeArea()
                case .web, .youtube:
                    LinkEntrySheet(kind: kind) { link in
                        add(Source(kind: kind, title: link, urlString: link))
                    }
                case .text:
                    TextEntrySheet { title, text in
                        add(Source(kind: .text, title: title, text: text))
                    }
                case .recording:
                    RecorderSheet { fileName, duration, transcript in
                        let title = "บันทึกเสียง \(Date().formatted(date: .abbreviated, time: .shortened)) (\(duration.clockString))"
                        add(Source(kind: .recording, title: title, text: transcript ?? "", fileName: fileName))
                    }
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

// MARK: - Document picker

/// UIDocumentPicker in copy mode: iOS downloads the file from iCloud / Drive / other providers and hands
/// over a local copy, which avoids NSFileProviderErrorDomain errors from not-yet-downloaded files.
struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
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
                    if kind == .web {
                        Text("ดึงเฉพาะเนื้อหาที่อ่านได้จากหน้าเว็บ หน้าที่ต้องล็อกอินหรือมี paywall อาจดึงไม่ได้")
                    }
                }
                if kind == .youtube {
                    GeminiKeySection()
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
        .presentationDetents(kind == .youtube ? [.large] : [.medium])
    }

    private func submit() {
        guard isValid else { return }
        onAdd(link.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

// MARK: - Gemini key

/// Lets the user paste a Gemini API key; YouTube links are then transcribed by Gemini.
struct GeminiKeySection: View {
    @State private var hasKey = GeminiKey.isSet
    @State private var draft = ""

    var body: some View {
        Section {
            if hasKey {
                Label("ใช้ Gemini ถอดคำพูดจาก YouTube", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("ลบ API key", role: .destructive) {
                    GeminiKey.remove()
                    hasKey = false
                }
            } else {
                SecureField("วาง Gemini API key", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("บันทึก key") {
                    GeminiKey.save(draft)
                    draft = ""
                    hasKey = GeminiKey.isSet
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).count < 20)
                Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                    Label("รับ API key ฟรีจาก Google AI Studio", systemImage: "key")
                }
            }
        } header: {
            Text("Gemini (ถอดคำพูดจาก YouTube)")
        } footer: {
            Text("YouTube ไม่ส่งคำบรรยายให้แอปโดยตรงแล้ว แอปจึงส่งลิงก์วิดีโอให้ Google Gemini ถอดคำพูดแทน (ส่งเฉพาะลิงก์ ไม่ส่งข้อมูลอื่น) จากนั้นสรุปโน้ตด้วยโมเดลในเครื่องตามเดิม key เก็บไว้ใน Keychain ของเครื่อง")
        }
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
    let onFinish: (String, TimeInterval, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = AudioRecorder()
    @State private var finishing = false
    @AppStorage(SpeechLocale.storageKey) private var speechLocale = SpeechLocale.thai.rawValue
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

                    Menu {
                        Picker("ภาษาที่พูด", selection: $speechLocale) {
                            ForEach(SpeechLocale.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                    } label: {
                        Text(SpeechLocale(rawValue: speechLocale)?.shortLabel ?? "ไทย")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .disabled(recorder.state != .idle)
                    .accessibilityLabel("ภาษาที่พูด")
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
        case .recording:
            if finishing { return "กำลังเก็บข้อความที่ถอดไว้…" }
            return recorder.transcribedPieces > 0
                ? "กำลังอัด… ถอดเสียงไปแล้ว \(recorder.transcribedPieces) ช่วง · ล็อกจอได้"
                : "กำลังอัด… ล็อกจอได้ เสียงยังอัดต่อ"
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
                try await recorder.start()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func finish() {
        let duration = recorder.elapsed
        finishing = true
        Task {
            guard let result = await recorder.stop() else { finishing = false; return }
            onFinish(result.fileName, duration, result.transcript)
            dismiss()
        }
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
