import Foundation

final class NotesStore {
    static let mainStack = "Main"

    let root: URL

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

    static func selectRoot(_ url: URL, defaults: UserDefaults = .standard) throws {
        let root = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let probe = root.appendingPathComponent(".notestack-write-check-" + UUID().uuidString)
        try Data().write(to: probe, options: .withoutOverwriting)
        try FileManager.default.removeItem(at: probe)
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


    private func directory(for stack: String) -> URL {
        stack == Self.mainStack ? root : root.appendingPathComponent(stack, isDirectory: true)
    }

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


    private func writeAndTrack(stack: String, noteID: String, content: String) {
        let url = directory(for: stack).appendingPathComponent(noteID)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        lastKnownContent["\(stack)/\(noteID)"] = content
    }

    func toggleItem(stack: String, noteID: String, noteTitle: String, item: NoteItem) {
        guard item.kind != .bullet else { return }
        let url = directory(for: stack).appendingPathComponent(noteID)
        guard var lines = (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: .newlines),
              item.lineIndex < lines.count else { return }
        let line = lines[item.lineIndex]
        guard let current = parseChecklistLine(line, lineIndex: item.lineIndex),
              current.title == item.title, current.kind == item.kind, current.done == item.done else { return }

        if !current.done {
            for (from, to) in [("- [ ] ", "- [x] "), ("- ( ) ", "- (x) ")] where line.hasPrefix(from) {
                let rest = Self.stripDoneDate(String(line.dropFirst(from.count)))
                let date = Date()
                lines[item.lineIndex] = to + Self.appendDoneDate(rest, date)
                appendToLogbook(to + Self.appendDoneDate("\(rest) — \(noteTitle)", date))
                break
            }
        } else {
            let flips: [(String, String)] = [
                ("- [x] ", "- [ ] "), ("- [X] ", "- [ ] "), ("- (x) ", "- ( ) "), ("- (X) ", "- ( ) "),
            ]
            for (from, to) in flips where line.hasPrefix(from) {
                let rest = Self.stripDoneDate(String(line.dropFirst(from.count)))
                lines[item.lineIndex] = to + rest
                removeFromLogbook(title: rest, noteTitle: noteTitle,
                                  date: Self.extractDoneDate(String(line.dropFirst(from.count))).doneDate)
                break
            }
        }
        writeAndTrack(stack: stack, noteID: noteID, content: lines.joined(separator: "\n"))
    }

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

    func addItem(stack: String, noteID: String, text: String) {
        let url = directory(for: stack).appendingPathComponent(noteID)
        guard var lines = (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: .newlines)
        else { return }
        while lines.last?.isEmpty == true { lines.removeLast() }
        lines.append(Self.markdownLine(for: text))
        writeAndTrack(stack: stack, noteID: noteID, content: lines.joined(separator: "\n") + "\n")
    }

    func editItem(stack: String, noteID: String, item: NoteItem, text: String) {
        let url = directory(for: stack).appendingPathComponent(noteID)
        guard var lines = (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: .newlines),
              item.lineIndex < lines.count else { return }
        lines[item.lineIndex] = Self.markdownLine(for: text)
        writeAndTrack(stack: stack, noteID: noteID, content: lines.joined(separator: "\n"))
    }

    @discardableResult
    func deleteItem(stack: String, noteID: String, noteTitle: String, item: NoteItem) -> String? {
        let url = directory(for: stack).appendingPathComponent(noteID)
        guard var lines = (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: .newlines),
              item.lineIndex < lines.count else { return nil }
        let removedLine = lines[item.lineIndex]
        lines.remove(at: item.lineIndex)
        writeAndTrack(stack: stack, noteID: noteID, content: lines.joined(separator: "\n"))
        return moveToTrash(stack: stack, noteID: noteID, noteTitle: noteTitle, line: removedLine)
    }

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
        let content = "# \(safeName)\n"
        writeAndTrack(stack: stack, noteID: filename, content: content)
        return filename
    }

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

    @discardableResult
    func moveItem(
        _ item: NoteItem, fromStack: String, fromNoteID: String,
        toStack: String, toNoteID: String, toNoteTitle: String
    ) -> Bool {
        let fromURL = directory(for: fromStack).appendingPathComponent(fromNoteID)
        guard var fromLines = (try? String(contentsOf: fromURL, encoding: .utf8))?.components(separatedBy: .newlines),
              item.lineIndex < fromLines.count else { return false }
        let line = fromLines[item.lineIndex]
        fromLines.remove(at: item.lineIndex)
        writeAndTrack(stack: fromStack, noteID: fromNoteID, content: fromLines.joined(separator: "\n"))

        ensureNote(stack: toStack, filename: toNoteID, title: toNoteTitle)
        let toURL = directory(for: toStack).appendingPathComponent(toNoteID)
        guard var toLines = (try? String(contentsOf: toURL, encoding: .utf8))?.components(separatedBy: .newlines)
        else { return false }
        while toLines.last?.isEmpty == true { toLines.removeLast() }
        toLines.append(line)
        writeAndTrack(stack: toStack, noteID: toNoteID, content: toLines.joined(separator: "\n") + "\n")
        return true
    }

    @discardableResult
    func copyItem(
        _ item: NoteItem, fromStack: String, fromNoteID: String,
        toStack: String, toNoteID: String, toNoteTitle: String
    ) -> Bool {
        let fromURL = directory(for: fromStack).appendingPathComponent(fromNoteID)
        guard let fromLines = (try? String(contentsOf: fromURL, encoding: .utf8))?.components(separatedBy: .newlines),
              item.lineIndex < fromLines.count else { return false }
        let line = fromLines[item.lineIndex]

        ensureNote(stack: toStack, filename: toNoteID, title: toNoteTitle)
        let toURL = directory(for: toStack).appendingPathComponent(toNoteID)
        guard var toLines = (try? String(contentsOf: toURL, encoding: .utf8))?.components(separatedBy: .newlines)
        else { return false }
        while toLines.last?.isEmpty == true { toLines.removeLast() }
        toLines.append(line)
        writeAndTrack(stack: toStack, noteID: toNoteID, content: toLines.joined(separator: "\n") + "\n")
        return true
    }


    private var logbookURL: URL {
        root.appendingPathComponent("Logbook", isDirectory: true).appendingPathComponent("Logbook.md")
    }

    private func appendToLogbook(_ line: String) {
        try? FileManager.default.createDirectory(
            at: logbookURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var content = (try? String(contentsOf: logbookURL, encoding: .utf8)) ?? "# Logbook\n"
        if !content.hasSuffix("\n") { content += "\n" }
        content += line + "\n"
        writeAndTrack(stack: "Logbook", noteID: "Logbook.md", content: content)
    }

    private func removeFromLogbook(title: String, noteTitle: String, date: Date?) {
        guard var lines = (try? String(contentsOf: logbookURL, encoding: .utf8))?.components(separatedBy: "\n") else { return }
        guard let index = lines.firstIndex(where: { line in
            guard let entry = parseChecklistLine(line, lineIndex: 0) else { return false }
            return entry.done && entry.title == "\(title) — \(noteTitle)" && entry.doneDate == date
        }) else { return }
        lines.remove(at: index)
        writeAndTrack(stack: "Logbook", noteID: "Logbook.md", content: lines.joined(separator: "\n"))
    }

    func loadLogbook() -> Note {
        parse(logbookURL) ?? Note(id: "Logbook.md", title: "Logbook", items: [], color: nil)
    }

    func logbookContents() -> String {
        (try? String(contentsOf: logbookURL, encoding: .utf8)) ?? ""
    }


    private var trashDirectory: URL { root.appendingPathComponent(".trash", isDirectory: true) }

    struct TrashEntry: Identifiable, Equatable {
        let id: String // the trash file's own filename
        let deletedAt: Date
        let stack: String
        let noteID: String
        let noteTitle: String
        let line: String // the raw Markdown line, e.g. "- [ ] milk"
    }

    @discardableResult
    private func moveToTrash(stack: String, noteID: String, noteTitle: String, line: String) -> String {
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
        try? content.write(to: trashDirectory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
        return filename
    }

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

    @discardableResult
    func restoreFromTrash(_ entryID: String) -> Bool {
        let entryURL = trashDirectory.appendingPathComponent(entryID)
        defer { try? FileManager.default.removeItem(at: entryURL) }
        guard let entry = parseTrashEntry(entryURL) else { return false }

        let noteURL = directory(for: entry.stack).appendingPathComponent(entry.noteID)
        if var lines = (try? String(contentsOf: noteURL, encoding: .utf8))?.components(separatedBy: .newlines) {
            while lines.last?.isEmpty == true { lines.removeLast() }
            lines.append(entry.line)
            writeAndTrack(stack: entry.stack, noteID: entry.noteID, content: lines.joined(separator: "\n") + "\n")
        } else {
            try? FileManager.default.createDirectory(at: directory(for: entry.stack), withIntermediateDirectories: true)
            writeAndTrack(stack: entry.stack, noteID: entry.noteID, content: "# \(entry.noteTitle)\n\n\(entry.line)\n")
        }
        return true
    }

    func emptyTrashEntry(_ entryID: String) {
        try? FileManager.default.removeItem(at: trashDirectory.appendingPathComponent(entryID))
    }

    func emptyTrash() {
        for entry in listTrash() { emptyTrashEntry(entry.id) }
    }

    private static let trashDateFormatter = ISO8601DateFormatter()


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

    @discardableResult
    func restoreHistorySnapshot(stack: String, noteID: String, snapshotID: String) -> Bool {
        let snapshotURL = historyDirectory(stack: stack, noteID: noteID).appendingPathComponent(snapshotID)
        guard let content = try? String(contentsOf: snapshotURL, encoding: .utf8) else { return false }
        writeAndTrack(stack: stack, noteID: noteID, content: content)
        return true
    }
}
