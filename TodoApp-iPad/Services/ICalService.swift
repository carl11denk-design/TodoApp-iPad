import Foundation
import Observation
import WidgetKit

@Observable
class ICalService {
    var events: [CalendarEvent] = []
    var isLoading = false
    var errorMessage: String?

    private let cacheKey = "todoapp_calendar_events_v2"
    private let defaults = UserDefaults(suiteName: PersistenceManager.appGroupID) ?? .standard

    init() {
        loadCachedEvents()
    }

    func fetch(url: String) async {
        await MainActor.run {
            self.isLoading    = true
            self.errorMessage = nil
        }

        do {
            let text   = try await fetchRawData(urlString: url)
            let parsed = ICalParser.parse(text: text)

            await MainActor.run {
                self.events    = parsed
                self.isLoading = false
                self.cacheEvents(parsed)
            }
        } catch is CancellationError {
            await MainActor.run { self.isLoading = false }
        } catch let error as URLError where error.code == .cancelled {
            await MainActor.run { self.isLoading = false }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading    = false
            }
        }
    }

    // MARK: - Fetch

    private func fetchRawData(urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return text
    }

    // MARK: - Cache

    private func cacheEvents(_ events: [CalendarEvent]) {
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: cacheKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func loadCachedEvents() {
        guard let data   = defaults.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([CalendarEvent].self, from: data)
        else { return }
        self.events = cached
    }
}
