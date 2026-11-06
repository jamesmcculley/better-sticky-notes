import Foundation

/// Standalone, local, no network at all: one note = one Markdown file in `~/Documents/Notestack/`.
/// Deliberately plain text (optional `---`-delimited frontmatter, `# Title` heading, checklist/
/// task/bullet lines) -- editable in any text editor, readable as an Obsidian vault, no schema, no
/// migrations. Watching is a plain timer-based poll of the directory, not FSEvents/DispatchSource:
/// this is local disk I/O (reading a handful of tiny files every couple seconds costs nothing),
/// and a simple, well-understood primitive beats a fancier API that's hard to verify without a GUI
/// session to drive real file edits against (the same lesson the Tauri WebView-polling bug taught).
///
/// Multiple stacks (ADR 0003): "not every sticky ever created will be in the main stack." A stack
/// is just a directory -- the root (`mainStack`) holds loose .md files directly, and every
/// *subdirectory* of the root is one more named stack. Still the underlying mechanism Daily/
/// Weekly notes are built on (ADR 0019): "Daily" and "Weekly" are just two more stack directories,
/// each holding one date-named file per day/week. `createStack`/`createNote`/`moveNote` aren't
/// used by the current UI (which only ever targets Daily/Weekly directly) but are kept as general,
/// already-tested primitives rather than deleted -- they're correct, harmless, and were real
/// scaffolding for the stacks/arbitrary-notes model ADR 0018 replaced.
final class NotesStore {
    static let mainStack = "Main"

    let root: URL

    /// `root` is injectable so tests can point this at a throwaway temp folder instead of the
    /// real `~/Documents/Notestack/` -- the production entry point (Entry.swift/AppDelegate)
    /// always uses the no-argument convenience initializer below.
    init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    static var defaultRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notestack", isDirectory: true)
    }

    static func configuredRoot(defaults: UserDefaults = .standard) -> URL {
        guard let path = defaults.string(forKey: "notestack.notesFolder"), !path.isEmpty else {
            return defaultRoot
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Validate before committing a preference; never migrate or merge the user's files.
    static func selectRoot(_ url: URL, defaults: UserDefaults = .standard) throws {
        let root = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let probe = root.appendingPathComponent(".notestack-write-check-" + UUID().uuidString)
        try Data().write(to: probe, options: .withoutOverwriting)
        try FileManager.default.removeItem(at: probe)
        // Check existing application subfolders too, before switching the active store.
        for name in ["Daily", "Weekly", "Logbook", ".trash", ".history"] {
            let child = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: child.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue, FileManager.default.isWritableFile(atPath: child.path) else {
                    throw CocoaError(.fileWriteNoPermission)
                }
            }
        }
        defaults.set(root.path, forKey: "notestack.notesFolder")
    }

    convenience init() {
        self.init(root: Self.configuredRoot())
    }

    private var pollTask: Task<Void, Never>?

    /// The last content this instance trusts for each note it's written or reconciled, keyed
    /// `"stack/noteID"` -- how `reconcileExternalChanges` (ADR 0021) tells "we wrote this
    /// ourselves" apart from "something else changed this file" without needing any signal from
    /// whatever did the other writing. Every write method in this class funnels through
    /// `writeAndTrack`, which updates this immediately, so the next reconciliation pass sees no
    /// diff for a change this app made itself.
    private var lastKnownContent: [String: String] = [:]

    func startWatching(stack: String, interval: TimeInterval = 2, onChange: @escaping ([Note]) -> Void) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                if let notes = self?.loadNotes(stack: stack) { onChange(notes) }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopWatching() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Stacks

    private func directory(for stack: String) -> URL {
        stack == Self.mainStack ? root : root.appendingPathComponent(stack, isDirectory: true)
    }

    /// "Main" first, then every subdirectory of the root, alphabetically.
    func listStacks() -> [String] {
        let subdirs = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]))?
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map(\.lastPathComponent)
            .sorted() ?? []
        return [Self.mainStack] + subdirs
    }

    @discardableResult
    func createStack(name: String) -> String {
        let safeName = name.isEmpty ? "New Stack" : name
        try? FileManager.default.createDirectory(at: directory(for: safeName), withIntermediateDirectories: true)
        return safeName
    }

    // MARK: - Reading

    func loadNotes(stack: String) -> [Note] {
        let dir = directory(for: stack)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { parse($0) }
    }

    private func parse(_ url: URL) -> Note? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: .newlines)
        let color = parseFrontmatter(lines)["color"].flatMap(NoteColor.init(rawValue:))

        var title = url.deletingPathExtension().lastPathComponent
        var items: [NoteItem] = []
        for index in frontmatterEnd(lines)..<lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                title = String(trimmed.dropFirst(2))
            } else if let item = parseChecklistLine(trimmed, lineIndex: index) {
                items.append(item)
            }
        }
        return Note(id: url.lastPathComponent, title: title, items: items, color: color)
    }

    /// Checklist (`- [ ] `/`- [x] `), task (`- ( ) `/`- (x) ` -- same idea, a circle instead of a
    /// square), or a plain bullet point (`- `, nothing after the dash to mark it as either of the
    /// above -- never toggleable). Checked first, in that order, since a task/checklist line also
    /// happens to start with `- `. A done line's trailing `@done(yyyy-MM-dd)` tag (ADR 0019) is
    /// split off into `doneDate`, not left as part of the visible title.
    private func parseChecklistLine(_ line: String, lineIndex: Int) -> NoteItem? {
        for (marker, done) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true)] {
            if line.hasPrefix(marker) {
                let (title, doneDate) = Self.extractDoneDate(String(line.dropFirst(marker.count)))
                return NoteItem(
                    id: "\(lineIndex)", title: title, done: done,
                    lineIndex: lineIndex, kind: .checklist, doneDate: doneDate
                )
            }
        }
        for (marker, done) in [("- ( ) ", false), ("- (x) ", true), ("- (X) ", true)] {
            if line.hasPrefix(marker) {
                let (title, doneDate) = Self.extractDoneDate(String(line.dropFirst(marker.count)))
                return NoteItem(
                    id: "\(lineIndex)", title: title, done: done,
                    lineIndex: lineIndex, kind: .task, doneDate: doneDate
                )
            }
        }
        if line.hasPrefix("- ") {
            return NoteItem(
                id: "\(lineIndex)", title: String(line.dropFirst(2)), done: false,
                lineIndex: lineIndex, kind: .bullet, doneDate: nil
            )
        }
        return nil
    }

    // MARK: - Frontmatter

    /// A tiny `---`-delimited `key: value` block at the top of the file -- not a general YAML
    /// parser, just enough structure to store a note's color (ADR 0008) alongside the title and
    /// items. Unknown keys round-trip unharmed: `setColor` only ever touches the `color` key,
    /// never rewrites the whole block from scratch, so a key some future feature (or a person
    /// hand-editing the file) adds survives a color change untouched.
    private func parseFrontmatter(_ lines: [String]) -> [String: String] {
        let end = frontmatterEnd(lines)
        guard end > 1 else { return [:] }
        var fields: [String: String] = [:]
        for line in lines[1..<(end - 1)] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        return fields
    }

    /// The index of the first line *after* a leading frontmatter block, or 0 if there isn't one.
    /// Everything else (heading/item parsing, where to insert a missing heading) treats this as
    /// "where the real body starts," so it never mistakes a frontmatter line for a title/item or
    /// inserts a new heading ahead of the frontmatter block.
    private func frontmatterEnd(_ lines: [String]) -> Int {
        guard lines.first == "---", let closing = lines.dropFirst().firstIndex(of: "---") else { return 0 }
        return closing + 1
    }

    private func writeFrontmatter(_ fields: [String: String], into lines: inout [String]) {
        lines.removeSubrange(0..<frontmatterEnd(lines))
        guard !fields.isEmpty else { return }
        var block = ["---"]
        block.append(contentsOf: fields.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" })
        block.append("---")
        lines.insert(contentsOf: block, at: 0)
    }

    // MARK: - Done dates (ADR 0019)

    /// Local completion time to seconds; older date-only tags remain readable.
    private static let doneDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    private static let legacyDoneDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    private static let doneTagPrefix = " @done("

    /// Splits a trailing `" @done(yyyy-MM-dd)"` tag off the end of `text`, if present. The
    /// `@done(...)` convention echoes TaskPaper's own tag for the same idea, so it reads
    /// naturally to anyone who's seen that format, and is still just plain text to Obsidian
    /// either way.
    private static func extractDoneDate(_ text: String) -> (title: String, doneDate: Date?) {
        guard text.hasSuffix(")"),
              let tagStart = text.range(of: doneTagPrefix, options: .backwards)?.lowerBound
        else { return (text, nil) }
        let dateString = String(text[text.index(tagStart, offsetBy: doneTagPrefix.count)..<text.index(before: text.endIndex)])
        guard let date = (dateString.count == 10 ? legacyDoneDateFormatter : doneDateFormatter).date(from: dateString) else { return (text, nil) }
        return (String(text[text.startIndex..<tagStart]), date)
    }

    private static func appendDoneDate(_ text: String, _ date: Date) -> String {
        text + doneTagPrefix + doneDateFormatter.string(from: date) + ")"
    }

    private static func stripDoneDate(_ text: String) -> String {
        extractDoneDate(text).title
    }

    // MARK: - Writing

    /// Writes `content` to the given note's file and records it as this instance's trusted
    /// version of that file (ADR 0021) -- every write method below goes through this one spot
    /// for exactly that reason. A write that bypassed it would get spuriously snapshotted the
    /// next time its stack is reconciled, as if an outside edit had made it.
    @discardableResult
    private func writeAndTrack(stack: String, noteID: String, content: String) -> Bool {
        let url = directory(for: stack).appendingPathComponent(noteID)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            lastKnownContent["\(stack)/\(noteID)"] = content
            return true
        } catch {
            return false
        }
    }

    /// Resolves a rendered item only when its line still represents that same item.
    /// A line index alone is unsafe after an external edit inserts or removes lines.
    private func currentLineIndex(for item: NoteItem, in lines: [String]) -> Int? {
        guard lines.indices.contains(item.lineIndex),
              let current = parseChecklistLine(lines[item.lineIndex].trimmingCharacters(in: .whitespaces), lineIndex: item.lineIndex),
              current.id == item.id, current.title == item.title, current.kind == item.kind,
              current.done == item.done, current.doneDate == item.doneDate else { return nil }
        return item.lineIndex
    }

    /// Re-reads the file fresh before toggling -- `item.lineIndex` is only ever trusted against
    /// the content it was parsed from a moment ago, never a cached copy that might have since
    /// been hand-edited. Bullets aren't toggleable at all (they have no done/not-done state).
    ///
    /// A plain, reversible, in-place toggle for every kind (ADR 0019) -- completing something
    /// stamps today's date as a trailing `@done(...)` tag in place; un-completing strips it back
    /// off. Either way the item stays exactly where it is -- every daily note is its own
    /// permanent historical record, so there's nowhere more "complete" for a finished task to
    /// physically move to.
    ///
    /// Completion copies to Logbook; reopening removes one matching completion.
    func toggleItem(stack: String, noteID: String, noteTitle: String, item: NoteItem) {
        guard item.kind != .bullet else { return }
        let url = directory(for: stack).appendingPathComponent(noteID)
        guard var lines = (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: .newlines),
              let index = currentLineIndex(for: item, in: lines) else { return }
        let line = lines[index]
        guard let current = parseChecklistLine(line.trimmingCharacters(in: .whitespaces), lineIndex: index) else { return }

        var logbookAddition: (title: String, date: Date)?
        var logbookRemoval: (title: String, date: Date)?
        if !current.done {
            for (from, to) in [("- [ ] ", "- [x] "), ("- ( ) ", "- (x) ")] where line.hasPrefix(from) {
                let rest = Self.stripDoneDate(String(line.dropFirst(from.count)))
                let date = Date()
                lines[index] = to + Self.appendDoneDate(rest, date)
                logbookAddition = ("\(rest) — \(noteTitle)", date)
                break
            }
        } else {
            let flips: [(String, String)] = [
                ("- [x] ", "- [ ] "), ("- [X] ", "- [ ] "), ("- (x) ", "- ( ) "), ("- (X) ", "- ( ) "),
            ]
            for (from, to) in flips where line.hasPrefix(from) {
                let rest = Self.stripDoneDate(String(line.dropFirst(from.count)))
                lines[index] = to + rest
                if let date = item.doneDate { logbookRemoval = (item.title, date) }
                break
            }
        }
        guard writeAndTrack(stack: stack, noteID: noteID, content: lines.joined(separator: "\n")) else { return }
        if let logbookAddition {
            appendToLogbook(Self.logbookLine(title: logbookAddition.title, date: logbookAddition.date, kind: item.kind))
        }
        if let logbookRemoval {
            removeFromLogbook(title: logbookRemoval.title, noteTitle: noteTitle, date: logbookRemoval.date)
        }
    }

    /// Updates the `# Heading` line in place -- the filename (== `Note.id`) never changes, so a
    /// rename can't collide with another note or invalidate anything keyed by id elsewhere.
    /// Inserts a heading right after any frontmatter block if the note didn't have one yet
    /// (title was falling back to the filename) -- never at absolute line 0, which would land
    /// the heading *inside* the frontmatter block.
    func renameNote(stack: String, noteID: String, title: String) {
        let url = directory(for: stack).appendingPathComponent(noteID)
        guard var lines = (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: .newlines)
        else { return }
        if let headingIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("# ") }) {
            lines[headingIndex] = "# \(title)"
        } else {
            lines.insert("# \(title)", at: frontmatterEnd(lines))
        }
        writeAndTrack(stack: stack, noteID: noteID, content: lines.joined(separator: "\n"))
    }

    /// Appends one new item, inferring its kind from a typed shorthand prefix: `()` for a task,
    /// `[]` for a checklist, anything else for a plain bullet point -- "Add item…" accepts the
    /// same shorthand the file format itself uses (ADR 0007), so there's no separate kind-picker
    /// control to build. Trims trailing blank lines first so repeated adds don't pile up empty
    /// lines between items over time.
    func addItem(stack: String, noteID: String, text: String) {
        let url = directory(for: stack).appendingPathComponent(noteID)
        guard var lines = (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: .newlines)
        else { return }
        while lines.last?.isEmpty == true { lines.removeLast() }
        lines.append(Self.markdownLine(for: text))
        writeAndTrack(stack: stack, noteID: noteID, content: lines.joined(separator: "\n") + "\n")
    }

    /// Replaces an existing item's whole line, inferring its (possibly new) kind from the same
    /// typed shorthand `addItem` uses -- editing "() call mom" down to "[] call mom" converts a
    /// task into a checklist item, not just a typo fix; that's a feature, not a surprise, since
    /// the edit field shows the shorthand form to begin with (`PaneView.shorthand(for:)`, which
    /// includes any `@done(...)` tag too, so a typo fix on an already-done item doesn't silently
    /// drop its done-date). Same re-read-fresh-first reasoning as `toggleItem` -- `item.lineIndex`
    /// is only ever trusted against the content it was parsed from a moment ago.
    func editItem(stack: String, noteID: String, item: NoteItem, text: String) {
        let url = directory(for: stack).appendingPathComponent(noteID)
        guard var lines = (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: .newlines),
              let index = currentLineIndex(for: item, in: lines) else { return }
        let editedLine = Self.markdownLine(for: text)
        lines[index] = editedLine
        guard writeAndTrack(stack: stack, noteID: noteID, content: lines.joined(separator: "\n")) else { return }
        guard item.done, let oldDate = item.doneDate else { return }
        let newItem = parseChecklistLine(editedLine, lineIndex: index)
        if let newItem, newItem.done, let doneDate = newItem.doneDate {
            replaceLogbookEntry(
                title: item.title, noteTitle: parse(url)?.title ?? noteID,
                date: oldDate,
                with: Self.logbookLine(title: newItem.title + " — " + (parse(url)?.title ?? noteID), date: doneDate, kind: newItem.kind)
            )
        } else {
            removeFromLogbook(title: item.title, noteTitle: parse(url)?.title ?? noteID, date: oldDate)
        }
    }

    /// Removes one item's line -- but stashes a copy in Trash first (ADR 0011), so it's
    /// recoverable later even after quitting the app, not just via the in-session ⌘Z undo.
    /// Same re-read-fresh-first reasoning as `toggleItem`/`editItem` for `item.lineIndex`. Returns
    /// the Trash entry's id (for `AppController`'s one-level ⌘Z undo), or nil if the item was
    /// already gone.
    @discardableResult
    func deleteItem(stack: String, noteID: String, noteTitle: String, item: NoteItem) -> String? {
        let url = directory(for: stack).appendingPathComponent(noteID)
        guard var lines = (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: .newlines),
              let index = currentLineIndex(for: item, in: lines) else { return nil }
        let removedLine = lines[index]
        guard let entryID = moveToTrash(stack: stack, noteID: noteID, noteTitle: noteTitle, line: removedLine) else { return nil }
        lines.remove(at: index)
        guard writeAndTrack(stack: stack, noteID: noteID, content: lines.joined(separator: "\n")) else {
            emptyTrashEntry(entryID)
            return nil
        }
        return entryID
    }

    /// Reorders items to match `newOrder` (a list of item ids, i.e. the `lineIndex` each had at
    /// the moment the drag started). Re-reads fresh first (same reasoning as every other write
    /// here) and re-identifies each item's *current* line by that id, so a stale id from a drag
    /// that started before some other change landed just gets skipped rather than moving the
    /// wrong line. Removes every current item line, then reinserts them in the requested order
    /// starting at the position the first one used to occupy -- non-item lines (title,
    /// frontmatter, blank lines) stay exactly where they were, nothing is renumbered around them.
    /// Any current item missing from `newOrder` (shouldn't happen, but a dropped id from the UI
    /// shouldn't silently delete it) is appended at the end instead of being lost.
    func reorderItems(stack: String, noteID: String, newOrder: [String]) {
        let url = directory(for: stack).appendingPathComponent(noteID)
        guard var lines = (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: .newlines)
        else { return }

        var lineByID: [String: String] = [:]
        var itemIndices: [Int] = []
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if parseChecklistLine(trimmed, lineIndex: index) != nil {
                lineByID["\(index)"] = lines[index]
                itemIndices.append(index)
            }
        }
        guard let insertAt = itemIndices.first else { return }

        for index in itemIndices.sorted(by: >) { lines.remove(at: index) } // back to front: indices don't shift

        let requestedIDs = Set(newOrder)
        let reordered = newOrder.compactMap { lineByID[$0] }
        let leftover = itemIndices.map { "\($0)" }.filter { !requestedIDs.contains($0) }.compactMap { lineByID[$0] }
        lines.insert(contentsOf: reordered + leftover, at: min(insertAt, lines.count))

        writeAndTrack(stack: stack, noteID: noteID, content: lines.joined(separator: "\n"))
    }

    /// `()`/`[]` shorthand -> the matching Markdown line, with the shorthand stripped from the
    /// title. `(x)`/`[x]` (done) is recognized too, not just the empty/unchecked form -- editing
    /// an existing *done* item pre-fills the field with `(x)`/`[x]` (`PaneView.shorthand(for:)`),
    /// and without this, resubmitting it unchanged would silently uncheck it. Anything else
    /// trailing in the typed text (an `@done(...)` tag, a `#tag`) just rides along as part of the
    /// title verbatim -- this never needs to know about either. Exposed at file scope (via
    /// `Self.`) so `notestackChecks` can verify the shorthand parsing directly without
    /// round-tripping through a file.
    static func markdownLine(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("(x)") || trimmed.hasPrefix("(X)") {
            return "- (x) " + String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.hasPrefix("()") {
            return "- ( ) " + String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.hasPrefix("[x]") || trimmed.hasPrefix("[X]") {
            return "- [x] " + String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.hasPrefix("[]") {
            return "- [ ] " + String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return "- " + trimmed
    }

    /// Sets (or clears, with `color: nil`) a note's color -- see `parseFrontmatter`/
    /// `writeFrontmatter` above for why this only ever touches the `color` key.
    func setColor(stack: String, noteID: String, color: NoteColor?) {
        let url = directory(for: stack).appendingPathComponent(noteID)
        guard var lines = (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: .newlines)
        else { return }
        var fields = parseFrontmatter(lines)
        if let color { fields["color"] = color.rawValue } else { fields.removeValue(forKey: "color") }
        writeFrontmatter(fields, into: &lines)
        writeAndTrack(stack: stack, noteID: noteID, content: lines.joined(separator: "\n"))
    }

    @discardableResult
    func createNote(stack: String, title: String) -> String {
        let dir = directory(for: stack)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeName = title.isEmpty ? "New Note" : title
        var filename = "\(safeName).md"
        var suffix = 2
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(filename).path) {
            filename = "\(safeName) \(suffix).md"
            suffix += 1
        }
        // Just the heading, no placeholder item line -- an empty "- [ ] " used to silently fail
        // to parse (trimming its trailing space broke the "- [ ] " prefix match), which is what
        // actually made a new note start with zero items. That trick broke the moment bullets
        // became a catch-all for any "- "-prefixed line (ADR 0007) -- "- [ ]" (trimmed) matches
        // the bullet fallback now, so a real placeholder would show up as a bogus "[ ]" item.
        let content = "# \(safeName)\n"
        writeAndTrack(stack: stack, noteID: filename, content: content)
        return filename
    }

    /// Creates the file with the given *specific* filename (and `# title` heading) if it doesn't
    /// already exist -- unlike `createNote`, which always picks a fresh, non-colliding filename,
    /// this targets one predictable filename (a day or week's own date-derived name, ADR 0019)
    /// and leaves an existing file completely untouched if it's already there. What "today's
    /// note always exists, automatically" is built on.
    @discardableResult
    func ensureNote(stack: String, filename: String, title: String) -> String {
        let dir = directory(for: stack)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: url.path) {
            writeAndTrack(stack: stack, noteID: filename, content: "# \(title)\n")
        }
        return filename
    }

    /// Moves a note's file from one stack to another, creating the destination stack if it
    /// doesn't exist yet. Renames on collision rather than overwriting, same as createNote.
    @discardableResult
    func moveNote(noteID: String, from: String, to: String) -> String {
        let sourceURL = directory(for: from).appendingPathComponent(noteID)
        let destDir = directory(for: to)
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        var destURL = destDir.appendingPathComponent(noteID)
        if FileManager.default.fileExists(atPath: destURL.path) {
            let base = (noteID as NSString).deletingPathExtension
            var suffix = 2
            repeat {
                destURL = destDir.appendingPathComponent("\(base) \(suffix).md")
                suffix += 1
            } while FileManager.default.fileExists(atPath: destURL.path)
        }
        try? FileManager.default.moveItem(at: sourceURL, to: destURL)
        return destURL.lastPathComponent
    }

    /// Moves one *item* -- not a whole note -- from one note to another, preserving its exact
    /// line (kind, done state, done-date, everything) verbatim: removes it from the source,
    /// creates the destination note via `ensureNote` if it doesn't exist yet, and appends it
    /// there. "Move this task/note to a different day or week" (ADR 0019) -- `moveNote` moves an
    /// entire file, which isn't what this needs. Re-reads the source fresh first, same reasoning
    /// as every other write here.
    @discardableResult
    func moveItem(
        _ item: NoteItem, fromStack: String, fromNoteID: String,
        toStack: String, toNoteID: String, toNoteTitle: String
    ) -> Bool {
        let fromURL = directory(for: fromStack).appendingPathComponent(fromNoteID)
        let toURL = directory(for: toStack).appendingPathComponent(toNoteID)
        guard fromURL.standardizedFileURL != toURL.standardizedFileURL,
              var fromLines = (try? String(contentsOf: fromURL, encoding: .utf8))?.components(separatedBy: .newlines),
              let index = currentLineIndex(for: item, in: fromLines) else { return false }
        let line = fromLines[index]
        let sourceTitle = parse(fromURL)?.title ?? fromNoteID

        // Commit the destination first. If the second write fails, both copies remain,
        // which is recoverable; removing the source first could lose the only copy.
        var toLines: [String]
        if let existing = try? String(contentsOf: toURL, encoding: .utf8) {
            toLines = existing.components(separatedBy: .newlines)
        } else {
            do { try FileManager.default.createDirectory(at: toURL.deletingLastPathComponent(), withIntermediateDirectories: true) }
            catch { return false }
            toLines = ["# \(toNoteTitle)"]
        }
        while toLines.last?.isEmpty == true { toLines.removeLast() }
        toLines.append(line)
        guard writeAndTrack(stack: toStack, noteID: toNoteID, content: toLines.joined(separator: "\n") + "\n") else { return false }

        fromLines.remove(at: index)
        guard writeAndTrack(stack: fromStack, noteID: fromNoteID, content: fromLines.joined(separator: "\n")) else { return false }
        if item.done, let date = item.doneDate {
            replaceLogbookEntry(
                title: item.title, noteTitle: sourceTitle, date: date,
                with: Self.logbookLine(title: item.title + " — " + toNoteTitle, date: date, kind: item.kind)
            )
        }
        return true
    }

    /// `moveItem`'s non-destructive sibling (ADR 0026): copies one item's exact line (kind, done
    /// state, done-date, everything) to another note, leaving the original completely untouched
    /// -- "copy this task to another day" without losing it from the day it's on now. Creates
    /// the destination note via `ensureNote` if it doesn't exist yet, same as `moveItem`.
    @discardableResult
    func copyItem(
        _ item: NoteItem, fromStack: String, fromNoteID: String,
        toStack: String, toNoteID: String, toNoteTitle: String
    ) -> Bool {
        let fromURL = directory(for: fromStack).appendingPathComponent(fromNoteID)
        guard let fromLines = (try? String(contentsOf: fromURL, encoding: .utf8))?.components(separatedBy: .newlines),
              let index = currentLineIndex(for: item, in: fromLines) else { return false }
        let line = fromLines[index]

        ensureNote(stack: toStack, filename: toNoteID, title: toNoteTitle)
        let toURL = directory(for: toStack).appendingPathComponent(toNoteID)
        guard var toLines = (try? String(contentsOf: toURL, encoding: .utf8))?.components(separatedBy: .newlines)
        else { return false }
        while toLines.last?.isEmpty == true { toLines.removeLast() }
        toLines.append(line)
        writeAndTrack(stack: toStack, noteID: toNoteID, content: toLines.joined(separator: "\n") + "\n")
        return true
    }

    // MARK: - Logbook (ADR 0026)

    /// A single, plain, ever-growing file -- not hidden like `.trash/`/`.history/` (those are
    /// safety nets you rarely need to open; the Logbook is a first-class record meant to actually
    /// be read, in Notestack or in Obsidian). Nested in its own visible `Logbook/` folder rather
    /// than sitting as a bare file at the vault's root, though -- `loadNotes(stack:)` only ever
    /// lists files *directly inside* one stack's own directory, never recursing into a
    /// subdirectory, so this is what actually keeps it from being mistaken for a note in
    /// whichever stack happens to be the root itself (the unused "Main" stack, ADR 0003/0018) --
    /// a bare `Logbook.md` at the root did exactly that once, sorting ahead of "Today.md"
    /// alphabetically and getting parsed as if it were the Main stack's first note. Caught by
    /// `notestackChecks`, not reasoned out in advance.
    private var logbookURL: URL {
        root.appendingPathComponent("Logbook", isDirectory: true).appendingPathComponent("Logbook.md")
    }

    /// Appends one already-formatted line -- read-modify-write of the whole file, same shape as
    /// every other write in this class, not a true atomic append; fine for how infrequently this
    /// fires (once per task completed, at most). Creates the folder and file with a heading the
    /// first time.
    private func appendToLogbook(_ line: String) {
        try? FileManager.default.createDirectory(
            at: logbookURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var content = (try? String(contentsOf: logbookURL, encoding: .utf8)) ?? "# Logbook\n"
        if !content.hasSuffix("\n") { content += "\n" }
        content += line + "\n"
        writeAndTrack(stack: "Logbook", noteID: "Logbook.md", content: content)
    }

    private static func logbookLine(title: String, date: Date, kind: ItemKind) -> String {
        let shorthand = (kind == .task ? "(x) " : "[x] ") + title + " @done(\(doneDateFormatter.string(from: date)))"
        return markdownLine(for: shorthand)
    }

    private func matchingLogbookLineIndex(title: String, noteTitle: String, date: Date, in lines: [String]) -> Int? {
        lines.firstIndex { line in
            guard let entry = parseChecklistLine(line.trimmingCharacters(in: .whitespaces), lineIndex: 0) else { return false }
            return entry.done && entry.title == "\(title) — \(noteTitle)" && entry.doneDate == date
        }
    }

    private func removeFromLogbook(title: String, noteTitle: String, date: Date?) {
        guard let date,
              var lines = (try? String(contentsOf: logbookURL, encoding: .utf8))?.components(separatedBy: "\n"),
              let index = matchingLogbookLineIndex(title: title, noteTitle: noteTitle, date: date, in: lines) else { return }
        lines.remove(at: index)
        _ = writeAndTrack(stack: "Logbook", noteID: "Logbook.md", content: lines.joined(separator: "\n"))
    }

    private func replaceLogbookEntry(title: String, noteTitle: String, date: Date, with replacement: String) {
        guard var lines = (try? String(contentsOf: logbookURL, encoding: .utf8))?.components(separatedBy: "\n"),
              let index = matchingLogbookLineIndex(title: title, noteTitle: noteTitle, date: date, in: lines) else { return }
        lines[index] = replacement
        _ = writeAndTrack(stack: "Logbook", noteID: "Logbook.md", content: lines.joined(separator: "\n"))
    }

    func loadLogbook() -> Note {
        parse(logbookURL) ?? Note(id: "Logbook.md", title: "Logbook", items: [], color: nil)
    }

    /// Raw Markdown for verification and external-file interoperability.
    func logbookContents() -> String {
        (try? String(contentsOf: logbookURL, encoding: .utf8)) ?? ""
    }

    // MARK: - Trash (ADR 0011)

    /// A hidden subdirectory of the root -- invisible to `listStacks()` (which skips hidden
    /// entries already, same `.skipsHiddenFiles` option) and never touched by `loadNotes(stack:)`
    /// (which only ever reads a *stack's own* files, never recurses into subdirectories), so a
    /// trash entry can never be mistaken for a real note or a real stack.
    private var trashDirectory: URL { root.appendingPathComponent(".trash", isDirectory: true) }

    struct TrashEntry: Identifiable, Equatable {
        let id: String // the trash file's own filename
        let deletedAt: Date
        let stack: String
        let noteID: String
        let noteTitle: String
        let line: String // the raw Markdown line, e.g. "- [ ] milk"
    }

    /// One file per entry -- the same "a new concept is just a new file" idiom as everything else
    /// here -- reusing the `color` frontmatter convention (ADR 0008) rather than inventing a
    /// second one: a `---`-delimited block of metadata, then the deleted line as the body.
    @discardableResult
    private func moveToTrash(stack: String, noteID: String, noteTitle: String, line: String) -> String? {
        try? FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        let filename = UUID().uuidString + ".md"
        let content = """
        ---
        deletedAt: \(Self.trashDateFormatter.string(from: Date()))
        stack: \(stack)
        noteID: \(noteID)
        noteTitle: \(noteTitle)
        ---
        \(line)

        """
        do {
            try content.write(to: trashDirectory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
            return filename
        } catch {
            return nil
        }
    }

    /// Newest first.
    func listTrash() -> [TrashEntry] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: trashDirectory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap(parseTrashEntry)
            .sorted { $0.deletedAt > $1.deletedAt }
    }

    private func parseTrashEntry(_ url: URL) -> TrashEntry? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: .newlines)
        let fields = parseFrontmatter(lines)
        guard let deletedAtString = fields["deletedAt"], let deletedAt = Self.trashDateFormatter.date(from: deletedAtString),
              let stack = fields["stack"], let noteID = fields["noteID"]
        else { return nil }
        let line = lines[frontmatterEnd(lines)...].first { !$0.isEmpty } ?? ""
        return TrashEntry(
            id: url.lastPathComponent, deletedAt: deletedAt, stack: stack, noteID: noteID,
            noteTitle: fields["noteTitle"] ?? noteID, line: line
        )
    }

    /// Restores an entry: appends its line back into the note it came from, by its original
    /// filename -- recreating that exact file (under its original title) if it's since been
    /// deleted or moved away, rather than silently dropping the item a second time. Removes the
    /// Trash entry either way (a failed restore of a corrupt entry shouldn't leave it stuck).
    @discardableResult
    func restoreFromTrash(_ entryID: String) -> Bool {
        // IDs originate from filenames in our Trash directory; reject path components.
        guard URL(fileURLWithPath: entryID).lastPathComponent == entryID,
              let entry = parseTrashEntry(trashDirectory.appendingPathComponent(entryID)) else { return false }

        let noteURL = directory(for: entry.stack).appendingPathComponent(entry.noteID)
        var content: String
        if let existing = try? String(contentsOf: noteURL, encoding: .utf8) {
            var lines = existing.components(separatedBy: .newlines)
            while lines.last?.isEmpty == true { lines.removeLast() }
            lines.append(entry.line)
            content = lines.joined(separator: "\n") + "\n"
        } else {
            content = "# \(entry.noteTitle)\n\n\(entry.line)\n"
        }
        do { try FileManager.default.createDirectory(at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true) }
        catch { return false }
        guard writeAndTrack(stack: entry.stack, noteID: entry.noteID, content: content) else { return false }
        // If cleanup fails the restored item and its backup both remain, so retrying is safe.
        try? FileManager.default.removeItem(at: trashDirectory.appendingPathComponent(entryID))
        return true
    }

    /// Permanently discards one entry without restoring it.
    func emptyTrashEntry(_ entryID: String) {
        try? FileManager.default.removeItem(at: trashDirectory.appendingPathComponent(entryID))
    }

    /// Permanently discards everything in Trash.
    func emptyTrash() {
        for entry in listTrash() { emptyTrashEntry(entry.id) }
    }

    private static let trashDateFormatter = ISO8601DateFormatter()

    // MARK: - History: safety snapshots of externally-made changes (ADR 0021)

    /// A hidden subdirectory of the root, one folder per stack per note -- same "invisible to
    /// `listStacks()`/`loadNotes`" reasoning as `.trash/`. Holds a timestamped copy of a note's
    /// *previous* content every time `reconcileExternalChanges` notices the file changed without
    /// going through one of this class's own write methods -- the motivating case being an AI
    /// session (outside this app entirely, per the person's own call) editing a day/week note
    /// directly after they approve the change elsewhere. These are systems of record, so a bad
    /// edit -- AI or otherwise -- needs to always be recoverable, independent of Trash (which
    /// only ever covers one deleted item at a time, not a whole file rewritten by something else).
    private func historyDirectory(stack: String, noteID: String) -> URL {
        root.appendingPathComponent(".history", isDirectory: true)
            .appendingPathComponent(stack, isDirectory: true)
            .appendingPathComponent(noteID, isDirectory: true)
    }

    struct HistorySnapshot: Identifiable, Equatable {
        let id: String // the snapshot file's own filename
        let date: Date
        let stack: String
        let noteID: String
    }

    private static let historyTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS" // filename-safe: no colons, unique enough across rapid edits
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    @discardableResult
    private func saveHistorySnapshot(stack: String, noteID: String, content: String) -> String {
        let dir = historyDirectory(stack: stack, noteID: noteID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = Self.historyTimestampFormatter.string(from: Date()) + ".md"
        try? content.write(to: dir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
        return filename
    }

    /// Call once per stack per poll tick, *before* `loadNotes` -- compares every note file's
    /// current on-disk content against what this instance last trusted (`lastKnownContent`,
    /// updated by `writeAndTrack` for every write this app makes itself) and snapshots the *old*
    /// trusted content first if something else changed the file. The very first time a given
    /// note is seen in this process's lifetime there's nothing to compare against yet, so it just
    /// records a baseline and takes no snapshot -- otherwise every note already on disk at launch
    /// would get one pointlessly. `AppController.refreshNow()` calls this for both the Daily and
    /// Weekly stacks before reading notes for display.
    func reconcileExternalChanges(stack: String) {
        let dir = directory(for: stack)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension.lowercased() == "md" {
            let noteID = url.lastPathComponent
            guard let currentContent = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let key = "\(stack)/\(noteID)"
            if let previous = lastKnownContent[key], previous != currentContent {
                saveHistorySnapshot(stack: stack, noteID: noteID, content: previous)
            }
            lastKnownContent[key] = currentContent
        }
    }

    /// Newest first.
    func listHistory(stack: String, noteID: String) -> [HistorySnapshot] {
        let dir = historyDirectory(stack: stack, noteID: noteID)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { url -> HistorySnapshot? in
                guard let date = Self.historyTimestampFormatter.date(from: url.deletingPathExtension().lastPathComponent)
                else { return nil }
                return HistorySnapshot(id: url.lastPathComponent, date: date, stack: stack, noteID: noteID)
            }
            .sorted { $0.date > $1.date }
    }

    /// Overwrites the note's current content with a past snapshot's -- going through
    /// `writeAndTrack`, same as every other write here, so this restore itself is never mistaken
    /// for yet another external change the next time this stack is reconciled. Does not delete
    /// the snapshot (or the ones after it) -- restoring is non-destructive to the history itself,
    /// in case the wrong snapshot was picked.
    @discardableResult
    func restoreHistorySnapshot(stack: String, noteID: String, snapshotID: String) -> Bool {
        let snapshotURL = historyDirectory(stack: stack, noteID: noteID).appendingPathComponent(snapshotID)
        guard let content = try? String(contentsOf: snapshotURL, encoding: .utf8) else { return false }
        writeAndTrack(stack: stack, noteID: noteID, content: content)
        return true
    }
}
