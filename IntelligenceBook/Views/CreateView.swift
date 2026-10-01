import SwiftUI
import SwiftData

/// "Create" tab: start a new notebook straight from a source.
struct CreateView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var request: SourceKind?
    @State private var path: [Notebook] = []
    @State private var target: Notebook?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(SourceKind.allCases) { kind in
                        Button {
                            request = kind
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.addLabel).foregroundStyle(.primary)
                                    Text(hint(for: kind)).font(.footnote).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: kind.symbol).foregroundStyle(kind == .recording ? Color.red : Color.accentColor)
                            }
                        }
                    }
                } header: {
                    Text("เริ่มจากแหล่งข้อมูล")
                } footer: {
                    Text("ระบบจะสร้างสมุดใหม่ ดึงเนื้อหา แล้วให้ Llama 3.2 บนเครื่องสรุปเป็นโน้ตพร้อมไฮไลท์")
                }
            }
            .navigationTitle("สร้างโน้ต")
            .navigationDestination(for: Notebook.self) { NotebookView(notebook: $0, autoGenerate: true) }
            .sourceImporter(request: $request, notebook: makeNotebook) { source in
                if let nb = source.notebook, path.last != nb { path.append(nb) }
                target = nil
            }
        }
    }

    private func makeNotebook() -> Notebook {
        if let target { return target }
        let notebook = Notebook(title: "สมุดใหม่ \(Date().formatted(date: .abbreviated, time: .shortened))")
        modelContext.insert(notebook)
        target = notebook
        return notebook
    }

    private func hint(for kind: SourceKind) -> String {
        switch kind {
        case .pdf: "เอกสาร หนังสือ สไลด์ (รองรับไฟล์สแกนด้วย OCR)"
        case .web: "บทความหรือหน้าเว็บ"
        case .youtube: "ใช้คำบรรยาย (subtitle) ของวิดีโอ"
        case .text: "คัดลอกข้อความมาวาง"
        case .audio: "m4a, mp3, wav — ถอดเสียงเป็นข้อความ"
        case .recording: "อัดเลกเชอร์หรือประชุมสด ๆ"
        }
    }
}
