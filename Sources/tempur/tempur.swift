import SwiftUI
import AppKit
import UniformTypeIdentifiers

private extension Notification.Name {
    static let tempurClosePopover = Notification.Name("tempurClosePopover")
}

@main
struct TempurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = CollectionStore()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let rootView = CollectorView(store: store)
        let hostingController = NSHostingController(rootView: rootView)

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.contentSize = NSSize(width: 380, height: 560)
        popover.contentViewController = hostingController

        statusBarController = StatusBarController(popover: popover)
    }
}

@MainActor
final class StatusBarController {
    private let popover: NSPopover
    private let statusItem: NSStatusItem

    init(popover: NSPopover) {
        self.popover = popover
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "🍣"
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "Tempur — Drop, paste, and collect snippets"
        }

        NotificationCenter.default.addObserver(self, selector: #selector(handleCloseRequest), name: .tempurClosePopover, object: nil)
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    @objc private func handleCloseRequest() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }

        if let existingWindow = popover.contentViewController?.view.window {
            existingWindow.makeKeyAndOrderFront(nil)
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class CollectionStore: ObservableObject {
    @Published private(set) var collections: [ScrapCollection]
    @Published private(set) var activeCollectionID: UUID?

    private let defaults = UserDefaults.standard
    private let collectionsKey = "tempur.collections"
    private let activeKey = "tempur.activeCollectionID"

    init() {
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: collectionsKey),
           let decoded = try? decoder.decode([ScrapCollection].self, from: data) {
            collections = decoded
        } else {
            collections = []
        }

        if let raw = defaults.string(forKey: activeKey), let id = UUID(uuidString: raw) {
            activeCollectionID = id
        } else {
            activeCollectionID = collections.first?.id
        }

        if activeCollection == nil {
            activeCollectionID = collections.first?.id
        }
    }

    var activeCollection: ScrapCollection? {
        collections.first { $0.id == activeCollectionID }
    }

    var activeItems: [CollectedItem] {
        activeCollection?.items ?? []
    }

    var hasActiveCollection: Bool {
        activeCollection != nil
    }

    var requiresCollectionSelection: Bool {
        !hasActiveCollection
    }

    func selectCollection(id: UUID) {
        guard collections.contains(where: { $0.id == id }) else { return }
        activeCollectionID = id
        persistState()
    }

    @discardableResult
    func createCollection(named rawName: String) -> ScrapCollection {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? suggestedCollectionName() : trimmed
        let collection = ScrapCollection(name: name)
        collections.insert(collection, at: 0)
        activeCollectionID = collection.id
        persistState()
        return collection
    }

    func addText(_ text: String) {
        guard var collection = activeCollection else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = CollectedItem(content: .text(trimmed))
        collection.items.insert(item, at: 0)
        apply(collection)
    }

    func addImage(_ image: NSImage) {
        guard var collection = activeCollection else { return }
        let item = CollectedItem(content: .image(image))
        collection.items.insert(item, at: 0)
        apply(collection)
    }

    func clear() {
        guard var collection = activeCollection else { return }
        collection.items.removeAll()
        apply(collection)
    }

    func deleteItem(id: UUID) {
        guard var collection = activeCollection else { return }
        collection.items.removeAll { $0.id == id }
        apply(collection)
    }

    func moveItem(from source: IndexSet, to destination: Int) {
        guard var collection = activeCollection else { return }
        collection.items.move(fromOffsets: source, toOffset: destination)
        apply(collection)
    }

    func moveItemUp(_ itemId: UUID) {
        guard var collection = activeCollection else { return }
        guard let currentIndex = collection.items.firstIndex(where: { $0.id == itemId }) else { return }

        if currentIndex > 0 {
            print("moveItemUp: id=\(itemId) from=\(currentIndex) -> \(currentIndex - 1) total=\(collection.items.count)")
            let item = collection.items.remove(at: currentIndex)
            collection.items.insert(item, at: currentIndex - 1)
            print("moveItemUp: completed id=\(itemId)")
            withAnimation {
                self.apply(collection)
            }
        } else {
            print("moveItemUp: blocked id=\(itemId) at top")
        }
    }

    func moveItemDown(_ itemId: UUID) {
        guard var collection = activeCollection else { return }
        guard let currentIndex = collection.items.firstIndex(where: { $0.id == itemId }) else { return }

        if currentIndex < collection.items.count - 1 {
            print("moveItemDown: id=\(itemId) from=\(currentIndex) -> \(currentIndex + 1) total=\(collection.items.count)")
            let item = collection.items.remove(at: currentIndex)
            collection.items.insert(item, at: currentIndex + 1)
            print("moveItemDown: completed id=\(itemId)")
            withAnimation {
                self.apply(collection)
            }
        } else {
            print("moveItemDown: blocked id=\(itemId) at bottom")
        }
    }

    func reorderItems(_ itemId: UUID, direction: ReorderDirection) {
        guard var collection = activeCollection else { return }
        guard let currentIndex = collection.items.firstIndex(where: { $0.id == itemId }) else { return }

        switch direction {
        case .up:
            if currentIndex > 0 {
                let newIndex = currentIndex - 1
                collection.items.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: newIndex)
                apply(collection)
            }
        case .down:
            if currentIndex < collection.items.count - 1 {
                let newIndex = currentIndex + 1
                collection.items.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: newIndex)
                apply(collection)
            }
        }
    }

    enum ReorderDirection {
        case up, down
    }

    func canMoveItemUp(_ itemId: UUID) -> Bool {
        guard let collection = activeCollection else { return false }
        guard let currentIndex = collection.items.firstIndex(where: { $0.id == itemId }) else { return false }
        return currentIndex > 0
    }

    func canMoveItemDown(_ itemId: UUID) -> Bool {
        guard let collection = activeCollection else { return false }
        guard let currentIndex = collection.items.firstIndex(where: { $0.id == itemId }) else { return false }
        return currentIndex < collection.items.count - 1
    }

    func suggestedCollectionName() -> String {
        let base = "Collection"
        let nextIndex = collections.count + 1
        var candidate = "\(base) \(nextIndex)"
        var counter = nextIndex
        let existingNames = Set(collections.map { $0.name.lowercased() })
        while existingNames.contains(candidate.lowercased()) {
            counter += 1
            candidate = "\(base) \(counter)"
        }
        return candidate
    }

    private func apply(_ updated: ScrapCollection) {
        guard let index = collections.firstIndex(where: { $0.id == updated.id }) else { return }
        print("apply: updating collection id=\(updated.id) items=\(updated.items.count)")
        collections[index] = updated
        objectWillChange.send()
        persistState()
    }

    private func persistState() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(collections) {
            defaults.set(data, forKey: collectionsKey)
        }

        if let id = activeCollectionID {
            defaults.set(id.uuidString, forKey: activeKey)
        } else {
            defaults.removeObject(forKey: activeKey)
        }
    }
}

struct ScrapCollection: Identifiable, Codable {
    let id: UUID
    var name: String
    let createdAt: Date
    var items: [CollectedItem]

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), items: [CollectedItem] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.items = items
    }
}

struct CollectedItem: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let content: CollectedContent

    init(id: UUID = UUID(), timestamp: Date = Date(), content: CollectedContent) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
    }
}

enum CollectedContent: Codable {
    case text(String)
    case image(NSImage)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case text
        case imagePNG
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let string):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(string, forKey: .value)
        case .image(let image):
            guard let data = image.pngData() else {
                throw EncodingError.invalidValue(image, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unable to encode image as PNG."))
            }
            try container.encode(Kind.imagePNG, forKey: .kind)
            try container.encode(data, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .text:
            let string = try container.decode(String.self, forKey: .value)
            self = .text(string)
        case .imagePNG:
            let data = try container.decode(Data.self, forKey: .value)
            guard let image = NSImage(data: data) else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: container, debugDescription: "Unable to recreate image from stored data.")
            }
            self = .image(image)
        }
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private enum CollectionSheetMode {
    case onboarding
    case manage
}

struct CollectorView: View {
    @ObservedObject var store: CollectionStore
    @State private var isTargeted = false
    @State private var stagedText = ""
    @State private var showCollectionSheet = false
    @State private var sheetMode: CollectionSheetMode = .manage

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 18, pinnedViews: [.sectionHeaders]) {
                Section {
                    VStack(alignment: .leading, spacing: 18) {
                        if store.hasActiveCollection {
                            captureCard
                            savedItemsCard
                        } else {
                            onboardingCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                } header: {
                    headerCard
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 560)
        .onAppear {
            if store.requiresCollectionSelection {
                sheetMode = .onboarding
                showCollectionSheet = true
            }
        }
        .sheet(isPresented: $showCollectionSheet) {
            CollectionSelectionView(store: store, mode: sheetMode)
        }
    }

    private var headerCard: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
                Image(systemName: "square.stack.3d.up.fill")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let status = headerStatusLine {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 6)

            if let summary = headerCollectionSummary {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Menu {
                if !store.collections.isEmpty {
                    Section("Switch to") {
                        ForEach(store.collections) { collection in
                            Button(collection.name) {
                                store.selectCollection(id: collection.id)
                            }
                        }
                    }
                }

                Button("New Collection…") {
                    sheetMode = .manage
                    showCollectionSheet = true
                }

                if !store.collections.isEmpty {
                    Button("Manage Collections…") {
                        sheetMode = .manage
                        showCollectionSheet = true
                    }
                }
            } label: {
                Label("Collections", systemImage: "chevron.down.circle")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
                    .font(.caption2)
            }
            .menuStyle(.borderlessButton)

            Button {
                NotificationCenter.default.post(name: .tempurClosePopover, object: nil)
            } label: {
                Label("Close", systemImage: "xmark.circle.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var captureCard: some View {
        CardContainer(
            title: "Collect to this board",
            subtitle: "Drag files or paste clipboard text directly into the active collection.",
            iconName: "tray.and.arrow.down.fill"
        ) {
            VStack(alignment: .leading, spacing: 18) {
                DropZoneView(isTargeted: $isTargeted) { providers in
                    guard ensureActiveCollectionAvailable() else { return false }
                    return handleDrop(providers: providers)
                }
                .frame(height: 164)

                Divider()
                    .padding(.horizontal, -6)

                PasteBoxView(text: $stagedText, canCommit: store.hasActiveCollection) {
                    commitStagedText()
                }
            }
        }
    }

    private var savedItemsCard: some View {
        CardContainer(
            title: "Saved items",
            subtitle: savedItemsSubtitle,
            iconName: "bookmark.square.fill",
            accessory: {
                HStack(spacing: 8) {
                    Button("Copy All", role: .none) {
                        copyAllItemsToClipboard()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(storeItems.isEmpty)

                    Button("Clear", role: .destructive) {
                        store.clear()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(storeItems.isEmpty)
                }
            }
        ) {
            if storeItems.isEmpty {
                PlaceholderListView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 16) {
                    CollectedItemsList(store: store)
                        .frame(maxHeight: .infinity)

                    Button {
                        copyAllItemsToClipboard()
                    } label: {
                        Label("Copy All to Clipboard", systemImage: "doc.on.doc.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
    }

    private var onboardingCard: some View {
        CardContainer(
            title: "Start a collection",
            subtitle: "Collections keep related inspiration together.",
            iconName: "square.stack.3d.forward.dottedline"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Create a fresh collection or reuse an existing board to begin collecting drops and pastes.")
                    .foregroundStyle(.secondary)

                Button {
                    sheetMode = .manage
                    showCollectionSheet = true
                } label: {
                    Label("Choose a collection", systemImage: "plus.circle.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }


    private var headerStatusLine: String? {
        if let created = store.activeCollection?.createdAt {
            return "Created \(RelativeDateTimeFormatter.presenting(created))"
        }
        if store.collections.isEmpty {
            return "No collections yet"
        }
        if store.hasActiveCollection {
            return nil
        }
        return "Select a collection"
    }

    private var headerDescription: String? {
        if !store.hasActiveCollection {
            return "Create a collection to start capturing inspiration."
        }
        return nil
    }

    private var headerCollectionSummary: String? {
        guard store.hasActiveCollection else { return nil }
        let itemCount = store.activeItems.count
        let itemText = itemCount == 1 ? "1 item" : "\(itemCount) items"
        return "\(itemText) saved"
    }

    private var headerTitle: String {
        store.activeCollection?.name ?? "Collections"
    }

    private var headerSubtitle: String {
        if let created = store.activeCollection?.createdAt {
            return "Created \(RelativeDateTimeFormatter.presenting(created))"
        }
        if store.collections.isEmpty {
            return "No collections yet • create one to start collecting."
        }
        return "Select a collection to start capturing drops."
    }

    private var savedItemsSubtitle: String {
        let count = storeItems.count
        if count == 0 {
            return "Nothing saved yet"
        }
        return count == 1 ? "1 item saved" : "\(count) items saved"
    }

    private var storeItems: [CollectedItem] {
        store.activeItems
    }

    private func ensureActiveCollectionAvailable() -> Bool {
        guard store.hasActiveCollection else {
            sheetMode = .onboarding
            showCollectionSheet = true
            return false
        }
        return true
    }

    private func commitStagedText() {
        guard ensureActiveCollectionAvailable() else { return }
        store.addText(stagedText)
        stagedText = ""
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handled = true
                loadImage(from: provider)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                loadFile(from: provider)
            } else if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                provider.loadObject(ofClass: NSString.self) { reading, _ in
                    if let text = reading as? NSString {
                        let captured = text as String
                        Task { @MainActor in
                            self.store.addText(captured)
                        }
                    }
                }
            }
        }

        return handled
    }

    private func loadImage(from provider: NSItemProvider) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data, let image = NSImage(data: data) else { return }
            Task { @MainActor in
                self.store.addImage(image)
            }
        }
    }

    private func loadFile(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let resolvedURL: URL?
            if let data = item as? Data {
                resolvedURL = URL(dataRepresentation: data, relativeTo: nil)
            } else if let url = item as? URL {
                resolvedURL = url
            } else if let url = item as? NSURL {
                resolvedURL = url as URL
            } else if let path = item as? String {
                resolvedURL = URL(fileURLWithPath: path)
            } else {
                resolvedURL = nil
            }

            guard let url = resolvedURL else { return }

            if let image = NSImage(contentsOf: url) {
                Task { @MainActor in
                    self.store.addImage(image)
                }
            } else if let text = try? String(contentsOf: url) {
                Task { @MainActor in
                    self.store.addText(text)
                }
            }
        }
    }

    private func copyAllItemsToClipboard() {
        let items = store.activeItems
        guard !items.isEmpty else { return }

        var clipboardContent = ""
        var hasImageContent = false

        // Format all items in order
        for (index, item) in items.enumerated() {
            switch item.content {
            case .text(let text):
                if index > 0 {
                    clipboardContent += "\n\n"
                }
                clipboardContent += text
            case .image:
                hasImageContent = true
                if index > 0 {
                    clipboardContent += "\n\n"
                }
                clipboardContent += "[Image \(index + 1)]"
            }
        }

        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if hasImageContent {
            // For images, we'll create a rich text format or HTML
            // For now, just copy the text representation
            pasteboard.setString(clipboardContent, forType: .string)
        } else {
            // Simple text content
            pasteboard.setString(clipboardContent, forType: .string)
        }

        // Show a subtle confirmation (optional)
        print("Copied \(items.count) items to clipboard")
    }


}


private struct DropZoneView: View {
    @Binding var isTargeted: Bool
    let dropHandler: ([NSItemProvider]) -> Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(backgroundGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(borderColor, style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                )
                .animation(.easeInOut(duration: 0.2), value: isTargeted)

            VStack(spacing: 8) {
                Image(systemName: isTargeted ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                Text(isTargeted ? "Drop to save" : "Drag & drop text or images")
                    .font(.headline)
                Text("Images, files, and snippets are all welcome")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .onDrop(of: [.fileURL, .image, .plainText, .utf8PlainText, .text], isTargeted: $isTargeted) { providers in
            dropHandler(providers)
        }
    }

    private var backgroundGradient: LinearGradient {
        let base = Color.accentColor.opacity(isTargeted ? 0.28 : 0.12)
        return LinearGradient(
            colors: [base, Color.accentColor.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        isTargeted ? .accentColor : Color.primary.opacity(0.25)
    }
}

private struct PasteBoxView: View {
    @Binding var text: String
    let canCommit: Bool
    var onCommit: () -> Void
    @FocusState private var hasFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )

                TextEditor(text: $text)
                    .focused($hasFocus)
                    .padding(10)
                    .scrollContentBackground(.hidden)

                if text.isEmpty {
                    Text("Click here, paste with ⌘V, then press Save.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                        .padding(.leading, 14)
                        .padding(.trailing, 16)
                        .offset(y: -2)
                }
            }
            .frame(height: 140)
            .onTapGesture {
                hasFocus = true
            }

            HStack(spacing: 12) {
                Button {
                    onCommit()
                } label: {
                    Label("Save text", systemImage: "tray.and.arrow.down.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canCommit || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                if canCommit {
                    Text("⌘⏎ to save")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct PlaceholderListView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Waiting for inspiration")
                    .font(.headline)
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentColor)
            }

            Text("Drop files, screenshots, or paste snippets — they will appear here instantly.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CollectedItemsList: View {
    @ObservedObject var store: CollectionStore
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .medium
        return formatter
    }()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(store.activeItems) { item in
                    CollectedItemRow(item: item, store: store)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct CollectedItemRow: View {
    let item: CollectedItem
    @ObservedObject var store: CollectionStore
    @State private var isHovered = false

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .medium
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(dateFormatter.string(from: item.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                switch item.content {
                case .text(let value):
                    Text(value)
                        .font(.body)
                        .textSelection(.enabled)
                        .lineLimit(8)
                        .truncationMode(.tail)
                case .image(let image):
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Button {
                    store.deleteItem(id: item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .help("Delete item")

                HStack(spacing: 2) {
                    Button {
                        store.moveItemUp(item.id)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Move up")
                    .disabled(!store.canMoveItemUp(item.id))

                    Button {
                        store.moveItemDown(item.id)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Move down")
                    .disabled(!store.canMoveItemDown(item.id))
                }
            }
            .opacity(isHovered ? 1.0 : 0.0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button(role: .destructive) {
                store.deleteItem(id: item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onDrag {
            NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onDrop(of: [.plainText], delegate: ItemDropDelegate(item: item, store: store))

    }
}

private struct ItemDropDelegate: DropDelegate {
    let item: CollectedItem
    @ObservedObject var store: CollectionStore

    func performDrop(info: DropInfo) -> Bool {
        guard let fromIndex = store.activeItems.firstIndex(where: { $0.id == item.id }) else {
            return false
        }

        // Find the target index by looking at the items around the drop location
        guard let toIndex = findDropIndex(from: info, items: store.activeItems) else {
            return false
        }

        if fromIndex != toIndex {
            let sourceIndexSet = IndexSet(integer: fromIndex)
            store.moveItem(from: sourceIndexSet, to: toIndex)
        }

        return true
    }

    private func findDropIndex(from info: DropInfo, items: [CollectedItem]) -> Int? {
        // This is a simplified implementation - in a real app you'd want more sophisticated
        // logic to determine the exact drop position
        guard let fromIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return nil
        }

        // For now, we'll just swap with the item being dropped on
        return fromIndex
    }

    func dropEntered(info: DropInfo) {}

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {}
}
private struct CollectionSelectionView: View {
    @ObservedObject var store: CollectionStore
    let mode: CollectionSheetMode

    @Environment(\.dismiss) private var dismiss
    @State private var intent: Intent
    @State private var selectedCollectionID: UUID?
    @State private var newCollectionName: String

    private enum Intent: Hashable {
        case existing
        case new
    }

    init(store: CollectionStore, mode: CollectionSheetMode) {
        self.store = store
        self.mode = mode
        let hasCollections = !store.collections.isEmpty
        _intent = State(initialValue: hasCollections ? .existing : .new)
        _selectedCollectionID = State(initialValue: store.activeCollectionID ?? store.collections.first?.id)
        _newCollectionName = State(initialValue: store.suggestedCollectionName())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(mode == .onboarding ? "Pick a Collection" : "Collections")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.bottom, 8)

            if store.collections.isEmpty {
                VStack(spacing: 12) {
                    Text("Create your first collection to start saving snippets.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Collection name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g. Moodboard", text: $newCollectionName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(confirm)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Picker("Action", selection: $intent) {
                        Text("Use Existing").tag(Intent.existing)
                        Text("Create New").tag(Intent.new)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity)

                    if intent == .existing {
                        CollectionListSelection(store: store, selectedCollectionID: $selectedCollectionID)
                            .frame(maxHeight: 200)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Collection name")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("e.g. Moodboard", text: $newCollectionName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(confirm)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            Divider()

            HStack {
                if mode == .manage && !store.collections.isEmpty {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: confirm) {
                    Text(primaryButtonTitle)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isPrimaryDisabled)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .frame(width: 380, height: store.collections.isEmpty ? 280 : 380)
    }

    private var primaryButtonTitle: String {
        if intent == .existing && !store.collections.isEmpty {
            return "Use Collection"
        }
        return "Create Collection"
    }

    private var isPrimaryDisabled: Bool {
        if store.collections.isEmpty {
            return newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        switch intent {
        case .existing:
            return selectedCollectionID == nil
        case .new:
            return newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func confirm() {
        if store.collections.isEmpty {
            createCollection()
            return
        }

        switch intent {
        case .existing:
            useExisting()
        case .new:
            createCollection()
        }
    }

    private func useExisting() {
        guard let id = selectedCollectionID ?? store.collections.first?.id else { return }
        store.selectCollection(id: id)
        dismiss()
    }

    private func createCollection() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.createCollection(named: trimmed)
        dismiss()
    }
}

private struct CollectionListSelection: View {
    @ObservedObject var store: CollectionStore
    @Binding var selectedCollectionID: UUID?

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(store.collections) { collection in
                    Button {
                        selectedCollectionID = collection.id
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(collection.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Text("\(collection.items.count) items")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            if selectedCollectionID == collection.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                                    .font(.system(size: 16))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedCollectionID == collection.id ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(selectedCollectionID == collection.id ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .animation(.easeInOut(duration: 0.15), value: selectedCollectionID)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
        .frame(maxHeight: 180)
    }
}

private struct CollectionListRow: View {
    let collection: ScrapCollection
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .font(.headline)

                Text("\(collection.items.count) items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct CardContainer<Content: View, Accessory: View>: View {
    let title: String
    let subtitle: String?
    let iconName: String?
    let content: Content
    let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        iconName: String? = nil,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.content = content()
        self.accessory = accessory()
    }

    init(
        title: String,
        subtitle: String? = nil,
        iconName: String? = nil,
        @ViewBuilder content: () -> Content
    ) where Accessory == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.content = content()
        self.accessory = EmptyView()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                if let iconName {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))

                        Image(systemName: iconName)
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    .frame(width: 34, height: 34)
                    .alignmentGuide(.top) { _ in 0 }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)

                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                accessory
                    .alignmentGuide(.top) { _ in 0 }
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private extension RelativeDateTimeFormatter {
    static func presenting(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
