# TempurAI

Frictionless capture from anywhere to your LLMs.

TempurAI is a macOS menu bar tool that removes the back-and-forth friction when moving context (text, screenshots, files) from PDFs, decks, websites, and other apps into web-based LLMs like ChatGPT. Think of it as “the capture surface” that IDEs like Cursor give you natively—now available system-wide for everything else you work with.

- Always-available menu bar popover
- Drag & drop anything (text, images, files)
- Organize into lightweight “Collections” before sending
- Copy everything in one go and paste into ChatGPT/Claude/etc.
- Zero cloud dependency; everything stored locally

---

## Why TempurAI?

LLMs are incredible once you get your context in. The problem is getting it in. Moving between PDF viewers, browsers, slide decks, and tools creates tedious copy/paste cycles and fragments your thought process. TempurAI compresses that workflow into one focused flow:

1) Capture context fast (drag/drop or paste)
2) Curate it once (reorder, prune)
3) Send it to your LLM of choice in a single paste

You stay in flow. Your model gets better prompts. Everyone wins.

---

## Features

- Menu Bar Popover
  - Click the 🍣 icon to open the capture surface instantly.
  - Prominent Close button to dismiss quickly.

- Drag & Drop Capture
  - Drop text, images, or files directly into the popover.
  - Text files load as text; image files load as images.
  - Mixed content supported.

- Paste Box
  - Stage text with ⌘V, then press “Save text” (or ⌘↩) to commit to the active collection.

- Collections
  - Create and switch between collections to group related context.
  - Simple selection sheet with “Use Existing” or “Create New”.

- Quick Reorder
  - Hover an item to reveal Up/Down buttons for precise ordering.
  - Items at the top/bottom intelligently disable movement in those directions.

- Copy All
  - Consolidates the active collection into one paste ready for ChatGPT/Claude/etc.
  - Images currently appear in the combined clipboard as placeholders like “[Image 1]” to preserve order and context.

- Local and Private
  - Your data stays on-device (UserDefaults with JSON encoding for assets).
  - No network calls or accounts required.

---

## Install & Run

Requirements:
- macOS 13+ (Ventura or newer recommended)
- Swift toolchain (Xcode 15+ recommended)

Build and run:
- Using SwiftPM:
  - `swift run`
- Using Xcode:
  - Open `Package.swift` in Xcode and run the `tempur` target.

You’ll see a 🍣 icon appear in the macOS menu bar. Click it to open the TempurAI popover.

---

## Usage

- Open:
  - Click the 🍣 menu bar icon to toggle the popover.

- Choose a Collection:
  - First run will ask you to create or pick a collection.
  - Switch collections later via the “Collections” header menu.

- Capture:
  - Drag & drop text, images, or files into the “Collect to this board” card.
  - Or paste text into the editor and press “Save text” (or ⌘↩).

- Curate:
  - Hover saved items and use ↑/↓ to reorder.
  - Delete items via the trash button.
  - “Clear” removes all items in the active collection.

- Send:
  - Use “Copy All” to place everything (in order) onto your clipboard.
  - Paste into ChatGPT/Claude or any LLM UI.

- Close:
  - Click the Close button in the header to dismiss the popover.

Tips:
- Consider one collection per task (e.g., “Quarterly Review”, “Vendor Research”, “Paper Summary”).
- Reorder strategically—front-load the most important context to guide the model.

---

## Keyboard & Interactions

- Paste staged text: ⌘V (into the text box)
- Save staged text: ⌘↩
- Hover actions on items: Trash, Move Up, Move Down
- Close the popover: Close button in header

---

## Roadmap

- One-click send to ChatGPT/Claude (open model UI, auto-focus, paste)
- Global hotkey to toggle the popover
- Browser Share Extension (Safari/Chrome) and Services integration
- OCR for PDFs/screenshots to extract text
- Rich “Copy All” with Markdown, image captions, and source attribution
- Multi-select operations (batch delete, batch move)
- Encrypted sync across devices
- Smarter deduplication and snippet tagging

Have a feature request? Please open an issue.

---

## Architecture Overview

High level:
- Status Bar + Popover: Always-available capture surface
- SwiftUI views render the UI and handle user interactions
- ObservableObject store manages state and persistence

Key components:
- AppDelegate + StatusBarController
  - Creates the `NSStatusItem` (🍣) and shows an `NSPopover` with the SwiftUI content.
  - Handles Close requests via a NotificationCenter event.

- CollectorView (SwiftUI)
  - Main UI: header, capture card, saved items card, onboarding.
  - Presents collection management sheet.

- CollectionStore (ObservableObject)
  - Manages `collections`, `activeCollectionID`, and `items`.
  - Persists via `UserDefaults` (keys: `tempur.collections`, `tempur.activeCollectionID`).
  - Encodes images as PNG, stored alongside text content.

- Models
  - `ScrapCollection`: id, name, createdAt, items.
  - `CollectedItem`: id, timestamp, content.
  - `CollectedContent`: `.text(String)` | `.image(NSImage)`

- Notable Views
  - `DropZoneView`: animated drop target for files/images/text.
  - `PasteBoxView`: staged text capture with save action.
  - `CollectedItemsList`, `CollectedItemRow`: list and item UI, reordering controls.
  - `CollectionSelectionView`: sheet to switch/create collections.

---

## Privacy

- Local-first by design. No network calls.
- Data persists on-device in UserDefaults as JSON blobs (images stored as PNG).
- You can delete items or clear a collection at any time.

---

## Troubleshooting

- I don’t see the 🍣 icon:
  - Ensure the app built successfully and is running.
  - macOS may group menu extras—adjust your menu bar items or restart the app.

- Drag & drop isn’t doing anything:
  - Confirm you’re dropping onto the highlighted drop zone.
  - Try a simple text file or image first to sanity-check.

- Reordering isn’t reflected:
  - You must hover the item to reveal the up/down controls; items at the top/bottom can’t move past boundaries.
  - Use “Copy All” after reordering; the order is preserved in the clipboard.

- Copy All doesn’t include image pixels:
  - Current “Copy All” consolidates text and uses `[Image N]` placeholders for images to preserve context and order. Full rich content export is on the roadmap.

---

## Contributing

- Clone the repo, run with `swift run`.
- Submit issues with clear reproduction steps and environment details.
- PRs welcome—please keep changes focused and include rationale.

---

## License

MIT License

Copyright (c) 2025 setrf

This project is licensed under the MIT License. See LICENSE for details.
## Screenshots (Optional)

- Collections sheet with selection and create-new
- Capture card with drop zone and paste box
- Saved items with hover controls (reorder, delete)

Add screenshots to showcase real workflows (PDF + web article + deck → “Copy All” → paste into ChatGPT).

---

## Credits

Inspired by the ergonomics of IDE-integrated LLMs (e.g., Cursor) and designed to bring that “frictionless context handoff” to the rest of your desktop workflow.
