import SwiftUI

/// Liefert eine deterministische, fachspezifische Farbe aus dem Fachnamen.
/// Gleiche Namen → gleiche Farbe, auch zwischen Stundenplan und Fortschritts-Tab.
func colorForString(_ str: String, colorScheme: ColorScheme) -> Color {
    var hash = 0
    for c in str.unicodeScalars { hash = Int(c.value) &+ ((hash &<< 5) &- hash) }
    let hue = Double(abs(hash) % 360) / 360.0
    let sat = colorScheme == .dark ? 0.60 : 0.78
    let bri = colorScheme == .dark ? 0.88 : 0.52
    return Color(hue: hue, saturation: sat, brightness: bri)
}

/// Formatiert Stunden als "2h 30min", "2h" oder "45min".
func formatHours(_ hours: Double) -> String {
    let totalMinutes = Int(hours * 60)
    let h = totalMinutes / 60
    let m = totalMinutes % 60
    if h > 0 && m > 0 { return "\(h)h \(m)min" }
    if h > 0 { return "\(h)h" }
    return "\(m)min"
}
