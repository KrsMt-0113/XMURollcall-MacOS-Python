import SwiftUI
import Foundation

/// Represents a saved XMU user account.
struct Account: Identifiable, Codable, Equatable, Sendable {
    let id: String          // UUID string
    var nickname: String
    var username: String
    var password: String
    var colorHex: String    // e.g. "#FF0000"

    /// Cookies JSON string cached from last successful login.
    var cookiesJSON: String?

    /// Display name retrieved from profile after login.
    var displayName: String?

    /// The SwiftUI Color derived from the hex string.
    var color: Color {
        Color(hex: colorHex)
    }

    init(
        id: String = UUID().uuidString,
        nickname: String,
        username: String,
        password: String,
        colorHex: String,
        cookiesJSON: String? = nil,
        displayName: String? = nil
    ) {
        self.id = id
        self.nickname = nickname
        self.username = username
        self.password = password
        self.colorHex = colorHex
        self.cookiesJSON = cookiesJSON
        self.displayName = displayName
    }
}

// MARK: - Preset Colors

extension Account {
    /// Preset color options for account creation.
    static let presetColors: [(name: String, hex: String)] = [
        ("Red",    "#E74C3C"),
        ("Orange", "#E67E22"),
        ("Yellow", "#F1C40F"),
        ("Green",  "#2ECC71"),
        ("Blue",   "#3498DB"),
        ("Purple", "#9B59B6"),
        ("Pink",   "#E91E8A"),
    ]
}

// MARK: - Color Extension for Hex Support

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        case 8:
            r = Double((int >> 24) & 0xFF) / 255.0
            g = Double((int >> 16) & 0xFF) / 255.0
            b = Double((int >> 8) & 0xFF) / 255.0
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}
