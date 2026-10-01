# IntelligenceBook

แอป iOS แนว NotebookLM: โยน **PDF · ลิงก์เว็บ · YouTube · ข้อความ · ไฟล์เสียง · อัดเสียงสด** แล้วให้ **Llama 3.2 ที่รันบนเครื่อง** สรุปเป็นโน้ตที่อ่านง่าย มีไฮไลท์ กล่องสี (callout) โค้ด และตาราง จากนั้นถามว่าจะแชร์ไปไหน — Obsidian, Canva, Notes หรือแผ่นแชร์ของ iOS

UI เป็น SwiftUI แบบ Apple native (TabView, NavigationStack, List/Form, sheets, share sheet, SF Symbols, semantic colors, Dynamic Type, Light/Dark)

## ฟีเจอร์

| ส่วน | ทำงานอย่างไร |
|---|---|
| PDF | PDFKit ดึงข้อความ, หน้าสแกนใช้ Vision OCR |
| ลิงก์เว็บ | ดึง HTML แล้วตัดเหลือเนื้อหาหลัก (article/main) |
| YouTube | ดึงคำบรรยาย (ไทย → อังกฤษ) พร้อม timestamp |
| ข้อความ | วางได้เลย |
| ไฟล์เสียง / อัดสด | AVAudioRecorder + Speech framework ถอดเสียงทีละ 50 วินาที (ยาวเท่าไหร่ก็ได้) |
| AI | Llama 3.2 ผ่าน MLX Swift — **เลือก 1B/3B อัตโนมัติตามแรมเครื่อง** (≥ 8 GB → 3B) เปลี่ยนเองได้ในตั้งค่า |
| เอกสารยาว | map → reduce: ย่อทีละช่วงให้พอดี context แล้วค่อยเขียนโน้ตฉบับเต็ม |
| รูปแบบโน้ต | สรุปใจความ · คู่มืออ่านทบทวน · โครงร่าง · คำถามทบทวน |
| แชร์ | Obsidian (`obsidian://new` + Markdown/callout), PDF สีสำหรับ Canva/Notes, Markdown, ข้อความ |

### Syntax ของโน้ต (Obsidian-compatible)

```markdown
# หัวเรื่อง
> [!summary] สรุปสั้น        ← ม่วง (AI insight)
> ...
- ประเด็นที่มี ==ไฮไลท์== และ **คำสำคัญ**
> [!definition] คำศัพท์      ← เขียวอมฟ้า
> [!tip] ประเด็นสำคัญ        ← เหลือง
> [!question] คำถามทบทวน     ← ส้ม
> [!warning] ข้อควรระวัง     ← แดง
```

## Build IPA ด้วย GitHub Actions

ทุกครั้งที่ push ไป `main` workflow `.github/workflows/build-ipa.yml` จะ

1. ใช้ runner `macos-26` + Xcode 26 (ติดตั้ง Metal toolchain ให้ MLX)
2. `xcodegen generate` จาก `project.yml`
3. `xcodebuild archive` แบบไม่เซ็น
4. แพ็กเป็น `IntelligenceBook-unsigned.ipa` → ดาวน์โหลดได้จากหน้า Actions → artifact **IntelligenceBook-unsigned-ipa**

ติดตั้งลงเครื่องด้วย Sideloadly / AltStore / Feather (เซ็นด้วย Apple ID ของคุณเอง)

> ⚠️ MLX ใช้ Metal จึง**ไม่รันบน Simulator** ต้องทดสอบบนเครื่องจริง และโหลดโมเดลครั้งแรก ~0.7 GB (1B) หรือ ~1.8 GB (3B)

## โครงสร้าง

```
IntelligenceBook/
  App/         entry + TabView
  Models/      SwiftData: Notebook, Source, Note
  AI/          DeviceProfile (เลือก 1B/3B), LLMService (MLX), NoteGenerator (prompt + map-reduce)
  Ingestion/   PDF/OCR, เว็บ, YouTube, Speech, SourceProcessor
  Recording/   อัดเสียง + เล่นเสียง
  Notes/       parser + ตัวเรนเดอร์สี/ไฮไลท์ + export (MD/PDF/ข้อความ/Obsidian)
  Views/       Library, Create, Notebook, Generate, Note, Share, Settings
```

สเปกฉบับเต็มอยู่ใน Obsidian vault “intelligence book”
