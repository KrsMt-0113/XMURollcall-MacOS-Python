import Testing
import Foundation
@testable import XMURollcall

@Suite("XMURollcall Tests")
struct XMURollcallTests {

    // MARK: - Account Model Tests

    @Test("Account initializes with correct default values")
    func testAccountInitialization() {
        let account = Account(
            nickname: "Test",
            username: "12345678",
            password: "pass123",
            colorHex: "#E74C3C"
        )

        #expect(account.nickname == "Test")
        #expect(account.username == "12345678")
        #expect(account.password == "pass123")
        #expect(account.colorHex == "#E74C3C")
        #expect(account.cookiesJSON == nil)
        #expect(account.displayName == nil)
        #expect(!account.id.isEmpty)
    }

    @Test("Account equality is based on all fields")
    func testAccountEquality() {
        let a = Account(id: "abc", nickname: "A", username: "u1", password: "p1", colorHex: "#000000")
        let b = Account(id: "abc", nickname: "A", username: "u1", password: "p1", colorHex: "#000000")
        let c = Account(id: "def", nickname: "A", username: "u1", password: "p1", colorHex: "#000000")

        #expect(a == b)
        #expect(a != c)
    }

    @Test("Account preset colors has 7 entries")
    func testPresetColors() {
        #expect(Account.presetColors.count == 7)
        for preset in Account.presetColors {
            #expect(preset.hex.hasPrefix("#"))
            #expect(preset.hex.count == 7)
        }
    }

    // MARK: - Color Hex Extension Tests

    @Test("Color hex parsing handles 6-digit hex")
    func testColorHexParsing() {
        // Verify it doesn't crash with valid and edge-case hex values
        let _ = SwiftUI.Color(hex: "#FF0000")
        let _ = SwiftUI.Color(hex: "#00FF00")
        let _ = SwiftUI.Color(hex: "#0000FF")
        let _ = SwiftUI.Color(hex: "000000")
        let _ = SwiftUI.Color(hex: "#FFFFFF")
    }

    // MARK: - RollcallRecord Tests

    @Test("RollcallRecord time string formats correctly")
    func testRollcallRecordTimeString() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let components = DateComponents(year: 2026, month: 4, day: 5, hour: 14, minute: 30, second: 45)
        let date = calendar.date(from: components)!

        let record = RollcallRecord(
            id: "test-1",
            time: date,
            courseName: "数学分析",
            rollcallType: .number,
            result: .trying
        )

        #expect(record.timeString == "14:30:45")
        #expect(record.courseName == "数学分析")
        #expect(record.rollcallType == .number)
    }

    @Test("RollcallResult display text and color are correct")
    func testRollcallResultDisplay() {
        #expect(RollcallResult.trying.displayText == "trying...")
        #expect(RollcallResult.retrying.displayText == "retrying...")
        #expect(RollcallResult.failed("timeout").displayText == "failed: timeout")
        #expect(RollcallResult.failed("").displayText == "failed")
        #expect(RollcallResult.success("1234").displayText == "1234")
        #expect(RollcallResult.qrcode.displayText == "")
    }

    // MARK: - RollcallData Tests

    @Test("RollcallData type detection is correct")
    func testRollcallDataType() {
        let radar = RollcallData(
            rollcallID: 1, courseTitle: "Test", createdByName: "", departmentName: "",
            isExpired: false, isNumber: false, isRadar: true,
            rollcallStatus: "", scored: 0, status: "absent"
        )
        #expect(radar.type == .radar)

        let number = RollcallData(
            rollcallID: 2, courseTitle: "Test", createdByName: "", departmentName: "",
            isExpired: false, isNumber: true, isRadar: false,
            rollcallStatus: "", scored: 0, status: "absent"
        )
        #expect(number.type == .number)

        let qrcode = RollcallData(
            rollcallID: 3, courseTitle: "Test", createdByName: "", departmentName: "",
            isExpired: false, isNumber: false, isRadar: false,
            rollcallStatus: "", scored: 0, status: "absent"
        )
        #expect(qrcode.type == .qrcode)
    }

    @Test("RollcallData JSON serialization produces valid JSON")
    func testRollcallDataJSON() {
        let data = RollcallData(
            rollcallID: 42, courseTitle: "高等数学", createdByName: "张教授",
            departmentName: "数学系", isExpired: false, isNumber: true, isRadar: false,
            rollcallStatus: "active", scored: 0, status: "absent"
        )
        let json = data.jsonString
        #expect(!json.isEmpty)
        #expect(json != "{}")

        // Verify it's valid JSON
        let jsonData = json.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        #expect(parsed != nil)
        #expect(parsed?["rollcall_id"] as? Int == 42)
        #expect(parsed?["course_title"] as? String == "高等数学")
    }

    // MARK: - AppScreen Equality Tests

    @Test("AppScreen equality works correctly")
    func testAppScreenEquality() {
        let account1 = Account(id: "a1", nickname: "A", username: "u", password: "p", colorHex: "#000")
        let account2 = Account(id: "a2", nickname: "B", username: "u", password: "p", colorHex: "#000")

        #expect(AppScreen.start == AppScreen.start)
        #expect(AppScreen.accountSelection == AppScreen.accountSelection)
        #expect(AppScreen.addAccount == AppScreen.addAccount)
        #expect(AppScreen.monitor(account1) == AppScreen.monitor(account1))
        #expect(AppScreen.monitor(account1) != AppScreen.monitor(account2))
        #expect(AppScreen.start != AppScreen.accountSelection)
    }
}

import SwiftUI
