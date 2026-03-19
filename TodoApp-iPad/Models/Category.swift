import SwiftUI

struct Category: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var colorHex: String
    var icon: String

    var color: Color { Color(hex: colorHex) }
}

extension Category {
    static let defaults: [Category] = [
        Category(name: "Allgemein", colorHex: "#6B7280", icon: "circle.fill"),
        Category(name: "Arbeit",    colorHex: "#3B82F6", icon: "briefcase.fill"),
        Category(name: "Studium",   colorHex: "#8B5CF6", icon: "book.fill"),
        Category(name: "Einkauf",   colorHex: "#10B981", icon: "cart.fill"),
        Category(name: "Sport",     colorHex: "#F59E0B", icon: "figure.run"),
        Category(name: "Privat",    colorHex: "#EC4899", icon: "heart.fill"),
    ]
}
