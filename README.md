# Better Sticky Notes

A native macOS sticky-note app (installed as **Notestack**) with daily notes,
Monday-start weekly notes, a completion Logbook, and 35 color themes.
Notes are local Markdown files. No account or network connection is required.

## Install

Requires **macOS 14 or newer**.

Download `Notestack-macOS-arm64.zip` from this repository’s **Releases** page,
unzip it, and drag `Notestack.app` into Applications. This download is for
Apple Silicon Macs. The app is ad-hoc signed, not Apple-notarized; if macOS
blocks it, review it in **System Settings → Privacy & Security → Open Anyway**.

To build on your Mac instead (including Intel Macs), install Apple’s Command
Line Tools with `xcode-select --install`, download and unzip this repository’s
source, then run these commands from its folder:

```sh
swift run notestackChecks
./scripts/bundle.sh
open /Applications/Notestack.app
```

The install script requires write access to Applications. To create the app
without installing it, run `./scripts/bundle.sh --package-only`; the app is
written to `build/Notestack.app`.

## Use

- **Show/hide:** ⌘⇧F, or the app’s menu-bar icon.
- **Navigate:** click the note title. Choose **Daily**, **Weekly**, or **Logbook**.
  **Today** and **This Week** jump to the current period. Arrows and scrolling
  move one day or week. Only one note is displayed at a time.
- **Add:** click Add item. Type `() task`, `[] checklist`, or plain text for a bullet.
- **Edit:** click item text; Return saves and Escape cancels.
- **Complete:** click the circle or checkbox. A date/time stamp is added to the
  note and its Logbook copy. Reopening removes the stamp and matching Logbook entry.
- **Delete/reorder:** hover for × and ▲▼. ⌘Z restores the most recent deletion.
- **Copy/move:** use the item’s hover menu to send it to a daily date.
- **Colors:** use the header circle for note color and the corner palette button
  to cycle themes.
- **Storage:** click the title, then **Choose Notes Folder…**. Select the parent
  folder containing `Daily/`, `Weekly/`, and `Logbook/`. The default is
  `~/Documents/Notestack/`. Choosing a folder does not move existing files.
  **Reveal Notes Folder** in the menu-bar menu opens the current location.

You can edit the Markdown files externally; the app reloads changes while running.
Deleted items remain in `.trash/`, and external-edit snapshots in `.history/`.
The current day/week advances automatically at its boundary; historical notes
and the Logbook stay where you left them.
