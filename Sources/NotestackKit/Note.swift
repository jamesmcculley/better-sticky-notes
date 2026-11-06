import Foundation
import SwiftUI

/// One note = one Markdown file in the notes directory (NotesStore). `id` is the filename
/// (stable across reads, which is what `PaneID.day(id:)`/`.week(id:)` key off -- ADR 0019; a day
/// note's id is its own date, `yyyy-MM-dd.md`, see `NoteCadence`). `color` comes from an optional
/// `color:` frontmatter field (ADR 0008) -- nil means "no color set," rendered as the original
/// neutral `.regularMaterial` look.
struct Note: Identifiable {
    let id: String // filename, e.g. "Today.md"
    var title: String
    var items: [NoteItem]
    var color: NoteColor?
}

/// A sticky note's color -- a small, fixed palette rather than open-ended, to keep the
/// frontmatter and the "Color" menu both simple. `rawValue` is exactly what's written to the
/// `color:` frontmatter field, unchanged since before the cyberpunk redesign (ADR 0020) so
/// existing notes' `color: yellow` etc. keeps meaning the same thing -- only what each name
/// *renders as* changed, from pastel paper to a neon accent glow.
enum NoteColor: String, CaseIterable, Equatable {
    case yellow, pink, blue, green, purple, gray

    var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// Fixed, not system-adaptive -- same reasoning as `Theme`'s doc comment, just per-color
    /// instead of a single default. No longer a pane *fill* (ADR 0020 made every pane's fill a
    /// constant dark glass, `Theme.paneBase`) -- this is the accent/glow/border color layered on
    /// top of that fill, picked out of a neon palette instead of pastel paper.
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

/// One checklist-shaped line: a checklist item (`- [ ] text` / `- [x] text`), a task (`- ( ) text`
/// / `- (x) text` -- same idea, a different glyph), or a plain bullet point (`- text`, no
/// brackets at all -- not toggleable). `lineIndex` is the item's position in the file at the time
/// it was read -- NotesStore re-reads fresh before every toggle, so a stale index never silently
/// edits the wrong line. `doneDate` (ADR 0019) comes from a trailing `@done(yyyy-MM-dd)` tag,
/// stamped automatically on completion and cleared on un-completion -- nil for anything not done,
/// and (gracefully) for anything checked off before this existed.
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
