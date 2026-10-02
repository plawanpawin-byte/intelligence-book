// Runs on the CI Mac before the app build:
// swiftc IntelligenceBook/AI/ThaiNumbers.swift IntelligenceBook/AI/NoteText.swift tools/swiftcheck/main.swift
// Expected values come from the Python mirror in tools/eval/pipeline.py (eval branch).
import Foundation

let cases: [(String, String)] = [
    ("ถ้าขายแก้วละสามสิบห้า ต้นทุนประมาณสิบแปดบาท", "ถ้าขายแก้วละ 35 ต้นทุนประมาณ 18 บาท"),
    ("กำไรวันละแปดร้อยห้าสิบ", "กำไรวันละ 850"),
    ("เครื่องชงมือสองประมาณหมื่นสอง", "เครื่องชงมือสองประมาณ 12,000"),
    ("ราคาถูกดันขึ้นไปจนถึงร้อยห้าสิบ", "ราคาถูกดันขึ้นไปจนถึง 150"),
    ("Qd เท่ากับ หกร้อย ลบ สองพี", "Qd เท่ากับ 600 ลบ สองพี"),
    ("ทำได้เรียบร้อย", "ทำได้เรียบร้อย"),
    ("เราสามารถทำได้", "เราสามารถทำได้"),
    ("นั่งเก้าอี้", "นั่งเก้าอี้"),
    ("สายพันธุ์ใหม่", "สายพันธุ์ใหม่"),
    ("ยี่สิบเอ็ดวัน", "21 วัน"),
    ("สองพันห้าร้อยหกสิบสามคน", "2,563 คน"),
    ("สามล้านห้าแสนบาท", "3,500,000 บาท"),
    ("ประมาณสี่สิบเปอร์เซ็นต์", "ประมาณ 40 เปอร์เซ็นต์"),
    ("พันสองบาท", "1,200 บาท"),
    ("สิบโมง", "10 โมง"),
    ("ร้อยละห้าสิบ", "50%"),
    ("หกล้ม", "หกล้ม"),
]
var failed = 0
for (input, expected) in cases {
    let output = ThaiNumbers.convert(input)
    if output != expected {
        failed += 1
        print("FAIL: \(input) → \(output) (expected \(expected))")
    }
}

func check(_ name: String, _ got: String, _ want: String) {
    if got != want {
        failed += 1
        print("FAIL \(name):\n--- got ---\n\(got)\n--- want ---\n\(want)")
    }
}

check("speech",
      SourceCleaner.speech("[00:00] เอ่อ โอเคนะครับ  ถ้าขายแก้วละสามสิบห้า ต้นทุนประมาณสิบแปดบาท ครับ\n[00:50] ใช่ ดีมานด์ลดนะครับ"),
      "ถ้าขายแก้วละ 35 ต้นทุนประมาณ 18 บาท\nดีมานด์ลด")

let parsed = FactList.parse("TOPIC: x\n- determinants of demand:\n 1. รายได้ผู้บริโภค (income)\n 2. รสนิยม\n- น้ำตาลในชานม")
check("facts.topic", parsed.topic, "x")
check("facts", parsed.facts.joined(separator: "\n"), "- determinants of demand:\n  - รายได้ผู้บริโภค (income)\n  - รสนิยม\n- น้ำตาลในชานม")

let note = "## X\nราคาข้าว 10 บาท ดุลยภาพ 150 บาท\n> [!example] ตัวอย่าง\n> อุปสงค์จะเท่ากับ 100 กิโลกรัม\nok line 2 แบบ\n| a | b |\n|---|---|\n| x | 999 |\n### [!question] คำถาม\n**คำตอบ:** ตอบ"
check("grounding+fixer",
      MarkdownFixer.fix(Grounding.dropUngroundedNumbers(note, allowed: ["150", "600"]), thai: true),
      "## X\nราคาข้าว 10 บาท ดุลยภาพ 150 บาท\nok line 2 แบบ\n\n> [!question] คำถาม\n> **คำตอบ:** ตอบ")
check("numbers", Grounding.numbers(in: "ราคา 12,000 บาท และ 0.50 กับ 3.").sorted().joined(separator: ","), "0.5,0.50,12000,3")
check("summary title", MarkdownFixer.fix("> [!summary]\n> ok", thai: false), "> [!summary] Overview\n> ok")
check("bullet callout", MarkdownFixer.fix("* [!tip] จำ\ntext", thai: true), "> [!tip] จำ\ntext")

let example = "## ภูเขาไฟ: ทำไมบางลูกไหลเอื่อย แต่บางลูกระเบิดรุนแรง ภูเขาไฟเริ่มต้นจากแมกมาหินหลอมเหลวที่ร้อนราว 1,000 °C ใต้เปลือกโลก"
check("overlap copy", String(Grounding.overlap(example, with: example) > 0.9), "true")
check("overlap other", String(Grounding.overlap("อุปสงค์ (demand) คือ ปริมาณสินค้าที่ผู้บริโภค เต็มใจ ซื้อ ณ ระดับราคาต่างๆ", with: example) < 0.05), "true")
check("near duplicate", String(FactList.isNearDuplicate(FactList.trigrams("การแทรกแซง เพดานต่ำกว่าดุลยภาพ เกิด shortage ตลาดมืด"),
                                                        of: [FactList.trigrams("**การแทรกแซง**: เพดานต่ำกว่าดุลยภาพ เกิด shortage ตลาดมืด ขั้นต่ำสูงกว่า")])), "true")

let chunks = TextChunker.split(String(repeating: "ก ข ค ง ", count: 2000), maxCharacters: 3500)
check("chunker sizes", String(chunks.allSatisfy { $0.count <= 3500 + 1100 } && chunks.count >= 2), "true")
check("chunker keeps text", String(chunks.joined(separator: " ").filter { !$0.isWhitespace }.count), String(8000))

check("merge", SectionTools.merge(["## A\n\nfirst body text that is long enough to keep here", "## A\n\nsecond body text that is long enough to keep", "## B\n\nx"]).joined(separator: "|"),
      "## A\n\nfirst body text that is long enough to keep here\n\nsecond body text that is long enough to keep")
check("thai detect", String(LanguageDetector.isThai("อุปสงค์ demand คือ")), "true")

print(failed == 0 ? "Self-check: all tests pass" : "Self-check: \(failed) failures")
exit(failed == 0 ? 0 : 1)
