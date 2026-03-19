import Foundation

// MARK: - Exam detail (Teilleistung)

struct DualisExam: Identifiable, Codable, Hashable {
    var id = UUID()
    let name: String          // e.g. "Klausur (100%)", "Einführung BWL - Huf - 80"
    let grade: String         // e.g. "2,9" or "42,0" (points)
    let status: String

    /// Extract max points from name, e.g. "Einführung BWL - Huf - 80" → 80
    var maxPoints: Int? {
        // Look for last number after a dash: "- 80" or "- 40"
        let parts = name.components(separatedBy: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        if let last = parts.last, let val = Int(last) {
            return val
        }
        return nil
    }

    /// The achieved points as a number (e.g. "42,0" → 42)
    var pointsValue: Double? {
        let cleaned = grade.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    /// Formatted display: "42/80" or "38,5/40" or "2,9" or "–"
    var displayGrade: String {
        if grade.isEmpty { return "–" }
        if let points = pointsValue, points > 5, let max = maxPoints {
            // Show as "42/80" — use original grade string for the numerator to preserve decimals
            let pointsStr = grade.trimmingCharacters(in: .whitespaces)
            // Remove trailing ",0" for clean display (42,0 → 42)
            let cleanPoints = pointsStr.hasSuffix(",0")
                ? String(pointsStr.dropLast(2))
                : pointsStr
            return "\(cleanPoints)/\(max)"
        }
        return grade
    }
}

// MARK: - Module (Fach)

struct DualisModule: Identifiable, Codable, Hashable {
    var id = UUID()
    let moduleNumber: String  // e.g. "W3BW_101"
    let name: String          // e.g. "Grundlagen der Betriebswirtschaftslehre"
    let grade: String         // Grade from semester overview or empty
    let credits: String       // ECTS credits
    let status: String        // "bestanden", "noch nicht gesetzt" etc.
    let exams: [DualisExam]   // Teilleistungen from detail page
    var detailGrade: String?  // Grade from detail page (Gesamt row) — fallback

    /// Effective grade: use semester grade if numeric, else detailGrade, else computed from exams
    var effectiveGrade: String {
        if gradeValue != nil { return grade }
        if let dg = detailGrade, !dg.isEmpty {
            let cleaned = dg.replacingOccurrences(of: ",", with: ".")
            if Double(cleaned) != nil { return dg }
        }
        // Fallback: compute from available exam grades
        if let computed = computedGradeFromExams {
            return String(format: "%.1f", computed).replacingOccurrences(of: ".", with: ",")
        }
        return grade
    }

    var gradeValue: Double? {
        let cleaned = grade.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    /// Grade value including detailGrade fallback, then exam-computed fallback
    var effectiveGradeValue: Double? {
        if let v = gradeValue { return v }
        if let dg = detailGrade {
            let cleaned = dg.replacingOccurrences(of: ",", with: ".")
            if let v = Double(cleaned) { return v }
        }
        // Last fallback: compute from available sub-exam grades (values ≤ 5.0)
        return computedGradeFromExams
    }

    /// Average grade computed from sub-exams that have actual grades (≤ 5.0, not points)
    var computedGradeFromExams: Double? {
        let examGrades = exams.compactMap { exam -> Double? in
            guard let val = exam.pointsValue, val > 0, val <= 5.0 else { return nil }
            return val
        }
        guard !examGrades.isEmpty else { return nil }
        return examGrades.reduce(0.0, +) / Double(examGrades.count)
    }

    var creditsValue: Double? {
        let cleaned = credits.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }
}

// MARK: - Semester

struct DualisSemester: Identifiable, Codable, Hashable {
    var id = UUID()
    let name: String
    let modules: [DualisModule]

    var gpa: Double? {
        let graded = modules.filter { $0.effectiveGradeValue != nil && $0.creditsValue != nil }
        guard !graded.isEmpty else { return nil }
        let weightedSum = graded.reduce(0.0) { $0 + ($1.effectiveGradeValue! * $1.creditsValue!) }
        let totalCredits = graded.reduce(0.0) { $0 + $1.creditsValue! }
        guard totalCredits > 0 else { return nil }
        return weightedSum / totalCredits
    }
}

// MARK: - Complete grade data

struct DualisGradeData: Codable {
    let semesters: [DualisSemester]
    let fetchedAt: Date

    /// Deduplicated modules — each moduleNumber only once (latest semester wins)
    var uniqueModules: [DualisModule] {
        var seen: [String: DualisModule] = [:]
        // Iterate semesters in order; later entries overwrite earlier ones
        for module in semesters.flatMap(\.modules) {
            let key = module.moduleNumber.isEmpty ? module.name : module.moduleNumber
            seen[key] = module
        }
        return Array(seen.values)
    }

    var overallGPA: Double? {
        let graded = uniqueModules.filter { $0.effectiveGradeValue != nil && $0.creditsValue != nil }
        guard !graded.isEmpty else { return nil }
        let weightedSum = graded.reduce(0.0) { $0 + ($1.effectiveGradeValue! * $1.creditsValue!) }
        let totalCredits = graded.reduce(0.0) { $0 + $1.creditsValue! }
        guard totalCredits > 0 else { return nil }
        return weightedSum / totalCredits
    }

    var simpleAverage: Double? {
        let allGrades = uniqueModules.compactMap(\.effectiveGradeValue)
        guard !allGrades.isEmpty else { return nil }
        return allGrades.reduce(0.0, +) / Double(allGrades.count)
    }

    var totalCredits: Double {
        uniqueModules
            .filter { $0.effectiveGradeValue != nil }
            .compactMap(\.creditsValue)
            .reduce(0, +)
    }
}
