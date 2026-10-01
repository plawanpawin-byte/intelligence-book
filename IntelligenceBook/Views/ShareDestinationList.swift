import SwiftUI

/// "Where do you want to send this note?" — shown right after a note is saved and from the note's share button.
struct ShareDestinationList: View {
    let note: Note
    var onFinished: () -> Void = {}

    @AppStorage("obsidianVault") private var obsidianVault = ""
    @Environment(\.openURL) private var openURL
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    Text("Note saved")
                        .font(.title3.bold())
                    Text("Where do you want to share “\(note.title)”?")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }

            Section {
                destination("Obsidian", subtitle: "New note in your vault (Markdown + coloured callouts)", symbol: "diamond.fill", tint: .purple) {
                    openInObsidian()
                }
                destination("Canva", subtitle: "Sends a colour PDF — pick Canva in the share sheet", symbol: "paintpalette.fill", tint: .cyan) {
                    sharePDF()
                }
                destination("Notes", subtitle: "Sends the text with the PDF attached", symbol: "note.text", tint: .yellow) {
                    shareForNotes()
                }
            } header: {
                Text("Share to")
            }

            Section {
                destination("Markdown (.md)", subtitle: "Obsidian, Files, Bear, Notion", symbol: "doc.plaintext", tint: .gray) {
                    shareMarkdown()
                }
                destination("PDF", subtitle: "Print, email or AirDrop", symbol: "doc.richtext", tint: .red) {
                    sharePDF()
                }
                destination("Text", subtitle: "Copy or send in a chat", symbol: "text.quote", tint: .blue) {
                    SharePresenter.present([NoteExporter.plainText(for: note)])
                }
            } header: {
                Text("Export with the iOS share sheet")
            }

            Section {
                Button {
                    onFinished()
                } label: {
                    Label("Keep in the app only", systemImage: "tray.and.arrow.down")
                }
            }
        }
        .navigationTitle("Share note")
        .alert("Couldn’t share", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private func destination(_ title: String, subtitle: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityHint(subtitle)
    }

    private func openInObsidian() {
        guard let url = NoteExporter.obsidianURL(for: note, vault: obsidianVault) else {
            shareMarkdown()
            return
        }
        openURL(url) { accepted in
            // Obsidian not installed or link too long: fall back to sharing the .md file.
            if !accepted { shareMarkdown() }
        }
    }

    private func shareMarkdown() {
        do {
            SharePresenter.present([try NoteExporter.markdownFile(for: note)])
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func sharePDF() {
        do {
            SharePresenter.present([try NoteExporter.pdfFile(for: note)])
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func shareForNotes() {
        do {
            let pdf = try NoteExporter.pdfFile(for: note)
            SharePresenter.present([NoteExporter.plainText(for: note), pdf])
        } catch {
            errorText = error.localizedDescription
        }
    }
}
