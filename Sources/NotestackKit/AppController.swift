import AppKit
import SwiftUI

/// Owns one main note window and its floating daily/weekly navigator.
@MainActor
final class AppController {
    private var store: NotesStore
    private var window: AppWindow!
    private var navigator: AppWindow?
    private var showingLogbook = false
    private var period: NotePeriod = .daily
    private var lastRolloverDate = Date()
    private var pollTask: Task<Void, Never>?

    private var note: Note?
    private var itemCount = 0 // for Notifier.noteGrew; nil/first-seen never notifies

    /// Today's note id, refreshed on every poll tick -- see `checkForRollover()`. Kept as
    /// explicit state (rather than recomputed from `Date()` on every use) so this is a long-
    /// running menu-bar app that can roll over to a new day entirely on its own if left open
    /// past midnight, instead of silently continuing to show yesterday's note.
    private var todayID = NoteCadence.dayFilename(for: Date())

    /// Which day's note is actually on screen (ADR 0023) -- starts out equal to `todayID`, but
    /// ◀/▶, scroll, ←/→, or the date picker can point it anywhere else, past or future. Kept
    /// distinct from `todayID` specifically so `checkForRollover()` can tell "the person is
    /// looking at today, swap them to the new today at midnight" apart from "the person
    /// navigated away on purpose, leave them where they are."
    private var viewingID: String

    init(store: NotesStore) {
        self.store = store
        self.viewingID = todayID
    }

    /// The single most recent deletion's Trash entry id, for ⌘Z (ADR 0011) -- one level, not a
    /// stack. Trash itself has no browsing UI anymore (ADR 0022), but still safely holds every
    /// deleted item on disk -- reachable via "Reveal Notes Folder" (`.trash/`) if ever needed
    /// beyond what ⌘Z covers.
    private var lastDeletedTrashEntryID: String?

    func start() {
        window = AppWindow()
        window.onUndo = { [weak self] in self?.undoLastDelete() }
        window.onNavigate = { [weak self] direction in self?.navigate(by: direction) }
        store.ensureNote(stack: NoteCadence.dailyStack, filename: todayID, title: NoteCadence.dayTitle(for: Date()))

        // Size and center *before* the first `orderFront` -- otherwise the window would flash
        // briefly at its zero-size default origin before snapping to the right place.
        refreshNow()
        centerWindow()
        window.orderFront(nil)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { break } // see AGENTS.md trap re: pollTask's clean exit
                self.refreshNow()
            }
        }
    }

    func toggleVisibility() {
        if window.isVisible { navigator?.orderOut(nil); window.orderOut(nil) } else { window.orderFront(nil) }
    }

    func revealNotesFolder() {
        NSWorkspace.shared.open(store.root)
    }

    func chooseNotesFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Notes Folder"
        panel.message = "Choose the folder containing Daily, Weekly, and Logbook. Existing files stay in their current folder; choosing an empty folder starts a new collection."
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.root
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try NotesStore.selectRoot(url)
            guard url.standardizedFileURL != store.root.standardizedFileURL else { return }
            store = NotesStore(root: url)
            todayID = NoteCadence.dayFilename(for: Date())
            viewingID = todayID
            showingLogbook = false
            period = .daily
            lastRolloverDate = Date()
            itemCount = 0
            lastDeletedTrashEntryID = nil
            // Folder identity changed, so drafts and calendar state belong to the old collection.
            window.contentView = nil
            navigator?.contentView = nil
            store.ensureNote(stack: NoteCadence.dailyStack, filename: todayID,
                             title: NoteCadence.dayTitle(for: Date()))
            refreshNow()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t use that notes folder"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// ⌘Z (`AppWindow.onUndo`): restores the single most recent deletion straight back into the
    /// note it came from. A no-op if there's nothing to undo, or if it's already been undone once
    /// (one level, not a stack -- ADR 0011).
    private func undoLastDelete() {
        guard let entryID = lastDeletedTrashEntryID else { return }
        lastDeletedTrashEntryID = nil
        store.restoreFromTrash(entryID)
        refreshNow()
    }

    // MARK: - Reading the store -> rendering

    /// A write updates the file immediately, but the window only shows the change once this
    /// (and `render()`) run -- which otherwise only happens on the next up-to-2-second poll tick.
    /// Called right after every write that should be felt instantly instead of waiting on the
    /// poll. Internal, not private, so a future caller outside this file could trigger it too.
    func refreshNow() {
        checkForRollover()

        // Snapshot anything changed from outside this app's own write methods -- a hand-edit, or
        // the motivating case, an AI session editing today's note directly after the person
        // approves it elsewhere (ADR 0021) -- before reading it for display. Must run first:
        // reading below would otherwise just see the new content with no record of the old. No
        // in-app UI shows these snapshots anymore (ADR 0022) -- they just sit in `.history/` as a
        // safety net, reachable by hand via "Reveal Notes Folder" if ever actually needed.
        store.reconcileExternalChanges(stack: NoteCadence.dailyStack)

        store.reconcileExternalChanges(stack: NoteCadence.weeklyStack)
        store.reconcileExternalChanges(stack: "Logbook")
        let freshNote = showingLogbook ? store.loadLogbook() : store.loadNotes(stack: period.stack).first { $0.id == viewingID }
        if let freshNote {
            if !showingLogbook, itemCount > 0, freshNote.items.count > itemCount {
                Notifier.noteGrew(freshNote, from: itemCount)
            }
            itemCount = freshNote.items.count
        }
        note = freshNote
        render()
    }

    /// If real time has crossed into a new day since the last check, makes sure the new day's
    /// note exists -- a long-running session (this app is meant to be left open) rolls over on
    /// its own instead of silently continuing to think a stale date is still today. Only swaps
    /// the *view* over to the new note if the person was actually looking at today (ADR 0023) --
    /// someone who navigated away to browse an earlier or later day shouldn't get yanked back to
    /// a different note out from under them just because midnight passed.
    private func checkForRollover() {
        let now = Date()
        let freshTodayID = NoteCadence.dayFilename(for: now)
        guard freshTodayID != todayID else { return }
        store.ensureNote(stack: NoteCadence.dailyStack, filename: freshTodayID, title: NoteCadence.dayTitle(for: now))
        if !showingLogbook {
            let next = period.rollover(viewingID: viewingID, previousDate: lastRolloverDate, now: now)
            if next != viewingID {
                viewingID = next
                store.ensureNote(stack: period.stack, filename: next, title: period.title(for: now))
                itemCount = 0
            }
        }
        todayID = freshTodayID
        lastRolloverDate = now
    }

    // MARK: - Daily/weekly navigation

    private func navigate(by direction: Int) {
        let base = NoteCadence.date(fromFilename: viewingID) ?? Date()
        guard let target = Calendar.current.date(byAdding: .day, value: direction * period.stepDays, to: base) else { return }
        goToDate(target, period: period)
    }

    private func goToDate(_ date: Date, period targetPeriod: NotePeriod = .daily) {
        let id = targetPeriod.filename(for: date)
        guard showingLogbook || targetPeriod != period || id != viewingID else { return }
        showingLogbook = false
        period = targetPeriod
        store.ensureNote(stack: period.stack, filename: id, title: period.title(for: date))
        viewingID = id
        itemCount = 0
        refreshNow()
    }

    private func toggleNavigator() {
        if let navigator, navigator.isVisible { navigator.orderOut(nil); return }
        if navigator == nil {
            let panel = AppWindow()
            navigator = panel
            window.addChildWindow(panel, ordered: .above)
        }
        renderNavigator()
        guard let navigator else { return }
        let screen = window.screen?.visibleFrame ?? window.frame
        let x = min(max(window.frame.minX, screen.minX), screen.maxX - navigator.frame.width)
        let y = min(max(window.frame.maxY - 30, screen.minY), screen.maxY - navigator.frame.height)
        navigator.setFrameOrigin(NSPoint(x: x, y: y))
        navigator.makeKeyAndOrderFront(nil)
    }

    private func renderNavigator() {
        guard let navigator else { return }
        let view = NavigatorView(date: NoteCadence.date(fromFilename: viewingID) ?? Date(), period: period,
            onDate: { [weak self] date, period in self?.goToDate(date, period: period) },
            onLogbook: { [weak self] in
                self?.showingLogbook = true
                self?.itemCount = 0
                self?.refreshNow()
            }, onChooseNotesFolder: { [weak self] in self?.chooseNotesFolder() },
            onClose: { [weak self] in self?.navigator?.orderOut(nil) })
        if let hosting = navigator.contentView as? ClickThroughHostingView<NavigatorView> {
            hosting.rootView = view
        } else { navigator.contentView = ClickThroughHostingView(rootView: view) }
        if let hosting = navigator.contentView { navigator.setContentSize(hosting.fittingSize) }
    }

    /// A small AppKit modal -- a date picker, same idiom `AppDelegate`'s old "New Stack…" prompt
    /// used -- shared by "Go to Date…" and the per-item "Choose Date…" transfer option below.
    /// Defaults to whichever day is currently on screen, not always today, so repeatedly nudging
    /// a far-off date doesn't mean retyping the whole thing from today each time. Returns nil if
    /// cancelled.
    private func promptForDate(message: String) -> Date? {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay]
        picker.dateValue = NoteCadence.date(fromFilename: viewingID) ?? Date()
        alert.accessoryView = picker
        window.makeKeyAndOrderFront(nil)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return picker.dateValue
    }

    // MARK: - Copy/move an item to another day (ADR 0026)

    /// Resolves a relative/arbitrary transfer target to an actual date -- always relative to the
    /// *real* current date (`Date()`), never to whichever day is currently on screen, same
    /// reasoning the original per-item move menu used (ADR 0019): "move to Tomorrow" while
    /// looking at last Tuesday's note still means the real tomorrow. Returns nil if `.chooseDate`
    /// was cancelled.
    private func resolveTransferDate(_ target: ItemTransferTarget) -> Date? {
        let now = Date()
        switch target {
        case .today: return now
        case .tomorrow: return Calendar.current.date(byAdding: .day, value: 1, to: now)
        case .yesterday: return Calendar.current.date(byAdding: .day, value: -1, to: now)
        case .chooseDate: return promptForDate(message: "Choose Date")
        }
    }

    private func transferItem(_ item: NoteItem, action: ItemTransferAction, target: ItemTransferTarget) {
        guard let date = resolveTransferDate(target) else { return } // .chooseDate, cancelled
        let destinationID = NoteCadence.dayFilename(for: date)
        guard period != .daily || destinationID != viewingID else { return } // already there -- nothing to do
        let destinationTitle = NoteCadence.dayTitle(for: date)
        switch action {
        case .move:
            store.moveItem(
                item, fromStack: period.stack, fromNoteID: viewingID,
                toStack: NoteCadence.dailyStack, toNoteID: destinationID, toNoteTitle: destinationTitle
            )
        case .copy:
            store.copyItem(
                item, fromStack: period.stack, fromNoteID: viewingID,
                toStack: NoteCadence.dailyStack, toNoteID: destinationID, toNoteTitle: destinationTitle
            )
        }
        refreshNow()
    }

    private func render() {
        renderNavigator()
        guard let note else { return }
        let noteID = note.id
        let stack = period.stack
        let view = PaneView(
            note: note,
            readOnly: showingLogbook,
            period: period,
            onToggle: { [weak self] item in
                self?.store.toggleItem(stack: stack, noteID: noteID, noteTitle: note.title, item: item)
                self?.refreshNow()
            },
            onAddItem: { [weak self] text in
                guard let self else { return }
                self.store.addItem(stack: stack, noteID: noteID, text: text)
                // We just added exactly one item ourselves -- bump itemCount preemptively so
                // refreshNow() doesn't mistake our own addition for an externally-added line and
                // fire a pointless "note grew" notification.
                self.itemCount = note.items.count + 1
                self.refreshNow()
            },
            onEditItem: { [weak self] item, text in
                self?.store.editItem(stack: stack, noteID: noteID, item: item, text: text)
                self?.refreshNow()
            },
            onDeleteItem: { [weak self] item in
                guard let self else { return }
                self.lastDeletedTrashEntryID = self.store.deleteItem(
                    stack: stack, noteID: noteID, noteTitle: note.title, item: item
                )
                self.refreshNow()
            },
            onReorderItems: { [weak self] newOrder in
                self?.store.reorderItems(stack: stack, noteID: noteID, newOrder: newOrder)
                self?.refreshNow()
            },
            onSetColor: { [weak self] color in
                self?.store.setColor(stack: stack, noteID: noteID, color: color)
                self?.refreshNow()
            },
            onTransferItem: { [weak self] item, action, target in
                self?.transferItem(item, action: action, target: target)
            },
            onPreviousDay: { [weak self] in self?.navigate(by: -1) },
            onNextDay: { [weak self] in self?.navigate(by: 1) },
            onPickDate: { [weak self] in self?.toggleNavigator() },
            onClose: { [weak self] in self?.toggleVisibility() }, // there's nothing else to close back to
            onCycleTheme: { [weak self] in
                Theme.cycleToNext()
                self?.refreshNow() // rebuild the view with the new palette -- no store write involved
            }
        )
        // Update the existing hosting view's rootView rather than replacing it outright --
        // SwiftUI preserves @State across a rootView update (same view identity) -- an
        // in-progress item edit shouldn't get wiped mid-keystroke by the 2-second poll.
        let hosting: ClickThroughHostingView<PaneView>
        if let existing = window.contentView as? ClickThroughHostingView<PaneView> {
            existing.rootView = view
            hosting = existing
        } else {
            hosting = ClickThroughHostingView(rootView: view)
            window.contentView = hosting
        }
        hosting.onNavigate = showingLogbook ? nil : { [weak self] direction in self?.navigate(by: direction) }
        // The window isn't resizable anymore (ADR 0022) -- it's always exactly the size of the
        // one note it shows, same technique the very first version of this app used before the
        // multi-pane detour (setContentSize from the hosting view's own fitting size).
        let origin = window.frame.origin
        window.setContentSize(hosting.fittingSize)
        window.setFrameOrigin(origin) // setContentSize keeps the bottom-left corner fixed by
        // default already, but pin it explicitly rather than relying on that implicit behavior
    }

    private func centerWindow() {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = window.frame.size
        window.setFrameOrigin(CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
    }
}
