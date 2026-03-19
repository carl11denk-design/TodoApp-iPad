import SwiftUI

enum Priority: String, Codable, CaseIterable {
    case low    = "Niedrig"
    case medium = "Mittel"
    case high   = "Hoch"

    var color: Color {
        switch self {
        case .low:    return .green
        case .medium: return .orange
        case .high:   return .red
        }
    }

    var icon: String {
        switch self {
        case .low:    return "arrow.down.circle.fill"
        case .medium: return "minus.circle.fill"
        case .high:   return "arrow.up.circle.fill"
        }
    }

    var sortOrder: Int {
        switch self {
        case .high:   return 0
        case .medium: return 1
        case .low:    return 2
        }
    }
}
