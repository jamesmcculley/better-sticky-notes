import Foundation
import SwiftUI

struct Note: Identifiable {
    let id: String // filename, e.g. "Today.md"
    var title: String
    var items: [NoteItem]
    var color: NoteColor?
}

enum NoteColor: String, CaseIterable, Equatable {
    case yellow, pink, blue, green, purple, gray

    var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    var swiftUIColor: Color {
        switch self {
        case .yellow: return Color(red: 1.0, green: 0.80, blue: 0.0) // amber
        case .pink: return Color(red: 1.0, green: 0.0, blue: 0.55) // magenta
        case .blue: return Color(red: 0.0, green: 0.85, blue: 1.0) // electric cyan
        case .green: return Color(red: 0.45, green: 1.0, blue: 0.35) // acid green
        case .purple: return Color(red: 0.68, green: 0.32, blue: 1.0) // violet
        case .gray: return Color(red: 0.68, green: 0.74, blue: 0.82) // cool steel
        }
    }
}

struct NoteItem: Identifiable, Equatable {
    let id: String
    var title: String
    var done: Bool
    let lineIndex: Int
    var kind: ItemKind
    var doneDate: Date?
}

enum ItemKind: String, Equatable {
    case checklist
    case task
    case bullet
}
