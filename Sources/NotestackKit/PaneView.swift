import SwiftUI

enum ItemTransferAction {
    case move, copy
}

enum ItemTransferTarget {
    case today, tomorrow, yesterday, chooseDate
}

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


    private var accentColor: Color { note.color?.swiftUIColor ?? Theme.neutralGlow }

    private var textColor: Color { Theme.textPrimary }

    private var dimTextColor: Color { Theme.textDim }

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
    }


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

    private func commitItemEdit(_ item: NoteItem) {
        let trimmed = itemDraft.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            onDeleteItem(item)
        } else {
            onEditItem(item, itemDraft)
        }
        editingItemID = nil
    }

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
