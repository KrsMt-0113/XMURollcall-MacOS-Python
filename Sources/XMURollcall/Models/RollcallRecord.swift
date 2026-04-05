import SwiftUI
import Foundation

/// Represents a rollcall event detected during monitoring.
struct RollcallRecord: Identifiable, Equatable, Sendable {
    let id: String
    let time: Date
    let courseName: String
    let rollcallType: RollcallType
    var result: RollcallResult

    /// The formatted time string for display.
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: time)
    }
}

/// The type of rollcall.
enum RollcallType: String, Sendable {
    case number = "Number"
    case radar  = "Radar"
    case qrcode = "QR Code"

    var displayName: String { rawValue }
}

/// The result status of a rollcall attempt.
enum RollcallResult: Equatable, Sendable {
    case trying
    case retrying
    case failed(String)
    case success(String)
    case qrcode

    var displayText: String {
        switch self {
        case .trying:
            return "trying..."
        case .retrying:
            return "retrying..."
        case .failed(let msg):
            return msg.isEmpty ? "failed" : "failed: \(msg)"
        case .success(let detail):
            return detail
        case .qrcode:
            return ""
        }
    }

    var color: Color {
        switch self {
        case .trying:
            return .primary
        case .retrying:
            return .yellow
        case .failed:
            return .red
        case .success:
            return .green
        case .qrcode:
            return .primary
        }
    }
}

/// Raw rollcall data from the API poll response.
struct RollcallData: Sendable {
    let rollcallID: Int
    let courseTitle: String
    let createdByName: String
    let departmentName: String
    let isExpired: Bool
    let isNumber: Bool
    let isRadar: Bool
    let rollcallStatus: String
    let scored: Int
    let status: String

    /// Determine the rollcall type.
    var type: RollcallType {
        if isRadar { return .radar }
        if isNumber { return .number }
        return .qrcode
    }

    /// JSON string representation for passing to Python handler.
    var jsonString: String {
        let dict: [String: Any] = [
            "rollcall_id": rollcallID,
            "course_title": courseTitle,
            "created_by_name": createdByName,
            "department_name": departmentName,
            "is_expired": isExpired,
            "is_number": isNumber,
            "is_radar": isRadar,
            "rollcall_status": rollcallStatus,
            "scored": scored,
            "status": status,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}
