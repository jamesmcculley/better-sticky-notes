import SwiftUI

/// Which direction a per-item transfer (ADR 0026) goes: leave the original in place and duplicate
/// it elsewhere, or remove it from here and relocate it there. The same four `ItemTransferTarget`
/// options apply either way -- "copy this to yesterday" is just as sensible as "move this to
/// tomorrow."
enum ItemTransferAction {
    case move, copy
}

/// Where a transferred item goes -- relative to the real current date (`AppController.
/// resolveTransferDate`), not whichever day happens to be on screen. `.chooseDate` opens the same
/// date-picker modal "Go to Date…" uses.
enum ItemTransferTarget {
    case today, tomorrow, yesterday, chooseDate
}

/// The one sticky note this app ever shows (ADR 0022) -- one day's note at a time, navigable to
/// any other day (ADR 0023: ◀/▶, scroll, ←/→, or a date picker), but still never more than one
/// note on screen, and no sidebar, no other panes. Completing a task/checklist item copies it to
/// a running Logbook file in addition to marking it done in place (ADR 0026) -- see `NotesStore.
/// toggleItem`. An item (open or done) can also be copied or moved to another day via a
/// hover-revealed menu (ADR 0026) -- there's still only ever one note open at a time, so this
/// doesn't bring back a second visible pane, just a destination picked blind. No history-restore
/// menu (the safety-net snapshot mechanism still runs, just silently -- see `AppController`).
///
/// Reordering (ADR 0012/0014/0015) uses hover-revealed ▲▼ buttons, not drag -- see ADR 0015.
struct PaneView: View {
    let note: Note
    var readOnly = false
    var period: NotePeriod = .daily
    var onToggle: (NoteItem) -> Void = { _ in }
    var onAddItem: (String) -> Void = { _ in }
    var onEditItem: (NoteItem, String) -> Void = { _, _ in }
    var onDeleteItem: (NoteItem) -> Void = { _ in }
    var onReorderItems: ([String]) -> Void = { _ in }
    var onSetColor: (NoteColor?) -> Void = { _ in }
    var onTransferItem: (NoteItem, ItemTransferAction, ItemTransferTarget) -> Void = { _, _, _ in }
    var onPreviousDay: () -> Void = {}
    var onNextDay: () -> Void = {}
    var onPickDate: () -> Void = {}
    var onClose: () -> Void = {}
    var onCycleTheme: () -> Void = {}

    @State private var editingItemID: String?
    @State private var itemDraft = ""
    @State private var hoveredItemID: String?
    @State private var isAddingItem = false
    @State private var newItemDraft = ""
    @FocusState private var addItemFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            scanline

            VStack(alignment: .leading, spacing: 6) {
                header

                if note.items.isEmpty {
                    Text("Nothing here")
                        .font(.system(size: 13))
                        .foregroundStyle(dimTextColor)
                } else {
                    if readOnly {
                        ScrollView { itemList }
                            .frame(height: min(CGFloat(note.items.count) * 65, 450))
                    } else { itemList }
                }

                if !readOnly { addItemRow }
            }
            .padding(14)
        }
        .frame(width: 240, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .background(Theme.paneBase.opacity(0.88), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accentColor.opacity(0.7), lineWidth: 1.25))
        .overlay(alignment: .bottomTrailing) { themeCycleButton }
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        .shadow(color: accentColor.opacity(0.35), radius: 14)
        // Navigating to a different day (ADR 0023) reuses this same view's @State (SwiftUI
        // preserves it across a rootView update by identity, same reasoning as everywhere else
        // this matters) -- but an in-progress edit/add-item draft was about a specific item in
        // the *previous* day's note, and has no meaning once `note.id` changes out from under it.
        // Reset rather than silently carry a stale draft into a different note.
        .onChange(of: "\(readOnly ? "Logbook" : period.stack)/\(note.id)") { _, _ in
            editingItemID = nil
            isAddingItem = false
            newItemDraft = ""
        }
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(note.items) { item in itemRow(item).disabled(readOnly) }
        }
    }

    // MARK: - Color (ADR 0008; cyberpunk accent glow, ADR 0020)

    /// The one color per note that everything else here derives from: the neon border, the glow,
    /// the unchecked-item icons -- a cyberpunk HUD reads by its accent color, not its fill, so
    /// `note.color` doesn't change the note's *background* at all (always the same fixed dark
    /// glass, `Theme.paneBase`), only this.
    private var accentColor: Color { note.color?.swiftUIColor ?? Theme.neutralGlow }

    private var textColor: Color { Theme.textPrimary }

    private var dimTextColor: Color { Theme.textDim }

    /// Cycles the whole app's theme -- fill, default glow, text tones (ADR 0024) -- one click at
    /// a time, wrapping back to the first after the last; no menu, just a button. Tucked into the
    /// note's own corner (`.overlay(alignment: .bottomTrailing)` on the whole pane) rather than
    /// the header, which is already fairly full of day-navigation/color/close controls. Small and
    /// low-contrast on purpose -- a theme switcher is a "find it once, rarely touch it again"
    /// control, not something that should compete for attention with the note's actual content.
    private var themeCycleButton: some View {
        Button(action: onCycleTheme) {
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 10))
                .foregroundStyle(dimTextColor.opacity(0.7))
        }
        .buttonStyle(.plain)
        .padding(8)
        .help("Change theme (\(Theme.current.name))")
    }

    /// A thin glowing bar across the very top of the card, inside the border -- the one purely
    /// decorative HUD touch, cheap to render and the clearest single signal that this isn't a
    /// plain pastel index card.
    private var scanline: some View {
        LinearGradient(
            colors: [accentColor.opacity(0.05), accentColor.opacity(0.9), accentColor.opacity(0.05)],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 2)
        .clipShape(RoundedRectangle(cornerRadius: 1))
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    // MARK: - Header: day navigation, title (doubles as the date picker), color, close

    /// Day navigation (ADR 0023/0024): ◀/▶ flank the title directly, and the title itself --
    /// the day's full date, e.g. "Thu, Nov 5, 2026" -- opens the date picker when tapped, rather
    /// than a separate calendar icon off to the side. Scroll (`ClickThroughHostingView.
    /// onNavigate`) and ←/→ (`AppWindow.onNavigate`) cover the same ground without needing any
    /// on-screen control at all, so the arrows are a visible, discoverable affordance more than
    /// the only way in.
    private var header: some View {
        HStack(alignment: .top, spacing: 4) {
            Button(action: onPreviousDay) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(period == .daily ? "Previous day" : "Previous week")

            Text(note.title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(accentColor)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .center)
                .onTapGesture(perform: onPickDate)
                .help("Go to date…")

            Button(action: onNextDay) {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(period == .daily ? "Next day" : "Next week")

            if !readOnly { colorMenu }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(dimTextColor)
            }
            .buttonStyle(.plain)
            .help("Hide (⌘⇧F to bring back)")
        }
        .foregroundStyle(dimTextColor)
    }

    private var colorMenu: some View {
        Menu {
            Button(note.color == nil ? "✓ Default" : "Default") { onSetColor(nil) }
            ForEach(NoteColor.allCases, id: \.self) { color in
                Button(color == note.color ? "✓ \(color.displayName)" : color.displayName) { onSetColor(color) }
            }
        } label: {
            Circle()
                .fill(note.color?.swiftUIColor ?? Theme.paneBase)
                .frame(width: 11, height: 11)
                .overlay(Circle().strokeBorder(accentColor.opacity(0.8), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Color")
    }

    // MARK: - Add item (ADR 0009: collapsed to a small "+" until clicked)

    @ViewBuilder
    private var addItemRow: some View {
        if isAddingItem {
            TextField("Add item…", text: $newItemDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($addItemFieldFocused)
                .onSubmit(commitNewItem)
                .onExitCommand { // Escape: clear and collapse back to "+"
                    newItemDraft = ""
                    isAddingItem = false
                }
                .onChange(of: addItemFieldFocused) { _, focused in
                    if !focused && newItemDraft.trimmingCharacters(in: .whitespaces).isEmpty {
                        isAddingItem = false
                    }
                }
                .help("Start with \"()\" for a task, \"[]\" for a checklist, or nothing for a bullet point")
        } else {
            Button {
                isAddingItem = true
                addItemFieldFocused = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                    Text("Add item").font(.system(size: 12))
                }
                .foregroundStyle(dimTextColor)
            }
            .buttonStyle(.plain)
        }
    }

    private func commitNewItem() {
        guard !newItemDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onAddItem(newItemDraft)
        newItemDraft = "" // stays open (doesn't collapse) for the next item -- fast repeated
        // capture: keep the field ready for repeated entry.
    }

    // MARK: - Items (ADR 0007: kind; ADR 0009: editing existing text; ADR 0019: done-date)

    @ViewBuilder
    private func itemRow(_ item: NoteItem) -> some View {
        if editingItemID == item.id {
            TextField("Item", text: $itemDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { commitItemEdit(item) }
                .onExitCommand { editingItemID = nil } // Escape cancels, discards the draft
        } else {
            HStack(alignment: .top, spacing: 6) {
                if item.kind == .bullet {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(dimTextColor)
                        .padding(.top, 4)
                } else {
                    Button { onToggle(item) } label: {
                        Image(systemName: icon(for: item))
                            .font(.system(size: 12))
                            .foregroundStyle(item.done ? dimTextColor : accentColor)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title)
                        .font(.system(size: 13))
                        .foregroundStyle(item.done ? dimTextColor : textColor)
                        .strikethrough(item.kind != .bullet && item.done)
                        .lineLimit(2)
                        .onTapGesture {
                            guard !readOnly else { return }
                            itemDraft = shorthand(for: item)
                            editingItemID = item.id
                        }
                    // Only shown once the item is actually done -- a stray doneDate left over from
                    // hand-editing the raw shorthand (re-typing "()" over an already-"@done"-tagged
                    // line without also removing the tag) shouldn't surface as if it still applied.
                    if item.done, let doneDate = item.doneDate {
                        Text(Self.doneDateFormatter.string(from: doneDate))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(dimTextColor)
                    }
                }

                if !readOnly && hoveredItemID == item.id {
                    Spacer(minLength: 4)
                    transferMenu(for: item)
                    moveButtons(for: item)
                    Button { onDeleteItem(item) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(dimTextColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onHover { hovering in
                hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
            }
        }
    }

    private static let doneDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy HH:mm:ss"
        formatter.timeZone = .current
        return formatter
    }()

    /// "Copy / move an open (or closed) task to another day" (ADR 0026) -- a hover-revealed
    /// `Menu`, same idiom as the delete "×" and move ▲▼ buttons right next to it, grouped into
    /// Move/Copy sections so both directions are reachable from one icon rather than two.
    /// Available on every item regardless of done state -- deferring an unfinished task to
    /// tomorrow and duplicating an already-done one onto another day are both reasonable.
    private func transferMenu(for item: NoteItem) -> some View {
        Menu {
            Section("Move") {
                Button("Today") { onTransferItem(item, .move, .today) }
                Button("Tomorrow") { onTransferItem(item, .move, .tomorrow) }
                Button("Yesterday") { onTransferItem(item, .move, .yesterday) }
                Button("Choose Date…") { onTransferItem(item, .move, .chooseDate) }
            }
            Section("Copy") {
                Button("Today") { onTransferItem(item, .copy, .today) }
                Button("Tomorrow") { onTransferItem(item, .copy, .tomorrow) }
                Button("Yesterday") { onTransferItem(item, .copy, .yesterday) }
                Button("Choose Date…") { onTransferItem(item, .copy, .chooseDate) }
            }
        } label: {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 11))
                .foregroundStyle(dimTextColor)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Copy or move to another day…")
    }

    /// Plain button taps (ADR 0015), not a drag gesture -- swaps `item` with its immediate
    /// neighbor and sends the whole resulting order to `onReorderItems`. Disabled instead of
    /// hidden at either end of the list, so the row doesn't jump width depending on position.
    private func moveButtons(for item: NoteItem) -> some View {
        let ids = note.items.map(\.id)
        let index = ids.firstIndex(of: item.id) ?? 0
        return HStack(spacing: 2) {
            Button { reorder(item, by: -1) } label: {
                Image(systemName: "chevron.up").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(index == 0)

            Button { reorder(item, by: 1) } label: {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(index == ids.count - 1)
        }
        .foregroundStyle(dimTextColor)
    }

    private func reorder(_ item: NoteItem, by offset: Int) {
        var ids = note.items.map(\.id)
        guard let index = ids.firstIndex(of: item.id) else { return }
        let newIndex = index + offset
        guard ids.indices.contains(newIndex) else { return }
        ids.swapAt(index, newIndex)
        onReorderItems(ids)
    }

    /// Clearing the text entirely and pressing Return deletes the item, rather than being
    /// silently rejected (ADR 0010).
    private func commitItemEdit(_ item: NoteItem) {
        let trimmed = itemDraft.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            onDeleteItem(item)
        } else {
            onEditItem(item, itemDraft)
        }
        editingItemID = nil
    }

    /// The shorthand form shown while editing -- includes done state (`(x)`/`[x]`, not just
    /// `()`/`[]`) so resubmitting an edit *unchanged* doesn't silently uncheck an already-done
    /// item, and (ADR 0019) includes the `@done(...)` tag too, for the same reason: a typo fix on
    /// an already-done item shouldn't silently drop its done-date. `NotesStore.markdownLine(for:)`
    /// just carries any trailing text through verbatim, so this round-trips correctly with no
    /// special-casing needed on the write side.
    private func shorthand(for item: NoteItem) -> String {
        let doneTag = item.doneDate.map { " @done(\(Self.doneDateTagFormatter.string(from: $0)))" } ?? ""
        switch item.kind {
        case .task: return "(\(item.done ? "x" : " ")) \(item.title)\(doneTag)"
        case .checklist: return "[\(item.done ? "x" : " ")] \(item.title)\(doneTag)"
        case .bullet: return item.title
        }
    }

    private static let doneDateTagFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    private func icon(for item: NoteItem) -> String {
        switch item.kind {
        case .checklist: return item.done ? "checkmark.square.fill" : "square"
        case .task: return item.done ? "checkmark.circle.fill" : "circle"
        case .bullet: return "circle.fill" // unreached here (handled above); kept so the switch stays exhaustive
        }
    }
}
