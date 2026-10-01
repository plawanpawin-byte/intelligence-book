# IntelligenceBook

แอป iOS แนว NotebookLM: โยน **PDF · ลิงก์เว็บ · YouTube · ข้อความ · ไฟล์เสียง · อัดเสียงสด** แล้วให้ **Llama 3.2 3B ที่รันบนเครื่อง (แสดงในแอปชื่อ "Apple Foundation Models 3B")** สรุปเป็นโน้ตที่อ่านง่าย มีไฮไลท์ กล่องสี (callout) โค้ด และตาราง จากนั้นถามว่าจะแชร์ไปไหน — Obsidian, Canva, Notes หรือแผ่นแชร์ของ iOS

UI เป็น SwiftUI แบบ Apple native (หน้าแรกเป็นการ์ด 2 คอลัมน์แบบ Apple Notes gallery พร้อมรูปปก, ปุ่มค้นหาและปุ่มสร้างแบบ Liquid Glass ลอยด้านล่าง, เมนู ≡ มุมขวาบน: ปักหมุด / ลบ / เลือกโมเดล, NavigationStack, List/Form, sheets, share sheet, SF Symbols, semantic colors, Dynamic Type, Light/Dark)

## ฟีเจอร์

| ส่วน | ทำงานอย่างไร |
|---|---|
| PDF | PDFKit ดึงข้อความ, หน้าสแกนใช้ Vision OCR |
| ลิงก์เว็บ | ดึง HTML แล้วตัดเหลือเนื้อหาหลัก (article/main) |
| YouTube | ดึงคำบรรยาย (ไทย → อังกฤษ) พร้อม timestamp |
| ข้อความ | วางได้เลย |
| ไฟล์เสียง / อัดสด | AVAudioRecorder + Speech framework ถอดเสียงทีละ 50 วินาที (ยาวเท่าไหร่ก็ได้) |
| AI | Llama 3.2 3B (4-bit) ผ่าน MLX Swift — ชื่อในแอป "Apple Foundation Models 3B" (เครื่องแรม < 5.5 GB ใช้ 1B) · กันตอบวนซ้ำ (repetition penalty + ตัดบรรทัดซ้ำ) · เนื้อหาสั้นได้โน้ตสั้น · Built with Llama |
| เอกสารยาว | map → reduce: ย่อทีละช่วงให้พอดี context แล้วค่อยเขียนโน้ตฉบับเต็ม |
| รูปแบบโน้ต | สรุปใจความ · คู่มืออ่านทบทวน · โครงร่าง · คำถามทบทวน |
| แชร์ | Obsidian (`obsidian://new` + Markdown/callout), PDF สีสำหรับ Canva/Notes, Markdown, ข้อความ |

### Syntax ของโน้ต (Obsidian-compatible)

```markdown
# หัวเรื่อง
> [!summary] สรุปสั้น        ← เหลือง
> ...
- ประเด็นที่มี ==ไฮไลท์== และ **คำสำคัญ**
> [!definition] คำศัพท์      ← เขียวอมฟ้า
> [!tip] ประเด็นสำคัญ        ← ส้ม
> [!question] คำถามทบทวน     ← ชมพู
> [!warning] ข้อควรระวัง     ← แดง
```

## Build IPA ด้วย GitHub Actions

ทุกครั้งที่ push ไป `main` workflow `.github/workflows/build-ipa.yml` จะ

1. ใช้ runner `macos-26` + Xcode 26 
2. `xcodegen generate` จาก `project.yml`
3. `xcodebuild archive` แบบไม่เซ็น
4. แพ็กเป็น `IntelligenceBook-unsigned.ipa` → ดาวน์โหลดได้จากหน้า Actions → artifact **IntelligenceBook-unsigned-ipa**

ติดตั้งลงเครื่องด้วย Sideloadly / AltStore / Feather (เซ็นด้วย Apple ID ของคุณเอง)

> ⚠️ MLX ใช้ Metal จึง**ไม่รันบน Simulator** ต้องทดสอบบนเครื่องจริง โหลดโมเดลครั้งแรก ~1.8 GB
> อัดเสียงยาว 2–3 ชม. ได้แม้ล็อกจอ (background audio) และถอดเสียงไปพร้อมกันระหว่างอัด

## โครงสร้าง

```
IntelligenceBook/
  App/         entry + TabView
  Models/      SwiftData: Notebook, Source, Note
  AI/          DeviceProfile, LLMService (MLX + RepetitionGuard), NoteGenerator (prompt + map-reduce)
  Ingestion/   PDF/OCR, เว็บ, YouTube, Speech, SourceProcessor
  Recording/   อัดเสียง + เล่นเสียง
  Notes/       parser + ตัวเรนเดอร์สี/ไฮไลท์ + export (MD/PDF/ข้อความ/Obsidian)
  Views/       Library (masonry cards), Notebook, Generate, Note, Share, SourceImport
```

สเปกฉบับเต็มอยู่ใน Obsidian vault “intelligence book”
