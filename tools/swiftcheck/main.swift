// Runs on the CI Mac before the app build: swiftc IntelligenceBook/AI/ThaiNumbers.swift tools/swiftcheck/main.swift
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
print(failed == 0 ? "ThaiNumbers: all \(cases.count) cases pass" : "ThaiNumbers: \(failed) failures")
exit(failed == 0 ? 0 : 1)
