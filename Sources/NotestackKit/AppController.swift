import AppKit
import SwiftUI

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

    private var todayID = NoteCadence.dayFilename(for: Date())

    private var viewingID: String

    init(store: NotesStore) {
        self.store = store
        self.viewingID = todayID
    }

    private var lastDeletedTrashEntryID: String?

    func start() {
        window = AppWindow()
        window.onUndo = { [weak self] in self?.undoLastDelete() }
        window.onNavigate = { [weak self] direction in self?.navigate(by: direction) }
        store.ensureNote(stack: NoteCadence.dailyStack, filename: todayID, title: NoteCadence.dayTitle(for: Date()))

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

    private func undoLastDelete() {
        guard let entryID = lastDeletedTrashEntryID else { return }
        lastDeletedTrashEntryID = nil
        store.restoreFromTrash(entryID)
        refreshNow()
    }


    func refreshNow() {
        checkForRollover()

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
        let hosting: ClickThroughHostingView<PaneView>
        if let existing = window.contentView as? ClickThroughHostingView<PaneView> {
            existing.rootView = view
            hosting = existing
        } else {
            hosting = ClickThroughHostingView(rootView: view)
            window.contentView = hosting
        }
        hosting.onNavigate = showingLogbook ? nil : { [weak self] direction in self?.navigate(by: direction) }
        let origin = window.frame.origin
        window.setContentSize(hosting.fittingSize)
        window.setFrameOrigin(origin) // setContentSize keeps the bottom-left corner fixed by
    }

    private func centerWindow() {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = window.frame.size
        window.setFrameOrigin(CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
    }
}
