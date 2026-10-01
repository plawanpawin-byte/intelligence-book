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
                        Text("Sources")
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
                Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
                Button { showShare = true } label: { Label("Share", systemImage: "square.and.arrow.up") }
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
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showShare = false } }
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
            .navigationTitle("Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $preview) {
                        Text("Markdown").tag(false)
                        Text("Preview").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        note.markdown = draft
                        note.title = NoteCleaner.title(from: draft, fallback: note.title)
                        note.updatedAt = Date()
                        note.notebook?.touch()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Menu {
                        Button("Summary (yellow)") { insert("\n> [!summary] Summary\n> ") }
                        Button("Definition (teal)") { insert("\n> [!definition] Term\n> ") }
                        Button("Key point (orange)") { insert("\n> [!tip] Key point\n> ") }
                        Button("Question (pink)") { insert("\n> [!question] Question\n> ") }
                        Button("Caution (red)") { insert("\n> [!warning] Caution\n> ") }
                    } label: {
                        Image(systemName: "rectangle.stack.badge.plus")
                    }
                    .accessibilityLabel("Insert callout")
                    Button { insert("==highlight==") } label: { Image(systemName: "highlighter") }
                        .accessibilityLabel("Highlight")
                    Button { insert("**bold**") } label: { Image(systemName: "bold") }
                        .accessibilityLabel("Bold")
                    Button { insert("\n- [ ] ") } label: { Image(systemName: "checklist") }
                        .accessibilityLabel("To-do item")
                    Button { insert("\n```\n\n```\n") } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }
                        .accessibilityLabel("Code")
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
