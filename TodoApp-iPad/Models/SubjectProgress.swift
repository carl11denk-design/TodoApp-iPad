import Foundation

struct SubjectProgress: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var customColorHue: Double? = nil   // nil = automatisch aus Name generiert

    // Skript
    var scriptCurrentPage: Int = 0
    var scriptTotalPages: Int  = 0   // 0 = nicht gesetzt

    // Nacharbeit
    var nacharbeitCurrentPage: Int = 0
    var nacharbeitTotalPages: Int  = 0   // 0 = nicht gesetzt

    var scriptProgress: Double {
        guard scriptTotalPages > 0 else { return 0 }
        return min(Double(scriptCurrentPage) / Double(scriptTotalPages), 1.0)
    }

    var nacharbeitProgress: Double {
        guard nacharbeitTotalPages > 0 else { return 0 }
        return min(Double(nacharbeitCurrentPage) / Double(nacharbeitTotalPages), 1.0)
    }
}
