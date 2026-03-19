import Foundation

struct CalendarEvent: Identifiable, Codable {
    var id = UUID()
    let summary: String
    let location: String?
    let startDate: Date
    let endDate: Date

    enum CodingKeys: String, CodingKey {
        case summary, location, startDate, endDate
    }
}
