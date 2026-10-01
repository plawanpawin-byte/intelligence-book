import SwiftUI

struct NoteView: View {
    @Bindable var note: Note
    @State private var editing = false
    @State private var showShare = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("\(note.style.title) · \(note.modelName) · \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                NoteContentView(markdown: note.markdown)

                if !note.sourceTitles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("แหล่งข้อมูล")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(note.sourceTitles, id: \.self) { title in
                            Label(title, systemImage: "doc.text")
                                .font(.footnote)
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.top, 12)
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { editing = true } label: { Label("แก้ไข", systemImage: "pencil") }
                Button { showShare = true } label: { Label("แชร์", systemImage: "square.and.arrow.up") }
            }
        }
        .sheet(isPresented: $editing) {
            NoteEditorView(note: note)
        }
        .sheet(isPresented: $showShare) {
            NavigationStack {
                ShareDestinationList(note: note) { showShare = false }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { showShare = false } }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct NoteEditorView: View {
    @Bindable var note: Note
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var preview = false

    var body: some View {
        NavigationStack {
            Group {
                if preview {
                    ScrollView { NoteContentView(markdown: draft).padding() }
                } else {
                    TextEditor(text: $draft)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                }
            }
            .navigationTitle("แก้ไขโน้ต")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    Picker("โหมด", selection: $preview) {
                        Text("Markdown").tag(false)
                        Text("ตัวอย่าง").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") {
                        note.markdown = draft
                        note.title = NoteCleaner.title(from: draft, fallback: note.title)
                        note.updatedAt = Date()
                        note.notebook?.touch()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Menu {
                        Button("สรุป (ม่วง)") { insert("\n> [!summary] สรุป\n> ") }
                        Button("นิยาม (เขียวอมฟ้า)") { insert("\n> [!definition] คำศัพท์\n> ") }
                        Button("ประเด็นสำคัญ (เหลือง)") { insert("\n> [!tip] ประเด็นสำคัญ\n> ") }
                        Button("คำถาม (ส้ม)") { insert("\n> [!question] คำถาม\n> ") }
                        Button("ข้อควรระวัง (แดง)") { insert("\n> [!warning] ข้อควรระวัง\n> ") }
                    } label: {
                        Image(systemName: "rectangle.stack.badge.plus")
                    }
                    .accessibilityLabel("แทรกกล่องสี")
                    Button { insert("==ไฮไลท์==") } label: { Image(systemName: "highlighter") }
                        .accessibilityLabel("ไฮไลท์")
                    Button { insert("**ตัวหนา**") } label: { Image(systemName: "bold") }
                        .accessibilityLabel("ตัวหนา")
                    Button { insert("\n- [ ] ") } label: { Image(systemName: "checklist") }
                        .accessibilityLabel("รายการที่ต้องทำ")
                    Button { insert("\n```\n\n```\n") } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }
                        .accessibilityLabel("โค้ด")
                    Spacer()
                }
            }
            .onAppear { draft = note.markdown }
        }
    }

    private func insert(_ snippet: String) {
        draft += snippet
    }
}
