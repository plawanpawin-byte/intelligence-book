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
    @State private var importStatus: String?

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
                case .web:
                    LinkEntrySheet(kind: kind) { link in
                        add(Source(kind: kind, title: link, urlString: link))
                    }
                case .text:
                    TextEntrySheet { title, text in
                        add(Source(kind: .text, title: title, text: text))
                    }
                case .recording:
                    RecorderSheet { fileName, duration, transcript in
                        let title = "Recording \(Date().formatted(date: .abbreviated, time: .shortened)) (\(duration.clockString))"
                        add(Source(kind: .recording, title: title, text: transcript ?? "", fileName: fileName))
                    }
                }
            }
            .overlay(alignment: .top) {
                if let importStatus {
                    Label(importStatus, systemImage: "icloud.and.arrow.down")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .alert("Import failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
    }

    private func handleFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = AppError.describe(error, during: "Choosing the file")
        case .success(let urls):
            Task { @MainActor in
                for url in urls {
                    importStatus = "Importing \(url.lastPathComponent)…"
                    do {
                        let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) ?? false
                        let name = try await FileStore.importPicked(url) { status in importStatus = status }
                        let title = url.deletingPathExtension().lastPathComponent
                        add(Source(kind: isPDF ? .pdf : .audio, title: title, fileName: name))
                    } catch {
                        importError = AppError.describe(error, during: "Importing \(url.lastPathComponent)")
                    }
                }
                importStatus = nil
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
            source.detail = "\(source.text.count.formatted()) characters"
        } else {
            SourceProcessor.shared.process(source)
        }
        onAdded(source)
    }
}

// MARK: - Document picker

/// UIDocumentPicker that opens files in place (security-scoped). We download cloud files ourselves
/// (FileStore.importPicked), waiting and retrying — copy mode fails outright with
/// NSFileProviderErrorDomain -5009 whenever iCloud can't deliver the file immediately.
struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
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
        WebExtractor.normalize(link) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://", text: $link)
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
                        Text("Only the readable text of the page is used. Pages behind a login or paywall may not work.")
                    }
                }
            }
            .navigationTitle(kind.addLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add", action: submit).disabled(!isValid) }
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
                    TextField("Title (optional)", text: $title)
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 260)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Paste or type text here")
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
                    Text("\(text.count.formatted()) characters")
                }
            }
            .navigationTitle("Paste text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
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
                    .accessibilityLabel("Recorded time \(recorder.elapsed.clockString)")

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
                    .accessibilityLabel(recorder.state == .paused ? "Resume" : "Pause")

                    RecordButton(isRecording: recorder.state != .idle) {
                        if recorder.state == .idle { start() } else { finish() }
                    }

                    Menu {
                        Picker("Spoken language", selection: $speechLocale) {
                            ForEach(SpeechLocale.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                    } label: {
                        Text(SpeechLocale(rawValue: speechLocale)?.shortLabel ?? "TH")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .disabled(recorder.state != .idle)
                    .accessibilityLabel("Spoken language")
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.discard()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: finish).disabled(recorder.state == .idle)
                }
            }
            .alert("Microphone access is off", isPresented: $permissionDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("Close", role: .cancel) {}
            } message: {
                Text("Allow IntelligenceBook to use the microphone in Settings to record.")
            }
        }
        .interactiveDismissDisabled(recorder.state != .idle)
    }

    private var statusText: String {
        if let errorText { return errorText }
        switch recorder.state {
        case .idle: return "Tap the red button to start recording"
        case .recording:
            if finishing { return "Collecting the transcript…" }
            return recorder.transcribedPieces > 0
                ? "Recording… \(recorder.transcribedPieces) parts transcribed · you can lock the screen"
                : "Recording… you can lock the screen"
        case .paused: return "Paused"
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
        .accessibilityLabel(isRecording ? "Stop and save" : "Start recording")
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
