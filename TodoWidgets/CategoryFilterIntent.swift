import AppIntents

struct CategoryFilterIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Kategorie wählen"
    static var description: IntentDescription = "Filtere Aufgaben nach Kategorie"

    @Parameter(title: "Kategorie", default: "Alle")
    var categoryName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Kategorie: \(\.$categoryName)")
    }

    init() {}

    init(categoryName: String) {
        self.categoryName = categoryName
    }
}
