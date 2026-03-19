import Foundation

// MARK: - No-Redirect Delegate (captures REFRESH header before redirect)

private class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil) // Cancel redirect to read REFRESH header
    }
}

// MARK: - Dualis Scraper

final class DualisService {
    static let shared = DualisService()

    private let baseURL = "https://dualis.dhbw.de/scripts/mgrqispi.dll"
    private var authArgs: String?
    private var session: URLSession!
    private let noRedirectDelegate = NoRedirectDelegate()

    init() {
        resetSession()
    }

    private func resetSession() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config)
    }

    enum DualisError: LocalizedError {
        case invalidCredentials
        case noSession
        case networkError(String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .invalidCredentials: return "Ungültige Anmeldedaten"
            case .noSession: return "Keine aktive Sitzung"
            case .networkError(let msg): return "Netzwerkfehler: \(msg)"
            case .parseError(let msg): return "Fehler beim Parsen: \(msg)"
            }
        }
    }

    // MARK: - Login

    func login(username: String, password: String) async throws {
        // Clear old cookies for dualis.dhbw.de
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://dualis.dhbw.de")!) {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }

        resetSession()

        guard let url = URL(string: baseURL) else {
            throw DualisError.networkError("Ungültige URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let fields: [(String, String)] = [
            ("usrname", username),
            ("pass", password),
            ("APPNAME", "CampusNet"),
            ("PRGNAME", "LOGINCHECK"),
            ("ARGUMENTS", "clino,usrname,pass,menuno,menu_type,browser,platform"),
            ("clino", "000000000000001"),
            ("menuno", "000324"),
            ("menu_type", "classic"),
            ("browser", ""),
            ("platform", ""),
        ]

        let bodyString = fields.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        // Use per-request delegate to prevent redirect (iOS 15+)
        // This keeps the same session (same cookies!) but blocks the redirect
        // so we can read the REFRESH header from the original response.
        let (data, response) = try await session.data(for: request, delegate: noRedirectDelegate)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DualisError.networkError("Keine HTTP-Antwort erhalten")
        }

        // Successful login: small response (< ~500 bytes) + REFRESH header with token
        // Failed login: large HTML error page
        let statusCode = httpResponse.statusCode

        // A redirect (302) is actually the expected success response
        // Status 200 with large body means error page
        if statusCode == 200 && data.count > 500 {
            throw DualisError.invalidCredentials
        }

        // Extract ARGUMENTS from REFRESH header
        // Format: "0; URL=/scripts/mgrqispi.dll?APPNAME=CampusNet&PRGNAME=STARTPAGE_DISPATCH&ARGUMENTS=-N128917080975804,-N000019,-N000000000000000"
        var args: String?

        // HTTP header names are case-insensitive; try common casings
        for headerKey in ["REFRESH", "refresh", "Refresh"] {
            if let refresh = httpResponse.value(forHTTPHeaderField: headerKey) {
                args = extractArguments(from: refresh)
                if args != nil { break }
            }
        }

        // Fallback: check all headers (some servers use non-standard casing)
        if args == nil {
            for (key, value) in httpResponse.allHeaderFields {
                let keyStr = "\(key)".lowercased()
                let valStr = "\(value)"
                if keyStr == "refresh" || valStr.contains("ARGUMENTS=") {
                    args = extractArguments(from: valStr)
                    if args != nil { break }
                }
            }
        }

        // Also check Location header (in case redirect URL contains the token)
        if args == nil {
            if let location = httpResponse.value(forHTTPHeaderField: "Location") {
                args = extractArguments(from: location)
            }
        }

        guard var sessionArgs = args, !sessionArgs.isEmpty else {
            let headerNames = httpResponse.allHeaderFields.keys.map { "\($0)" }.joined(separator: ", ")
            throw DualisError.parseError("Login-Antwort enthält kein Token. Status: \(statusCode), Header: \(headerNames)")
        }

        // Remove trailing "-N000000000000000" and ensure trailing comma
        // Result format: "-N128917080975804,-N000019,"
        sessionArgs = sessionArgs.replacingOccurrences(of: "-N000000000000000", with: "")
        if !sessionArgs.hasSuffix(",") {
            sessionArgs += ","
        }

        self.authArgs = sessionArgs
    }

    // MARK: - Fetch all grades

    func fetchGrades() async throws -> DualisGradeData {
        guard let authArgs = authArgs else {
            throw DualisError.noSession
        }

        // Step 1: Get course results overview to find semesters
        let overviewURL = "\(baseURL)?APPNAME=CampusNet&PRGNAME=COURSERESULTS&ARGUMENTS=\(authArgs)"
        let overviewHTML = try await fetchPage(overviewURL)

        // Step 2: Parse semester options from <select id="semester">
        let semesterOptions = parseSemesterOptions(from: overviewHTML)

        guard !semesterOptions.isEmpty else {
            // Include a snippet of the HTML for debugging
            let snippet = String(overviewHTML.prefix(300))
            throw DualisError.parseError("Keine Semester gefunden. Seite beginnt mit: \(snippet)")
        }

        // Step 3: Filter to WiSe 2025/26 and newer
        let filtered = semesterOptions.filter { isSemesterRelevant($0.name) }

        if filtered.isEmpty {
            let allNames = semesterOptions.map(\.name).joined(separator: ", ")
            throw DualisError.parseError("Keine relevanten Semester (ab WiSe 25/26). Verfügbar: \(allNames)")
        }

        var semesters: [DualisSemester] = []

        for (semesterName, semesterValue) in filtered {
            let semURL = "\(baseURL)?APPNAME=CampusNet&PRGNAME=COURSERESULTS&ARGUMENTS=\(authArgs)-N\(semesterValue)"
            let semHTML = try await fetchPage(semURL)

            let modules = try await parseModulesFromSemester(html: semHTML)
            let semester = DualisSemester(name: semesterName, modules: modules)
            semesters.append(semester)
        }

        let result = DualisGradeData(semesters: semesters, fetchedAt: Date())

        if result.semesters.flatMap(\.modules).isEmpty {
            throw DualisError.parseError("Keine Module in den Semestern gefunden")
        }

        return result
    }

    // MARK: - Private: Fetching

    private func fetchPage(_ urlString: String) async throws -> String {
        // Do NOT re-encode — the URL is already properly formed
        guard let url = URL(string: urlString) else {
            throw DualisError.networkError("Ungültige URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw DualisError.networkError("HTTP \(httpResponse.statusCode) für \(urlString)")
        }

        // Try UTF-8 first, then ISO Latin 1
        if let html = String(data: data, encoding: .utf8) {
            return html
        }
        if let html = String(data: data, encoding: .isoLatin1) {
            return html
        }
        throw DualisError.parseError("Konnte Seite nicht dekodieren (\(data.count) bytes)")
    }

    // MARK: - Private: Login helpers

    private func extractArguments(from text: String) -> String? {
        guard let range = text.range(of: "ARGUMENTS=") else { return nil }
        let after = text[range.upperBound...]
        let args = after.prefix(while: { !$0.isWhitespace && $0 != "\"" && $0 != "'" && $0 != ">" && $0 != ";" })
        let result = String(args)
        return result.isEmpty ? nil : result
    }

    // MARK: - Private: Semester filter

    private func isSemesterRelevant(_ name: String) -> Bool {
        let lower = name.lowercased()
        let yearPattern = try! NSRegularExpression(pattern: "(\\d{4})", options: [])
        let nsName = name as NSString
        let matches = yearPattern.matches(in: name, range: NSRange(location: 0, length: nsName.length))
        let years = matches.compactMap { Int(nsName.substring(with: $0.range(at: 1))) }
        guard let firstYear = years.first else { return false }

        let isWinter = lower.contains("wi") || lower.contains("winter") || lower.contains("ws")
        if firstYear >= 2026 { return true }
        if firstYear == 2025 && isWinter { return true }
        return false
    }

    // MARK: - Private: Semester parsing

    private func parseSemesterOptions(from html: String) -> [(name: String, value: String)] {
        // First try to find the <select id="semester"> element
        if let selectRange = html.range(of: "<select[^>]*id\\s*=\\s*[\"']?semester[\"']?[^>]*>", options: .regularExpression) {
            let afterSelect = html[selectRange.upperBound...]
            if let endRange = afterSelect.range(of: "</select>", options: .caseInsensitive) {
                let selectHTML = String(afterSelect[..<endRange.lowerBound])
                let options = parseOptionsFromHTML(selectHTML)
                if !options.isEmpty { return options }
            }
        }

        // Fallback: look for any select with semester options
        if let selectRange = html.range(of: "<select[^>]*>", options: .regularExpression) {
            let afterSelect = html[selectRange.upperBound...]
            if let endRange = afterSelect.range(of: "</select>", options: .caseInsensitive) {
                let selectHTML = String(afterSelect[..<endRange.lowerBound])
                let options = parseOptionsFromHTML(selectHTML)
                if !options.isEmpty { return options }
            }
        }

        // Last resort: find options anywhere in the HTML
        return parseOptionsFromHTML(html)
    }

    private func parseOptionsFromHTML(_ html: String) -> [(name: String, value: String)] {
        var results: [(String, String)] = []
        let pattern = try! NSRegularExpression(
            pattern: "<option[^>]*value\\s*=\\s*[\"']?(\\d+)[\"']?[^>]*>([^<]+)</option>",
            options: .caseInsensitive
        )
        let nsHTML = html as NSString
        let matches = pattern.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        for match in matches {
            let value = nsHTML.substring(with: match.range(at: 1))
            let name = nsHTML.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&#160;", with: " ")
            if !value.isEmpty && !name.isEmpty {
                results.append((name, value))
            }
        }
        return results
    }

    // MARK: - Private: Module parsing from semester page

    private func parseModulesFromSemester(html: String) async throws -> [DualisModule] {
        var modules: [DualisModule] = []

        let rowPattern = try! NSRegularExpression(
            pattern: "<tr[^>]*>(.*?)</tr>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let nsHTML = html as NSString
        let rows = rowPattern.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for row in rows {
            let rowHTML = nsHTML.substring(with: row.range)

            // Only process rows with tbdata cells
            guard rowHTML.contains("tbdata") else { continue }
            // Skip header/subhead rows
            if rowHTML.contains("tbsubhead") { continue }

            let cells = parseAllTDCells(from: rowHTML)

            // Module rows should have 5+ cells
            guard cells.count >= 5 else { continue }

            let moduleNumber = cleanHTML(cells[0])
            let name = cleanHTML(cells[1])
            let grade = cleanHTML(cells[2])
            let credits = cleanHTML(cells[3])
            let status = cleanHTML(cells[4])

            // Skip header rows (column titles)
            if moduleNumber.lowercased().contains("nr") && name.lowercased().contains("name") { continue }
            // Skip empty rows
            if name.isEmpty { continue }
            // Skip GPA summary row (no moduleNumber, no credits, but has a grade)
            if moduleNumber.isEmpty && credits.isEmpty && !grade.isEmpty { continue }

            // Extract RESULTDETAILS link for exam details + detail grade
            var exams: [DualisExam] = []
            var detailGrade: String? = nil
            if let detailPath = extractDetailLink(from: rowHTML) {
                let fullURL: String
                if detailPath.starts(with: "http") {
                    fullURL = detailPath
                } else {
                    fullURL = "https://dualis.dhbw.de\(detailPath)"
                }
                do {
                    let result = try await fetchAndParseExamDetails(url: fullURL)
                    exams = result.exams
                    detailGrade = result.overallGrade
                    print("[DUALIS] Module '\(name)': \(exams.count) exams, detailGrade=\(detailGrade ?? "nil")")
                    for exam in exams {
                        print("[DUALIS]   Exam: '\(exam.name)' grade='\(exam.grade)' display='\(exam.displayGrade)'")
                    }
                } catch {
                    print("[DUALIS] ERROR fetching details for '\(name)': \(error)")
                }
            } else {
                print("[DUALIS] No detail link for module '\(name)'")
            }

            let module = DualisModule(
                moduleNumber: moduleNumber,
                name: name,
                grade: grade,
                credits: credits,
                status: status,
                exams: exams,
                detailGrade: detailGrade
            )
            modules.append(module)
        }

        return modules
    }

    // MARK: - Private: Exam detail parsing

    struct ExamParseResult {
        let exams: [DualisExam]
        let overallGrade: String? // From "Gesamt" row
    }

    private func fetchAndParseExamDetails(url: String) async throws -> ExamParseResult {
        let html = try await fetchPage(url)
        print("[DUALIS] Detail page URL: \(url)")
        print("[DUALIS] Detail page length: \(html.count)")
        // Dump first 500 chars for debugging
        print("[DUALIS] Detail page start: \(String(html.prefix(500)))")
        return parseExamDetails(from: html)
    }

    private func parseExamDetails(from html: String) -> ExamParseResult {
        var exams: [DualisExam] = []
        var overallGrade: String? = nil

        print("[DUALIS] parseExamDetails: html length = \(html.count)")

        let examSection = extractExamSection(from: html)
        print("[DUALIS] examSection length = \(examSection.count)")
        // Dump full exam section for debugging (capped at 3000 chars)
        print("[DUALIS] examSection content: \(String(examSection.prefix(3000)))")

        let rowPattern = try! NSRegularExpression(
            pattern: "<tr[^>]*>(.*?)</tr>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )

        let nsHTML = examSection as NSString
        let rows = rowPattern.matches(in: examSection, range: NSRange(location: 0, length: nsHTML.length))
        print("[DUALIS] Found \(rows.count) rows in examSection")

        // First pass: determine Bewertung column index from header row
        var bewertungColIdx: Int? = nil
        for row in rows {
            let rowHTML = nsHTML.substring(with: row.range)
            if rowHTML.contains("tbsubhead") {
                let headerCells = parseTDCellsWithColspan(from: rowHTML)
                for (i, cell) in headerCells.enumerated() {
                    let cleaned = cleanHTML(cell)
                    if cleaned.lowercased().contains("bewertung") {
                        bewertungColIdx = i
                        print("[DUALIS] Found Bewertung at column \(i) (from \(headerCells.count) header cells)")
                        break
                    }
                }
                if bewertungColIdx != nil { break }
            }
        }
        print("[DUALIS] Bewertung column index: \(bewertungColIdx.map(String.init) ?? "NOT FOUND, using fallback")")

        // Also find "Prüfung" column for exam name
        var pruefungColIdx: Int? = nil
        for row in rows {
            let rowHTML = nsHTML.substring(with: row.range)
            if rowHTML.contains("tbsubhead") {
                let headerCells = parseTDCellsWithColspan(from: rowHTML)
                for (i, cell) in headerCells.enumerated() {
                    let cleaned = cleanHTML(cell).lowercased()
                    if cleaned.contains("prüfung") || cleaned.contains("pruefung") || cleaned.contains("pr\u{00FC}fung") {
                        pruefungColIdx = i
                        print("[DUALIS] Found Prüfung at column \(i)")
                        break
                    }
                }
                break
            }
        }

        for (idx, row) in rows.enumerated() {
            let rowHTML = nsHTML.substring(with: row.range)

            // Extract overall grade from "Gesamt" / level02 rows
            if rowHTML.contains("level02") && rowHTML.lowercased().contains("gesamt") {
                let cells = parseTDCellsWithColspan(from: rowHTML)
                print("[DUALIS] Row \(idx): GESAMT row, \(cells.count) cells: \(cells.map { cleanHTML($0) })")
                for cell in cells {
                    let cleaned = cleanHTML(cell)
                    if let gradeMatch = cleaned.range(of: "\\d+,\\d+", options: .regularExpression) {
                        overallGrade = String(cleaned[gradeMatch])
                        break
                    }
                }
                continue
            }

            // Skip non-data rows
            guard rowHTML.contains("tbdata") else { continue }
            if rowHTML.contains("tbsubhead") { continue }
            if rowHTML.contains("level01") || rowHTML.contains("level02") { continue }

            let cells = parseTDCellsWithColspan(from: rowHTML)
            let cleanedCells = cells.map { cleanHTML($0) }
            print("[DUALIS] Row \(idx): tbdata, \(cells.count) cells: \(cleanedCells)")

            guard cells.count >= 3 else { continue }

            // Determine exam name: use header-detected column, or find first non-empty meaningful cell
            let nameIdx = pruefungColIdx ?? findExamNameIndex(in: cleanedCells)
            guard let nIdx = nameIdx, nIdx < cleanedCells.count else { continue }
            let examName = cleanedCells[nIdx]
            if examName.isEmpty { continue }

            // Determine grade: use header-detected Bewertung column, or scan for numeric value
            var grade = ""
            if let bIdx = bewertungColIdx, bIdx < cleanedCells.count {
                grade = cleanedCells[bIdx]
            }
            // If Bewertung column was empty, scan all cells after name for a numeric grade
            if grade.isEmpty {
                grade = findGradeValue(in: cleanedCells, afterIndex: nIdx)
            }

            print("[DUALIS] => Exam: '\(examName)' grade='\(grade)'")
            exams.append(DualisExam(name: examName, grade: grade, status: ""))
        }

        print("[DUALIS] parseExamDetails result: \(exams.count) exams, overallGrade=\(overallGrade ?? "nil")")
        return ExamParseResult(exams: exams, overallGrade: overallGrade)
    }

    /// Find the index of the exam name cell — first cell with meaningful text (not a date, not a semester, not empty)
    private func findExamNameIndex(in cells: [String]) -> Int? {
        for (i, cell) in cells.enumerated() {
            if cell.isEmpty { continue }
            // Skip cells that look like semester labels (WiSe/SoSe + year)
            if cell.contains("WiSe") || cell.contains("SoSe") || cell.contains("wise") || cell.contains("sose") { continue }
            // Skip cells that look like dates (dd.mm.yyyy)
            if cell.range(of: "^\\d{2}\\.\\d{2}\\.\\d{4}$", options: .regularExpression) != nil { continue }
            // Skip cells that are just numbers (attempt number like "1")
            if cell.range(of: "^\\d{1,2}$", options: .regularExpression) != nil { continue }
            // Skip cells that look like a grade or points (e.g. "2,9" or "42,0")
            if cell.range(of: "^\\d+,\\d+$", options: .regularExpression) != nil { continue }
            // This cell has meaningful text — it's the exam name
            return i
        }
        return nil
    }

    /// Find a grade/points value in cells after the name column
    private func findGradeValue(in cells: [String], afterIndex: Int) -> String {
        // First pass: look for numeric grades
        for i in (afterIndex + 1)..<cells.count {
            let cell = cells[i]
            if cell.isEmpty { continue }
            // Match grade patterns: "2,9", "42,0", "38,5", "76,0"
            if cell.range(of: "^\\s*\\d+,\\d+\\s*$", options: .regularExpression) != nil {
                return cell.trimmingCharacters(in: .whitespaces)
            }
        }
        // Second pass: look for "noch nicht gesetzt" or similar status text
        for i in (afterIndex + 1)..<cells.count {
            let cell = cells[i]
            if cell.lowercased().contains("nicht gesetzt") || cell.lowercased().contains("nicht bestanden") {
                return cell.trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    /// Extract the exam section of the HTML — from "Bewertung" header to "Zugehörige" or end
    /// This avoids regex table matching which fails with nested tables
    private func extractExamSection(from html: String) -> String {
        // Find start: "Bewertung" text (in exam table header)
        let startMarkers = ["Bewertung", "tbsubhead"]
        var startIdx = html.startIndex

        for marker in startMarkers {
            if let range = html.range(of: marker, options: .caseInsensitive) {
                // Go back to find the <table before this
                let beforeMarker = html[html.startIndex..<range.lowerBound]
                if let tableStart = beforeMarker.range(of: "<table", options: [.backwards, .caseInsensitive]) {
                    startIdx = tableStart.lowerBound
                    break
                }
            }
        }

        // Find end: "Zugehörige Bausteine" or next <h1> or <h2> after start
        var endIdx = html.endIndex
        _ = html[startIdx...]

        let endMarkers = ["Zugehörige", "<h1", "<h2"]
        for marker in endMarkers {
            // Skip if marker is at the very start
            let afterStart = html[html.index(startIdx, offsetBy: min(50, html.distance(from: startIdx, to: html.endIndex)))...]
            if let range = afterStart.range(of: marker, options: .caseInsensitive) {
                if range.lowerBound < endIdx {
                    endIdx = range.lowerBound
                }
            }
        }

        return String(html[startIdx..<endIdx])
    }

    /// Parse <td> cells and expand colspan so output always matches visual column count
    private func parseTDCellsWithColspan(from html: String) -> [String] {
        var cells: [String] = []
        let tdPattern = try! NSRegularExpression(
            pattern: "<td([^>]*)>(.*?)</td>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let colspanPattern = try! NSRegularExpression(
            pattern: "colspan\\s*=\\s*[\"']?(\\d+)[\"']?",
            options: .caseInsensitive
        )

        let nsHTML = html as NSString
        let matches = tdPattern.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for match in matches {
            let attrs = nsHTML.substring(with: match.range(at: 1))
            let content = nsHTML.substring(with: match.range(at: 2))

            cells.append(content)

            // If colspan > 1, add empty cells to fill the gap
            let nsAttrs = attrs as NSString
            if let colMatch = colspanPattern.firstMatch(in: attrs, range: NSRange(location: 0, length: nsAttrs.length)) {
                let colspanStr = nsAttrs.substring(with: colMatch.range(at: 1))
                if let colspan = Int(colspanStr), colspan > 1 {
                    for _ in 1..<colspan {
                        cells.append("") // padding cell
                    }
                }
            }
        }
        return cells
    }

    // MARK: - Private: HTML helpers

    private func parseAllTDCells(from html: String) -> [String] {
        var cells: [String] = []
        let tdPattern = try! NSRegularExpression(
            pattern: "<td[^>]*>(.*?)</td>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let nsHTML = html as NSString
        let matches = tdPattern.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        for match in matches {
            cells.append(nsHTML.substring(with: match.range(at: 1)))
        }
        return cells
    }

    private func extractDetailLink(from html: String) -> String? {
        // Try multiple patterns — some pages use single quotes or no quotes
        let patterns = [
            "href\\s*=\\s*\"([^\"]*RESULTDETAILS[^\"]*)\"",
            "href\\s*=\\s*'([^']*RESULTDETAILS[^']*)'",
            "href\\s*=\\s*([^\\s>]*RESULTDETAILS[^\\s>]*)"
        ]
        for pat in patterns {
            let linkPattern = try! NSRegularExpression(pattern: pat, options: .caseInsensitive)
            let nsHTML = html as NSString
            if let match = linkPattern.firstMatch(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
                let link = nsHTML.substring(with: match.range(at: 1))
                    .replacingOccurrences(of: "&amp;", with: "&")
                print("[DUALIS] Found detail link: \(link)")
                return link
            }
        }
        return nil
    }

    private func cleanHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&#160;", with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
