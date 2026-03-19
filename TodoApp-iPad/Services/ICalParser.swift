import Foundation

/// Standalone parser for ICS and Rapla HTML formats.
/// Shared between main app and widget extension.
enum ICalParser {

    static func parse(text: String) -> [CalendarEvent] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("<") {
            if let range = text.range(of: "BEGIN:VCALENDAR[\\s\\S]*?END:VCALENDAR",
                                      options: .regularExpression) {
                return parseICS(String(text[range]))
            } else if text.contains("week_block") {
                return parseRaplaHTML(text)
            }
            return []
        }
        return parseICS(text)
    }

    // MARK: - ICS Parser

    static func parseICS(_ ics: String) -> [CalendarEvent] {
        var events: [CalendarEvent] = []
        let blocks      = ics.components(separatedBy: "BEGIN:VEVENT")
        let dtFormatter = DateFormatter()
        dtFormatter.locale = Locale(identifier: "en_US_POSIX")

        for block in blocks.dropFirst() {
            guard let endRange = block.range(of: "END:VEVENT") else { continue }
            let content  = String(block[block.startIndex..<endRange.lowerBound])
            let summary  = extractField("SUMMARY",  from: content) ?? "Kein Titel"
            let location = extractField("LOCATION", from: content)
            let dtStart  = extractField("DTSTART",  from: content) ?? extractFieldWithParams("DTSTART", from: content)
            let dtEnd    = extractField("DTEND",    from: content) ?? extractFieldWithParams("DTEND",   from: content)
            guard let startStr = dtStart, let endStr = dtEnd,
                  let startDate = parseICSDate(startStr, formatter: dtFormatter),
                  let endDate   = parseICSDate(endStr,   formatter: dtFormatter)
            else { continue }
            events.append(CalendarEvent(summary: summary, location: location, startDate: startDate, endDate: endDate))
        }
        return events.sorted { $0.startDate < $1.startDate }
    }

    private static func extractField(_ name: String, from text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("\(name):") { return String(t.dropFirst(name.count + 1)) }
        }
        return nil
    }

    private static func extractFieldWithParams(_ name: String, from text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix(name + ";"), let ci = t.firstIndex(of: ":") {
                return String(t[t.index(after: ci)...])
            }
        }
        return nil
    }

    private static func parseICSDate(_ str: String, formatter: DateFormatter) -> Date? {
        let c = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.hasSuffix("Z") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone   = TimeZone(identifier: "UTC")
        } else {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
            formatter.timeZone   = TimeZone.current
        }
        if let d = formatter.date(from: c) { return d }
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: c)
    }

    // MARK: - Rapla HTML Parser

    private struct RawCell {
        let tag: String
        let attrs: String
        let content: String
        let rowSpan: Int
        let colSpan: Int
    }

    static func parseRaplaHTML(_ html: String) -> [CalendarEvent] {
        var events: [CalendarEvent] = []

        let cleanHTML = html
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\u{00a0}", with: " ")

        let tablePattern = #"<table[^>]*class="[^"]*week_table[^"]*"[^>]*>([\s\S]*?)</table>"#
        guard let tableRegex = try? NSRegularExpression(pattern: tablePattern) else { return [] }
        let tableMatches = tableRegex.matches(in: cleanHTML, range: NSRange(cleanHTML.startIndex..., in: cleanHTML))

        for tableMatch in tableMatches {
            guard let tableRange = Range(tableMatch.range(at: 1), in: cleanHTML) else { continue }
            let tableHTML = String(cleanHTML[tableRange])
            let dayCols   = buildDayCols(from: tableHTML)
            let rows      = extractRows(from: tableHTML)
            guard rows.count > 1 else { continue }

            let maxCols = max(dayCols.count + 5, 30)
            var grid = Array(repeating: Array(repeating: false, count: maxCols), count: rows.count)

            for (rowIdx, row) in rows.enumerated() {
                let cells   = extractCells(from: row)
                var gridCol = 0

                for cell in cells {
                    while gridCol < maxCols && grid[rowIdx][gridCol] { gridCol += 1 }
                    guard gridCol < maxCols else { break }

                    for r in 0..<cell.rowSpan {
                        for c in 0..<cell.colSpan {
                            let gr = rowIdx + r; let gc = gridCol + c
                            if gr < grid.count && gc < maxCols { grid[gr][gc] = true }
                        }
                    }

                    if cell.attrs.contains("week_block") {
                        let dayName = gridCol < dayCols.count ? dayCols[gridCol] : ""
                        if !dayName.isEmpty, let (timeStr, title) = extractEventInfo(from: cell.content) {
                            let resources = extractResources(from: cell.content)
                            let location  = resources.joined(separator: " | ")
                            if let (startDate, endDate) = parseRaplaDateTime(dayHeader: dayName, timeString: timeStr) {
                                events.append(CalendarEvent(
                                    summary:   title,
                                    location:  location.isEmpty ? nil : location,
                                    startDate: startDate,
                                    endDate:   endDate
                                ))
                            }
                        }
                    }
                    gridCol += cell.colSpan
                }
            }
        }
        return events.sorted { $0.startDate < $1.startDate }
    }

    private static func buildDayCols(from tableHTML: String) -> [String] {
        let rows  = extractRows(from: tableHTML)
        guard let firstRow = rows.first else { return [] }
        let cells = extractCells(from: firstRow)
        var dayCols: [String] = []
        for cell in cells {
            let text = cell.content
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cell.attrs.contains("week_header") {
                for _ in 0..<cell.colSpan { dayCols.append(text) }
            } else {
                dayCols.append("")
            }
        }
        return dayCols
    }

    private static func extractRows(from html: String) -> [String] {
        let pattern = #"<tr[^>]*>([\s\S]*?)</tr>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { m in
            guard let r = Range(m.range(at: 1), in: html) else { return nil }
            return String(html[r])
        }
    }

    private static func extractCells(from rowHTML: String) -> [RawCell] {
        let pattern = #"<(td|th)([^>]*)>([\s\S]*?)</(?:td|th)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: rowHTML, range: NSRange(rowHTML.startIndex..., in: rowHTML)).compactMap { m in
            guard
                let tagRange     = Range(m.range(at: 1), in: rowHTML),
                let attrsRange   = Range(m.range(at: 2), in: rowHTML),
                let contentRange = Range(m.range(at: 3), in: rowHTML)
            else { return nil }
            let attrs = String(rowHTML[attrsRange])
            return RawCell(
                tag:     String(rowHTML[tagRange]),
                attrs:   attrs,
                content: String(rowHTML[contentRange]),
                rowSpan: extractIntAttr("rowspan", from: attrs) ?? 1,
                colSpan: extractIntAttr("colspan", from: attrs) ?? 1
            )
        }
    }

    private static func extractEventInfo(from cellContent: String) -> (time: String, title: String)? {
        let linkPattern = #"<a[^>]*>([\s\S]*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: linkPattern),
              let match = regex.firstMatch(in: cellContent, range: NSRange(cellContent.startIndex..., in: cellContent)),
              let range = Range(match.range(at: 1), in: cellContent)
        else { return nil }

        let text = String(cellContent[range])
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }
        return (lines[0], lines[1])
    }

    private static func extractResources(from cellContent: String) -> [String] {
        let pattern = #"<span[^>]*class="[^"]*resource[^"]*"[^>]*>([^<]*)</span>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: cellContent, range: NSRange(cellContent.startIndex..., in: cellContent)).compactMap { m in
            guard let r = Range(m.range(at: 1), in: cellContent) else { return nil }
            let val = String(cellContent[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            return val.isEmpty || val.hasPrefix("STG-") ? nil : val
        }
    }

    private static func parseRaplaDateTime(dayHeader: String, timeString: String) -> (Date, Date)? {
        let cal = Calendar.current
        guard
            let dateRegex = try? NSRegularExpression(pattern: #"(\d{1,2})\.(\d{1,2})\."#),
            let dateMatch = dateRegex.firstMatch(in: dayHeader, range: NSRange(dayHeader.startIndex..., in: dayHeader)),
            let dayRange   = Range(dateMatch.range(at: 1), in: dayHeader),
            let monthRange = Range(dateMatch.range(at: 2), in: dayHeader),
            let day   = Int(dayHeader[dayRange]),
            let month = Int(dayHeader[monthRange])
        else { return nil }

        var year = cal.component(.year, from: Date())
        if month < cal.component(.month, from: Date()) - 6 { year += 1 }

        let cleanTime = timeString.replacingOccurrences(of: " ", with: "")
        let timeParts = cleanTime.components(separatedBy: "-")
        guard timeParts.count >= 2 else { return nil }
        let sp = timeParts[0].components(separatedBy: ":"); let ep = timeParts[1].components(separatedBy: ":")
        guard sp.count == 2, ep.count == 2,
              let sh = Int(sp[0]), let sm = Int(sp[1]),
              let eh = Int(ep[0]), let em = Int(ep[1])
        else { return nil }

        var startComps = DateComponents()
        startComps.year = year; startComps.month = month; startComps.day = day
        startComps.hour = sh; startComps.minute = sm
        var endComps   = startComps
        endComps.hour  = eh; endComps.minute = em

        guard let startDate = cal.date(from: startComps), let endDate = cal.date(from: endComps) else { return nil }
        return (startDate, endDate)
    }

    private static func extractIntAttr(_ name: String, from attrs: String) -> Int? {
        let pattern = "\(name)=\"(\\d+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
              let range = Range(match.range(at: 1), in: attrs)
        else { return nil }
        return Int(attrs[range])
    }
}
