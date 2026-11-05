import AppKit
import Foundation
import SwiftUI
@testable import NotestackKit


var failures = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        print("ok   - \(name)")
    } else {
        print("FAIL - \(name)")
        failures += 1
    }
}

let main = NotesStore.mainStack

func makeStore() -> (NotesStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return (NotesStore(root: dir), dir)
}

func write(_ dir: URL, _ filename: String, _ content: String) {
    try? content.write(to: dir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
}

do {
    let (_, dir) = makeStore()
    check("init creates the root directory", FileManager.default.fileExists(atPath: dir.path))
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] write report\n- [x] buy milk\n")
    let notes = store.loadNotes(stack: main)
    check("parses one note", notes.count == 1)
    check("id is the filename", notes.first?.id == "Today.md")
    check("title comes from the heading", notes.first?.title == "Today")
    check("item titles in order", notes.first?.items.map(\.title) == ["write report", "buy milk"])
    check("item done state", notes.first?.items.map(\.done) == [false, true])
}

do {
    let (store, dir) = makeStore()
    write(dir, "Groceries.md", "- [ ] eggs\n")
    check("falls back to filename with no heading", store.loadNotes(stack: main).first?.title == "Groceries")
}

do {
    let (store, dir) = makeStore()
    write(dir, "Note.md", "# Note\n\nJust some plain text.\n\n- [ ] a real item\n")
    check("ignores non-checklist lines", store.loadNotes(stack: main).first?.items.map(\.title) == ["a real item"])
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n")
    write(dir, "notes.txt", "not markdown")
    check("only lists .md files", store.loadNotes(stack: main).map(\.id) == ["Today.md"])
}

do {
    let (store, dir) = makeStore()
    write(dir, "B.md", "# B\n")
    write(dir, "A.md", "# A\n")
    check("notes sorted by filename", store.loadNotes(stack: main).map(\.id) == ["A.md", "B.md"])
}


do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] write report\n")
    var item = store.loadNotes(stack: main)[0].items[0]
    check("starts unchecked", !item.done)
    check("starts with no done-date", item.doneDate == nil)

    store.toggleItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: item)
    item = store.loadNotes(stack: main)[0].items[0]
    check("toggle checks it", item.done)
    check("toggle stamps today's done-date", item.doneDate != nil && Calendar.current.isDateInToday(item.doneDate!))

    store.toggleItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: item)
    item = store.loadNotes(stack: main)[0].items[0]
    check("toggle again unchecks it", !item.done)
    check("un-toggling clears the done-date", item.doneDate == nil)
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] first\n- [ ] second\n- [x] third\n")
    let items = store.loadNotes(stack: main)[0].items
    store.toggleItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: items[1]) // toggle "second"

    let after = store.loadNotes(stack: main)[0].items
    check("toggling one line keeps the others' titles", after.map(\.title) == ["first", "second", "third"])
    check("toggling one line doesn't disturb the others' state", after.map(\.done) == [false, true, true])
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- ( ) call mom\n")
    var item = store.loadNotes(stack: main)[0].items[0]
    check("a task toggles in place, same as a checklist item", !item.done)

    store.toggleItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: item)
    item = store.loadNotes(stack: main)[0].items[0]
    check("the task is still there, now done, with a done-date", item.done && item.title == "call mom" && item.doneDate != nil)
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- just a bullet\n")
    let item = store.loadNotes(stack: main)[0].items[0]
    store.toggleItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: item)
    check("toggling a bullet point does nothing", store.loadNotes(stack: main)[0].items[0].title == "just a bullet")
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] milk @done(2026-01-01)\n") // hand-edited: a stray tag on an undone item
    let item = store.loadNotes(stack: main)[0].items[0]
    check("a stray @done tag on an undone item is parsed out of the title but doesn't mark it done",
         !item.done && item.title == "milk" && item.doneDate != nil)
}


do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] write report\n")
    store.renameNote(stack: main, noteID: "Today.md", title: "Tomorrow")
    let note = store.loadNotes(stack: main)[0]
    check("renameNote updates the title", note.title == "Tomorrow")
    check("renameNote doesn't touch the filename/id", note.id == "Today.md")
    check("renameNote doesn't disturb items", note.items.map(\.title) == ["write report"])
}

do {
    let (store, dir) = makeStore()
    write(dir, "Groceries.md", "- [ ] eggs\n") // no heading line at all
    store.renameNote(stack: main, noteID: "Groceries.md", title: "Shopping")
    check("renameNote inserts a heading when there wasn't one", store.loadNotes(stack: main)[0].title == "Shopping")
}


do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] first\n")
    store.addItem(stack: main, noteID: "Today.md", text: "second") // no shorthand -> bullet
    let items = store.loadNotes(stack: main)[0].items
    check("addItem appends after existing items", items.map(\.title) == ["first", "second"])
    check("addItem with no shorthand adds a bullet point", items[1].kind == .bullet)
}

do {
    let (store, _) = makeStore()
    let id = store.createNote(stack: main, title: "Groceries") // starts with no items
    store.addItem(stack: main, noteID: id, text: "milk")
    store.addItem(stack: main, noteID: id, text: "eggs")
    check("addItem works repeatedly without piling up blank lines",
         store.loadNotes(stack: main)[0].items.map(\.title) == ["milk", "eggs"])
}


do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] frist\n")
    let item = store.loadNotes(stack: main)[0].items[0]
    store.editItem(stack: main, noteID: "Today.md", item: item, text: "[] first")
    let after = store.loadNotes(stack: main)[0].items[0]
    check("editItem fixes a typo and keeps the kind", after.title == "first" && after.kind == .checklist)
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- just a thought\n")
    let item = store.loadNotes(stack: main)[0].items[0]
    store.editItem(stack: main, noteID: "Today.md", item: item, text: "() act on it")
    let after = store.loadNotes(stack: main)[0].items[0]
    check("editItem's shorthand can change a bullet into a task", after.kind == .task && after.title == "act on it")
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] first\n- [x] second\n- [ ] third\n")
    let items = store.loadNotes(stack: main)[0].items
    store.editItem(stack: main, noteID: "Today.md", item: items[1], text: "[] second, edited")
    let after = store.loadNotes(stack: main)[0].items
    check("editing one line doesn't disturb the others' titles", after.map(\.title) == ["first", "second, edited", "third"])
    check("editItem resets done state to whatever the retyped shorthand implies",
         after.map(\.done) == [false, false, false])
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [x] second @done(2026-01-01)\n")
    let item = store.loadNotes(stack: main)[0].items[0]
    check("the pre-edit item carries its done-date", item.doneDate != nil)
    store.editItem(stack: main, noteID: "Today.md", item: item, text: "[x] second, edited @done(2026-01-01)")
    let after = store.loadNotes(stack: main)[0].items[0]
    check("re-including the @done tag in an edit preserves the done-date",
         after.title == "second, edited" && after.done && after.doneDate != nil)
}


do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] first\n- [ ] second\n- [ ] third\n")
    let items = store.loadNotes(stack: main)[0].items
    store.deleteItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: items[1]) // delete "second"
    let after = store.loadNotes(stack: main)[0].items
    check("deleteItem removes exactly the targeted item", after.map(\.title) == ["first", "third"])
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] only item\n")
    let item = store.loadNotes(stack: main)[0].items[0]
    store.deleteItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: item)
    let note = store.loadNotes(stack: main)[0]
    check("deleting the only item leaves zero items, not a blank one", note.items.isEmpty)
    check("deleting an item doesn't touch the title", note.title == "Today")
}


do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] milk\n")
    let item = store.loadNotes(stack: main)[0].items[0]
    let entryID = store.deleteItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: item)
    check("deleteItem returns a Trash entry id", entryID != nil)

    let trash = store.listTrash()
    check("the deleted item shows up in Trash", trash.count == 1)
    check("the Trash entry remembers the line, note, and stack", trash.first?.line == "- [ ] milk"
         && trash.first?.noteID == "Today.md" && trash.first?.noteTitle == "Today" && trash.first?.stack == main)

    check("restoring it returns true", store.restoreFromTrash(entryID!))
    let restored = store.loadNotes(stack: main)[0]
    check("the item is back in its original note", restored.items.map(\.title) == ["milk"])
    check("Trash is empty again after restoring", store.listTrash().isEmpty)
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] milk\n")
    let item = store.loadNotes(stack: main)[0].items[0]
    let entryID = store.deleteItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: item)!
    try? FileManager.default.removeItem(at: dir.appendingPathComponent("Today.md")) // the note itself is now gone

    check("restoring still returns true even if the original note is gone", store.restoreFromTrash(entryID))
    let notes = store.loadNotes(stack: main)
    check("the note is recreated under its original title", notes.first?.title == "Today")
    check("the item is there", notes.first?.items.map(\.title) == ["milk"])
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] first\n- [ ] second\n")
    let items = store.loadNotes(stack: main)[0].items
    store.deleteItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: items[0])
    store.deleteItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: items[1])
    check("multiple deletions each land their own Trash entry", store.listTrash().count == 2)

    store.emptyTrash()
    check("emptyTrash discards everything", store.listTrash().isEmpty)
}

do {
    check("listTrash on a fresh store is empty", NotesStore(root: FileManager.default.temporaryDirectory
         .appendingPathComponent(UUID().uuidString)).listTrash().isEmpty)
}


do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] first\n- [ ] second\n- [ ] third\n")
    let ids = store.loadNotes(stack: main)[0].items.map(\.id)
    store.reorderItems(stack: main, noteID: "Today.md", newOrder: [ids[2], ids[0], ids[1]]) // third, first, second
    let after = store.loadNotes(stack: main)[0].items
    check("reorderItems applies the requested order", after.map(\.title) == ["third", "first", "second"])
    check("reordering preserves each item's own state", after.map(\.done) == [false, false, false])
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- ( ) task\n- [x] done check\n- a bullet\n")
    let ids = store.loadNotes(stack: main)[0].items.map(\.id)
    store.reorderItems(stack: main, noteID: "Today.md", newOrder: [ids[2], ids[1], ids[0]]) // reverse
    let after = store.loadNotes(stack: main)[0].items
    check("reordering preserves each item's kind", after.map(\.kind) == [.bullet, .checklist, .task])
    check("reordering preserves done state", after.map(\.done) == [false, true, false])
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] first\n- [ ] second\n")
    let ids = store.loadNotes(stack: main)[0].items.map(\.id)
    store.reorderItems(stack: main, noteID: "Today.md", newOrder: [ids[1]]) // "first" missing from the request
    let after = store.loadNotes(stack: main)[0].items
    check("an item missing from the requested order is appended, not dropped", after.map(\.title) == ["second", "first"])
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "---\ncolor: blue\n---\n# Today\n\n- [ ] first\n- [ ] second\n")
    let ids = store.loadNotes(stack: main)[0].items.map(\.id)
    store.reorderItems(stack: main, noteID: "Today.md", newOrder: [ids[1], ids[0]])
    let note = store.loadNotes(stack: main)[0]
    check("reordering doesn't disturb frontmatter", note.color == .blue)
    check("reordering doesn't disturb the title", note.title == "Today")
    check("the order is actually swapped", note.items.map(\.title) == ["second", "first"])
}


do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- ( ) call mom\n- (x) submit report\n- just a thought\n- [ ] buy milk\n")
    let items = store.loadNotes(stack: main)[0].items
    check("parses a task line", items[0].kind == .task && items[0].title == "call mom" && !items[0].done)
    check("parses a done task line", items[1].kind == .task && items[1].title == "submit report" && items[1].done)
    check("parses a bullet point line", items[2].kind == .bullet && items[2].title == "just a thought" && !items[2].done)
    check("still parses a checklist line", items[3].kind == .checklist && items[3].title == "buy milk")
}

do {
    check("() shorthand makes a task line", NotesStore.markdownLine(for: "() call the dentist") == "- ( ) call the dentist")
    check("[] shorthand makes a checklist line", NotesStore.markdownLine(for: "[] milk") == "- [ ] milk")
    check("no shorthand makes a bullet line", NotesStore.markdownLine(for: "just a note") == "- just a note")
    check("shorthand parsing trims leading space", NotesStore.markdownLine(for: "()  spaced") == "- ( ) spaced")
    check("(x) shorthand makes a done task line", NotesStore.markdownLine(for: "(x) already done") == "- (x) already done")
    check("[x] shorthand makes a done checklist line", NotesStore.markdownLine(for: "[x] already done") == "- [x] already done")
}


do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n")
    check("a note with no frontmatter has no color", store.loadNotes(stack: main)[0].color == nil)

    store.setColor(stack: main, noteID: "Today.md", color: .pink)
    var note = store.loadNotes(stack: main)[0]
    check("setColor sets the color", note.color == .pink)
    check("setColor doesn't disturb the title", note.title == "Today")

    store.setColor(stack: main, noteID: "Today.md", color: .blue)
    check("setColor changes an already-set color", store.loadNotes(stack: main)[0].color == .blue)

    store.setColor(stack: main, noteID: "Today.md", color: nil)
    note = store.loadNotes(stack: main)[0]
    check("setColor(nil) clears the color", note.color == nil)
    let contents = (try? String(contentsOf: dir.appendingPathComponent("Today.md"))) ?? ""
    check("clearing the color removes the frontmatter block entirely", contents == "# Today\n")
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "---\nother: keep-me\n---\n# Today\n\n- [ ] write report\n")
    store.setColor(stack: main, noteID: "Today.md", color: .green)
    let contents = (try? String(contentsOf: dir.appendingPathComponent("Today.md"))) ?? ""
    check("setColor preserves unrelated frontmatter keys", contents.contains("other: keep-me"))
    check("setColor adds the color key alongside it", contents.contains("color: green"))
    let note = store.loadNotes(stack: main)[0]
    check("the note still parses correctly with unrelated frontmatter present",
         note.title == "Today" && note.items.map(\.title) == ["write report"] && note.color == .green)
}

do {
    let (store, dir) = makeStore()
    write(dir, "Groceries.md", "- [ ] eggs\n") // no heading, like the renameNote test above
    store.renameNote(stack: main, noteID: "Groceries.md", title: "Shopping")
    store.setColor(stack: main, noteID: "Groceries.md", color: .yellow)
    let note = store.loadNotes(stack: main)[0]
    check("rename then color-set both land correctly with no frontmatter to start",
         note.title == "Shopping" && note.color == .yellow && note.items.map(\.title) == ["eggs"])
}

do {
    let (store, _) = makeStore()
    let filename = store.createNote(stack: main, title: "Groceries")
    check("createNote names the file after the title", filename == "Groceries.md")
    let notes = store.loadNotes(stack: main)
    check("createNote writes a loadable note", notes.count == 1 && notes.first?.title == "Groceries")
    check("a new note starts with no items", notes.first?.items.isEmpty == true)
}

do {
    let (store, _) = makeStore()
    let first = store.createNote(stack: main, title: "Groceries")
    let second = store.createNote(stack: main, title: "Groceries")
    check("createNote never overwrites an existing file", first != second)
    check("both notes exist", store.loadNotes(stack: main).count == 2)
}


do {
    let (store, _) = makeStore()
    check("a fresh store only has Main", store.listStacks() == ["Main"])
}

do {
    let (store, _) = makeStore()
    let created = store.createStack(name: "Archive")
    check("createStack returns the name used", created == "Archive")
    check("listStacks includes it, Main first", store.listStacks() == ["Main", "Archive"])
}

do {
    let (store, _) = makeStore()
    store.createStack(name: "Zeta")
    store.createStack(name: "Alpha")
    check("non-Main stacks are sorted alphabetically after Main", store.listStacks() == ["Main", "Alpha", "Zeta"])
}

do {
    let (store, _) = makeStore()
    store.createNote(stack: main, title: "Groceries")
    check("a note created in Main is not visible in another stack",
         store.loadNotes(stack: store.createStack(name: "Archive")).isEmpty)
}

do {
    let (store, _) = makeStore()
    let id = store.createNote(stack: main, title: "Old task")
    let newID = store.moveNote(noteID: id, from: main, to: "Archive")
    check("moveNote returns the filename in the destination", newID == id)
    check("the note is gone from the source stack", store.loadNotes(stack: main).isEmpty)
    check("the note is now in the destination stack", store.loadNotes(stack: "Archive").map(\.id) == [id])
    check("moveNote creates the destination stack if needed", store.listStacks().contains("Archive"))
}

do {
    let (store, _) = makeStore()
    let id = store.createNote(stack: main, title: "Dup")
    store.createNote(stack: "Archive", title: "Dup") // same filename already exists over there
    let newID = store.moveNote(noteID: id, from: main, to: "Archive")
    check("moveNote renames on collision instead of overwriting", newID != id)
    check("both notes exist in the destination", store.loadNotes(stack: "Archive").count == 2)
}


do {
    let (store, _) = makeStore()
    let id = store.ensureNote(stack: "Daily", filename: "2026-11-05.md", title: "Thursday, November 5")
    check("ensureNote uses the exact filename given", id == "2026-11-05.md")
    let note = store.loadNotes(stack: "Daily").first
    check("ensureNote creates a loadable note with the given title", note?.title == "Thursday, November 5")
    check("ensureNote creates the stack directory if needed", store.listStacks().contains("Daily"))
}

do {
    let (store, dir) = makeStore()
    store.createStack(name: "Daily")
    write(dir.appendingPathComponent("Daily"), "2026-11-05.md", "# Thursday, November 5\n\n- [ ] already here\n")
    store.ensureNote(stack: "Daily", filename: "2026-11-05.md", title: "Thursday, November 5")
    let note = store.loadNotes(stack: "Daily").first
    check("ensureNote leaves an existing file completely untouched", note?.items.map(\.title) == ["already here"])
}


do {
    let (store, dir) = makeStore()
    write(dir, "2026-11-05.md", "# Thursday, November 5\n\n- [ ] call mom\n- [ ] buy milk\n")
    let item = store.loadNotes(stack: main)[0].items[0] // "call mom"
    let moved = store.moveItem(
        item, fromStack: main, fromNoteID: "2026-11-05.md",
        toStack: main, toNoteID: "2026-11-06.md", toNoteTitle: "Friday, November 6"
    )
    check("moveItem reports success", moved)

    let source = store.loadNotes(stack: main).first { $0.id == "2026-11-05.md" }
    check("the item is gone from the source note", source?.items.map(\.title) == ["buy milk"])

    let destination = store.loadNotes(stack: main).first { $0.id == "2026-11-06.md" }
    check("moveItem creates the destination note if it doesn't exist yet", destination?.title == "Friday, November 6")
    check("the item arrives in the destination note, verbatim", destination?.items.map(\.title) == ["call mom"])
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- (x) call mom @done(2026-01-01)\n")
    let item = store.loadNotes(stack: main)[0].items[0]
    store.moveItem(item, fromStack: main, fromNoteID: "Today.md", toStack: main, toNoteID: "Other.md", toNoteTitle: "Other")
    let moved = store.loadNotes(stack: main).first { $0.id == "Other.md" }?.items.first
    check("moveItem preserves done state and done-date exactly", moved?.done == true && moved?.doneDate != nil)
}

do {
    let (store, dir) = makeStore()
    write(dir, "A.md", "# A\n\n- [ ] first\n")
    write(dir, "B.md", "# B\n\n- [ ] existing\n")
    let item = store.loadNotes(stack: main).first { $0.id == "A.md" }!.items[0]
    store.moveItem(item, fromStack: main, fromNoteID: "A.md", toStack: main, toNoteID: "B.md", toNoteTitle: "B")
    let destination = store.loadNotes(stack: main).first { $0.id == "B.md" }
    check("moveItem appends to an existing destination note without disturbing what's already there",
         destination?.items.map(\.title) == ["existing", "first"])
}


do {
    let (store, dir) = makeStore()
    write(dir, "2026-11-05.md", "# Thursday, November 5\n\n- [ ] call mom\n- [ ] buy milk\n")
    let item = store.loadNotes(stack: main)[0].items[0] // "call mom"
    let copied = store.copyItem(
        item, fromStack: main, fromNoteID: "2026-11-05.md",
        toStack: main, toNoteID: "2026-11-06.md", toNoteTitle: "Friday, November 6"
    )
    check("copyItem reports success", copied)

    let source = store.loadNotes(stack: main).first { $0.id == "2026-11-05.md" }
    check("copyItem leaves the source note completely untouched", source?.items.map(\.title) == ["call mom", "buy milk"])

    let destination = store.loadNotes(stack: main).first { $0.id == "2026-11-06.md" }
    check("copyItem creates the destination note if it doesn't exist yet", destination?.title == "Friday, November 6")
    check("the item arrives in the destination note, verbatim", destination?.items.map(\.title) == ["call mom"])
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- (x) call mom @done(2026-01-01)\n")
    let item = store.loadNotes(stack: main)[0].items[0]
    store.copyItem(item, fromStack: main, fromNoteID: "Today.md", toStack: main, toNoteID: "Other.md", toNoteTitle: "Other")
    let copied = store.loadNotes(stack: main).first { $0.id == "Other.md" }?.items.first
    check("copyItem preserves done state and done-date exactly", copied?.done == true && copied?.doneDate != nil)
}

do {
    let (store, dir) = makeStore()
    write(dir, "A.md", "# A\n\n- [ ] existing\n")
    write(dir, "B.md", "# B\n\n- [ ] existing\n")
    let item = store.loadNotes(stack: main).first { $0.id == "B.md" }!.items[0]
    store.copyItem(item, fromStack: main, fromNoteID: "B.md", toStack: main, toNoteID: "A.md", toNoteTitle: "A")
    let destination = store.loadNotes(stack: main).first { $0.id == "A.md" }
    check("copyItem appends to an existing destination note without disturbing what's already there",
         destination?.items.map(\.title) == ["existing", "existing"])
}


do {
    let (store, dir) = makeStore()
    write(dir, "2026-11-05.md", "# Thu, Nov 5, 2026\n\n- ( ) finish report #work\n")
    let item = store.loadNotes(stack: main)[0].items[0]
    store.toggleItem(stack: main, noteID: "2026-11-05.md", noteTitle: "Thu, Nov 5, 2026", item: item)

    let logbook = store.logbookContents()
    check("completing a task appends it to the Logbook", logbook.contains("finish report #work"))
    check("the Logbook entry keeps the item's tag", logbook.contains("#work"))
    check("the Logbook entry includes the source note's title", logbook.contains("Thu, Nov 5, 2026"))
    check("the Logbook entry includes a done-date tag", logbook.contains("@done("))
    check("the original item is still in the day's own note (a copy, not a move)",
         store.loadNotes(stack: main)[0].items.map(\.title) == ["finish report #work"])
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] milk\n")
    var item = store.loadNotes(stack: main)[0].items[0]
    check("the Logbook starts empty", store.logbookContents().isEmpty)

    store.toggleItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: item)
    check("completing adds exactly one Logbook entry", store.logbookContents().components(separatedBy: "\n- ").count == 2)

    item = store.loadNotes(stack: main)[0].items[0]
    store.toggleItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: item) // un-check it
    check("un-completing removes the earlier Logbook entry",
         store.logbookContents().components(separatedBy: "\n- ").count == 1)
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] first\n- [ ] second\n")
    let items = store.loadNotes(stack: main)[0].items
    store.toggleItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: items[0])
    let second = store.loadNotes(stack: main)[0].items.first { $0.title == "second" }!
    store.toggleItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: second)

    let logbook = store.logbookContents()
    check("completing two tasks appends two Logbook entries in order",
         logbook.range(of: "first")!.lowerBound < logbook.range(of: "second")!.lowerBound)
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- a bullet, not a checkbox\n")
    let item = store.loadNotes(stack: main)[0].items[0]
    store.toggleItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: item)
    check("toggling a bullet (a no-op) never touches the Logbook", store.logbookContents().isEmpty)
}


do {
    let components = DateComponents(year: 2026, month: 11, day: 5) // a Thursday
    let date = Calendar.current.date(from: components)!
    check("dayFilename is a plain yyyy-MM-dd.md", NoteCadence.dayFilename(for: date) == "2026-11-05.md")
    check("dayTitle includes the weekday", NoteCadence.dayTitle(for: date).hasPrefix("Thu"))
    check("date(fromFilename:) round-trips dayFilename",
         NoteCadence.date(fromFilename: NoteCadence.dayFilename(for: date)) != nil)
}

do {
    let thursday = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 5))! // Thursday
    let mondayOfThatWeek = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2))!
    check("weekFilename names the week after its Monday",
         NoteCadence.weekFilename(for: thursday) == NoteCadence.dayFilename(for: mondayOfThatWeek))
    check("weekTitle reads as \"Week of ...\"", NoteCadence.weekTitle(for: thursday).hasPrefix("Week of"))
}

do {
    let friday = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 6))!
    let id1 = NoteCadence.weekFilename(for: friday)
    let saturday = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 7))!
    let id2 = NoteCadence.weekFilename(for: saturday)
    check("two dates in the same week resolve to the same week filename", id1 == id2)
}


do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] first\n")
    store.reconcileExternalChanges(stack: main) // establishes the baseline -- nothing to compare against yet
    check("no snapshot is taken the first time a note is ever seen", store.listHistory(stack: main, noteID: "Today.md").isEmpty)

    write(dir, "Today.md", "# Today\n\n- [ ] first\n- [ ] second\n") // simulates an external/AI edit
    store.reconcileExternalChanges(stack: main)
    let history = store.listHistory(stack: main, noteID: "Today.md")
    check("an externally-changed file gets exactly one snapshot", history.count == 1)
    let contents = (try? String(contentsOf: dir.appendingPathComponent(".history/Main/Today.md/\(history[0].id)"))) ?? ""
    check("the snapshot holds the content from BEFORE the external change", contents == "# Today\n\n- [ ] first\n")
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] first\n")
    let item = store.loadNotes(stack: main)[0].items[0]
    store.reconcileExternalChanges(stack: main) // baseline

    store.toggleItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: item) // the app's OWN write
    store.reconcileExternalChanges(stack: main)
    check("a change made through the app's own write methods is never snapshotted as external",
         store.listHistory(stack: main, noteID: "Today.md").isEmpty)
}

do {
    let (store, dir) = makeStore()
    write(dir, "Today.md", "# Today\n\n- [ ] first\n")
    store.reconcileExternalChanges(stack: main)
    write(dir, "Today.md", "# Today\n\n- [ ] first\n- [ ] second\n")
    store.reconcileExternalChanges(stack: main)
    let snapshotID = store.listHistory(stack: main, noteID: "Today.md")[0].id

    check("restoring a snapshot returns true", store.restoreHistorySnapshot(stack: main, noteID: "Today.md", snapshotID: snapshotID))
    let restored = store.loadNotes(stack: main)[0]
    check("restoring puts the note back to the snapshot's content", restored.items.map(\.title) == ["first"])

    store.reconcileExternalChanges(stack: main) // the restore itself must not look like yet another external change
    check("restoring through the store's own API doesn't spawn another snapshot",
         store.listHistory(stack: main, noteID: "Today.md").count == 1)
}


do {
    check("every palette has a unique name", Set(Theme.palettes.map(\.name)).count == Theme.palettes.count)
    check("at least two palettes exist, or there'd be nothing to cycle through", Theme.palettes.count >= 2)
    check("every added theme is actually present (5 original + 30 more, ADR 0025)", Theme.palettes.count == 35)
}

func luminance(_ color: Color) -> Double {
    guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return 0.5 }
    return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
}

do {
    for palette in Theme.palettes {
        let contrast = abs(luminance(palette.paneBase) - luminance(palette.textPrimary))
        check("\(palette.name): textPrimary has real contrast against paneBase", contrast > 0.35)
    }
}

do {
    Theme.currentIndex = 0
    check("starts on the first palette", Theme.current.name == Theme.palettes[0].name)

    let second = Theme.cycleToNext()
    check("cycling advances to the next palette", second.name == Theme.palettes[1].name)
    check("current reflects the cycle", Theme.current.name == Theme.palettes[1].name)

    for _ in 0..<(Theme.palettes.count - 1) { Theme.cycleToNext() }
    check("cycling all the way around wraps back to the first", Theme.current.name == Theme.palettes[0].name)
}

do {
    let (store, dir) = makeStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    write(dir, "Today.md", "# Today\n- ( ) first\n- [ ] second\n")
    let items = store.loadNotes(stack: main)[0].items
    for item in items { store.toggleItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: item) }
    let completed = store.loadNotes(stack: main)[0].items
    check("completion timestamp retains time to seconds", abs(completed[0].doneDate!.timeIntervalSinceNow) < 3)
    check("Logbook and daily timestamp match", store.loadLogbook().items[0].doneDate == completed[0].doneDate)
    store.reconcileExternalChanges(stack: "Logbook")
    store.toggleItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: completed[0])
    check("reopening preserves unrelated Logbook entries", store.loadLogbook().items.map(\.title) == ["second — Today"])
    store.reconcileExternalChanges(stack: "Logbook")
    check("own Logbook writes do not create external history", store.listHistory(stack: "Logbook", noteID: "Logbook.md").isEmpty)
    write(dir, "Today.md", "# Today\n- (x) old @done(2026-01-01)\n")
    write(dir.appendingPathComponent("Logbook"), "Logbook.md", "# Logbook\n- (x) old — Today @done(2026-01-01)\n")
    store.toggleItem(stack: main, noteID: "Today.md", noteTitle: "Today", item: store.loadNotes(stack: main)[0].items[0])
    check("legacy date-only completion removes its Logbook entry", store.loadLogbook().items.isEmpty)
}

do {
    let suite = "notestackChecks.location." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    let (original, root) = makeStore()
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
    check("default notes folder remains Documents/Notestack", NotesStore.configuredRoot(defaults: defaults) == NotesStore.defaultRoot)
    write(root, "Existing.md", "# Existing\n")
    let selected = root.appendingPathComponent("Chosen", isDirectory: true)
    try! FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
    do { try NotesStore.selectRoot(selected, defaults: defaults) }
    catch { check("valid folder selection succeeds", false) }
    check("folder selection persists", NotesStore.configuredRoot(defaults: UserDefaults(suiteName: suite)!).path == selected.path)
    check("selection leaves existing notes in place", original.loadNotes(stack: main).map(\.id) == ["Existing.md"])
    let chosenStore = NotesStore(root: NotesStore.configuredRoot(defaults: defaults))
    chosenStore.ensureNote(stack: "Daily", filename: "2026-11-05.md", title: "Today")
    check("chosen folder receives daily notes", chosenStore.loadNotes(stack: "Daily").count == 1 && original.loadNotes(stack: "Daily").isEmpty)
    do {
        try NotesStore.selectRoot(root.appendingPathComponent("Existing.md"), defaults: defaults)
        check("file cannot be selected as root", false)
    } catch {
        check("invalid selection preserves saved folder", NotesStore.configuredRoot(defaults: defaults).path == selected.path)
    }
}

do {
    let sunday = NoteCadence.date(fromFilename: "2027-01-03.md")!
    let monday = NoteCadence.date(fromFilename: "2027-01-04.md")!
    check("Sunday belongs to the previous Monday across years", NotePeriod.weekly.filename(for: sunday) == "2026-12-28.md")
    check("current weekly note rolls to the new Monday", NotePeriod.weekly.rollover(viewingID: "2026-12-28.md", previousDate: sunday, now: monday) == "2027-01-04.md")
    check("browsing an older week survives rollover", NotePeriod.weekly.rollover(viewingID: "2026-12-21.md", previousDate: sunday, now: monday) == "2026-12-21.md")
    check("daily rollover remains one day", NotePeriod.daily.rollover(viewingID: "2027-01-03.md", previousDate: sunday, now: monday) == "2027-01-04.md")
    let (store, dir) = makeStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let id = "2027-01-04.md"
    for period in NotePeriod.allCases {
        store.ensureNote(stack: period.stack, filename: id, title: period.title(for: monday))
    }
    store.addItem(stack: "Weekly", noteID: id, text: "() weekly goal")
    check("same-named daily and weekly notes remain independent", store.loadNotes(stack: "Daily")[0].items.isEmpty)
    var weekly = store.loadNotes(stack: "Weekly")[0]
    store.toggleItem(stack: "Weekly", noteID: id, noteTitle: weekly.title, item: weekly.items[0])
    weekly = store.loadNotes(stack: "Weekly")[0]
    check("weekly completion records its week title and timestamp", store.loadLogbook().items[0].title == "weekly goal — " + weekly.title && store.loadLogbook().items[0].doneDate == weekly.items[0].doneDate)
    store.toggleItem(stack: "Weekly", noteID: id, noteTitle: weekly.title, item: weekly.items[0])
    check("weekly reopening removes completion from Logbook", store.loadLogbook().items.isEmpty)
    store.copyItem(store.loadNotes(stack: "Weekly")[0].items[0], fromStack: "Weekly", fromNoteID: id, toStack: "Daily", toNoteID: id, toNoteTitle: "Monday")
    check("weekly item can be copied to a same-named daily file", store.loadNotes(stack: "Daily")[0].items[0].title == "weekly goal")
}

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
