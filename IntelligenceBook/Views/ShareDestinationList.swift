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
                    Text("บันทึกโน้ตแล้ว")
                        .font(.title3.bold())
                    Text("จะแชร์ “\(note.title)” ไปที่ไหน?")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }

            Section {
                destination("Obsidian", subtitle: "สร้างโน้ตใหม่ใน vault (Markdown + callout สี)", symbol: "diamond.fill", tint: .purple) {
                    openInObsidian()
                }
                destination("Canva", subtitle: "ส่งเป็น PDF สี — เลือก Canva ในแผ่นแชร์", symbol: "paintpalette.fill", tint: .cyan) {
                    sharePDF()
                }
                destination("โน้ต (Notes)", subtitle: "ส่งเป็นข้อความพร้อม PDF แนบ", symbol: "note.text", tint: .yellow) {
                    shareForNotes()
                }
            } header: {
                Text("แชร์ไปที่")
            }

            Section {
                destination("Markdown (.md)", subtitle: "Obsidian, Files, Bear, Notion", symbol: "doc.plaintext", tint: .gray) {
                    shareMarkdown()
                }
                destination("PDF", subtitle: "พิมพ์ ส่งอีเมล หรือ AirDrop", symbol: "doc.richtext", tint: .red) {
                    sharePDF()
                }
                destination("ข้อความ", subtitle: "คัดลอกหรือส่งในแชท", symbol: "text.quote", tint: .blue) {
                    SharePresenter.present([NoteExporter.plainText(for: note)])
                }
            } header: {
                Text("ส่งออกผ่านแผ่นแชร์ iOS")
            }

            Section {
                Button {
                    onFinished()
                } label: {
                    Label("เก็บไว้ในแอปอย่างเดียว", systemImage: "tray.and.arrow.down")
                }
            }
        }
        .navigationTitle("แชร์โน้ต")
        .alert("แชร์ไม่สำเร็จ", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("ตกลง", role: .cancel) {}
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
