import SwiftUI

struct SettingsView: View {
    @AppStorage(DeviceProfile.preferenceKey) private var preferenceRaw = ModelPreference.auto.rawValue
    @AppStorage("outputLanguage") private var languageRaw = OutputLanguage.auto.rawValue
    @AppStorage(SpeechLocale.storageKey) private var speechRaw = SpeechLocale.thai.rawValue
    @AppStorage("obsidianVault") private var obsidianVault = ""
    @AppStorage("askShareAfterGenerate") private var askShare = true

    @State private var llm = LLMService.shared
    @State private var refresh = 0
    @State private var confirmDelete: LlamaVariant?
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("เครื่องนี้", value: DeviceProfile.deviceSummary)
                    LabeledContent("แนะนำ", value: DeviceProfile.recommended.displayName)
                    Picker("ขนาดโมเดล", selection: $preferenceRaw) {
                        ForEach(ModelPreference.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .onChange(of: preferenceRaw) { llm.unload() }
                    LabeledContent("ใช้งานอยู่", value: DeviceProfile.selected.displayName)
                    LabeledContent("สถานะ") {
                        Text(llm.statusText)
                            .foregroundStyle(.secondary)
                    }
                    if case .downloading(let p) = llm.state {
                        ProgressView(value: p)
                    }
                    Button {
                        downloadTask = Task {
                            _ = try? await llm.ensureLoaded()
                            refresh += 1
                        }
                    } label: {
                        Label(DeviceProfile.isDownloaded(DeviceProfile.selected) ? "โหลดโมเดลเข้าหน่วยความจำ" : "ดาวน์โหลดตอนนี้ (\(DeviceProfile.selected.downloadSize))",
                              systemImage: "arrow.down.circle")
                    }
                    .disabled(isBusy)
                } header: {
                    Text("AI บนเครื่อง — Llama 3.2")
                } footer: {
                    Text("“อัตโนมัติ” เลือก 3B เมื่อเครื่องมีแรม 8 GB ขึ้นไป (iPhone 15 Pro ขึ้นไป, iPad ชิป M) และ 1B สำหรับเครื่องที่แรมน้อยกว่า ทุกอย่างประมวลผลบนเครื่องด้วย MLX")
                }

                Section("โมเดลที่ดาวน์โหลดแล้ว") {
                    ForEach(LlamaVariant.allCases) { variant in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(variant.displayName)
                                Text(variant.downloadSize).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if DeviceProfile.isDownloaded(variant) {
                                Button("ลบ", role: .destructive) { confirmDelete = variant }
                                    .buttonStyle(.borderless)
                            } else {
                                Text("ยังไม่ดาวน์โหลด").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .id("\(variant.rawValue)-\(refresh)")
                    }
                }

                Section {
                    Picker("ภาษาของโน้ต", selection: $languageRaw) {
                        ForEach(OutputLanguage.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("ภาษาเสียงพูด", selection: $speechRaw) {
                        ForEach(SpeechLocale.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } header: {
                    Text("ภาษา")
                } footer: {
                    Text("ภาษาเสียงพูดใช้กับการถอดเสียงจากไฟล์เสียงและการอัดสด")
                }

                Section {
                    Toggle("ถามปลายทางแชร์หลังสร้างโน้ต", isOn: $askShare)
                    TextField("ชื่อ Obsidian vault (เว้นว่าง = vault ล่าสุด)", text: $obsidianVault)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("แชร์และส่งออก")
                } footer: {
                    Text("เช่น “intelligence book” โน้ตจะถูกสร้างเป็นไฟล์ Markdown ใน vault นั้น พร้อม callout สีที่ Obsidian แสดงได้")
                }

                Section {
                    LabeledContent("เวอร์ชัน", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Link(destination: URL(string: "https://github.com/plawanpawin-byte/intelligence-book")!) {
                        Label("ซอร์สโค้ดบน GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } header: {
                    Text("เกี่ยวกับ")
                } footer: {
                    Text("Llama 3.2 อยู่ภายใต้ Llama 3.2 Community License ของ Meta")
                }
            }
            .navigationTitle("ตั้งค่า")
            .confirmationDialog(
                "ลบ \(confirmDelete?.displayName ?? "")?",
                isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("ลบโมเดล", role: .destructive) {
                    if let variant = confirmDelete {
                        if llm.loadedVariant == variant { llm.unload() }
                        DeviceProfile.deleteDownload(variant)
                        refresh += 1
                    }
                }
            } message: {
                Text("ต้องดาวน์โหลดใหม่ก่อนใช้งานครั้งถัดไป")
            }
        }
    }

    private var isBusy: Bool {
        switch llm.state {
        case .downloading, .loading: true
        default: false
        }
    }
}
