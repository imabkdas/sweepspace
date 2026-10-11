import SwiftUI
import ScannerCore

public struct ResultsView: View {
    @Bindable var model: AppModel
    
    @State private var searchText = ""
    @State private var searchResults: [Node] = []
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var showVirtualAlert = false
    @State private var virtualAlertTitle = ""
    @State private var virtualAlertMessage = ""
    
    public var body: some View {
        HStack(spacing: 0) {
            // Left: Chart and Collector
            VStack {
                Spacer()
                
                ZStack {
                    SunburstView(
                        segments: model.currentSegments,
                        focusID: model.focusID,
                        selectedID: model.selectedID,
                        onHover: { id in model.selectedID = id },
                        onSelect: { id in 
                            if id != 0 { 
                                if id == AppModel.purgeableNodeID {
                                    model.drillIn(to: id)
                                } else if id == UInt32.max || id == UInt32.max - 1 {
                                    showVirtualExplanation(for: id)
                                } else if id >= AppModel.purgeableItemBaseID {
                                    model.selectedID = id
                                } else {
                                    model.drillIn(to: id) 
                                }
                            } 
                        },
                        onUp: { model.goUp() },
                        onReveal: { id in model.revealInFinder(nodeID: id) },
                        onCollect: { id in model.addToCollector(nodeID: id) },
                        onTrash: { id in Task { await model.deleteNode(id, immediately: false) } },
                        onDelete: { id in Task { await model.deleteNode(id, immediately: true) } }
                    )
                    
                    Text(formatSize(model.currentTotalBytes))
                        .font(.headline)
                        .foregroundColor(.primary)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Spacer()
                
                CollectorView(model: model)
            }
            .frame(maxWidth: .infinity)
            
            // Right: Navigation, Search, and List
            VStack(alignment: .leading, spacing: 0) {
                
                // Top controls: Back Button, Rescan, & Search
                HStack {
                    Button(action: { model.goUp() }) {
                        Image(systemName: "chevron.left")
                            .fontWeight(.bold)
                    }
                    .disabled(model.focusID == 0)
                    .buttonStyle(.borderless)
                    .padding(6)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(6)
                    .help("Go up one folder")
                    
                    Button(action: {
                        if let root = model.rootURL {
                            model.startScan(url: root)
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .fontWeight(.bold)
                    }
                    .buttonStyle(.borderless)
                    .padding(6)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(6)
                    .help("Rescan this disk")
                    
                    Spacer()
                    
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(8)
                    .frame(width: 180)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                // Path Breadcrumb
                Text(model.focusID == AppModel.purgeableNodeID ? "/ > purgeable space" : (model.buildURL(for: model.focusID)?.path ?? "/"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                
                if searchText.isEmpty {
                    // Standard Folder View
                    if model.focusID == AppModel.purgeableNodeID {
                        HStack(alignment: .bottom) {
                            Text("purgeable space")
                                .font(.title3)
                                .fontWeight(.medium)
                            Spacer()
                            Text(formatSize(model.currentTotalBytes))
                                .font(.title3)
                                .monospacedDigit()
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                        
                        HStack {
                            Text("System & app caches clearable on macOS.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("⚡️ Purge Caches") {
                                Task { await model.purgeAllCaches() }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    } else if let store = model.treeStore, store.nodes.count > Int(model.focusID) {
                        let focusNode = store.nodes[Int(model.focusID)]
                        let nameStr = String(decoding: focusNode.nameBytes, as: UTF8.self)
                        HStack(alignment: .bottom) {
                            Text(nameStr.isEmpty ? "/" : nameStr)
                                .font(.title3)
                                .fontWeight(.medium)
                            Spacer()
                            Text(formatSize(model.currentTotalBytes))
                                .font(.title3)
                                .monospacedDigit()
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(model.currentChildren, id: \.id) { child in
                                row(for: child)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                } else {
                    // Search Results View
                    HStack {
                        Text("Search Results")
                            .font(.headline)
                        Spacer()
                        Text("\(searchResults.count)\(searchResults.count == 100 ? "+" : "") items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            if searchResults.isEmpty {
                                Text("No matches found.")
                                    .foregroundColor(.secondary)
                                    .padding()
                            } else {
                                ForEach(searchResults, id: \.id) { child in
                                    row(for: child)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
            .frame(width: 300)
            .background(Color.black.opacity(0.1))
        }
        .onChange(of: searchText) { newValue in
            performSearch(query: newValue)
        }
        .alert(virtualAlertTitle, isPresented: $showVirtualAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(virtualAlertMessage)
        }
    }
    
    private func showVirtualExplanation(for id: UInt32) {
        if id == UInt32.max - 1 {
            virtualAlertTitle = "What is Hidden Space?"
            virtualAlertMessage = "Hidden space consists of files that SpaceSweep was blocked from scanning due to macOS permissions, as well as APFS system snapshots.\n\nIf hidden space is unusually large, SpaceSweep may not have Full Disk Access. Go to System Settings > Privacy & Security > Full Disk Access, enable SpaceSweep, and click the Rescan button."
        } else if id == UInt32.max - 2 {
            virtualAlertTitle = "What is Purgeable Space?"
            virtualAlertMessage = "Purgeable space consists of temporary system caches, local iCloud file mirrors, and APFS snapshots.\n\nIt is not a browsable folder. macOS automatically purges and reclaims this space whenever you need room for new files."
        } else {
            virtualAlertTitle = "What is Free Space?"
            virtualAlertMessage = "Free space is unallocated, empty space on your hard drive ready for new files."
        }
        showVirtualAlert = true
    }
    
    @ViewBuilder
    func row(for child: Node) -> some View {
        let isVirtualRoot = (child.id == UInt32.max || child.id == UInt32.max - 1 || child.id == AppModel.purgeableNodeID)
        let isPurgeableItem = child.id >= AppModel.purgeableItemBaseID
        HStack {
            Circle()
                .fill(colorForNode(child))
                .frame(width: 8, height: 8)
            Text(String(decoding: child.nameBytes, as: UTF8.self))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(formatSize(child.allocatedBytes))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background(model.selectedID == child.id ? Color.gray.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .onHover { isHovering in
            if isHovering {
                model.selectedID = child.id
            }
        }
        .onTapGesture {
            if child.id == AppModel.purgeableNodeID {
                model.drillIn(to: child.id)
                searchText = ""
                return
            }
            if child.id == UInt32.max || child.id == UInt32.max - 1 {
                showVirtualExplanation(for: child.id)
                return
            }
            if isPurgeableItem {
                model.selectedID = child.id
                return
            }
            if child.kind != 0 {
                model.drillIn(to: child.id)
                searchText = ""
            } else {
                model.drillIn(to: child.parent)
                model.selectedID = child.id
                searchText = ""
            }
        }
        .contextMenu {
            if child.id == AppModel.purgeableNodeID {
                Button("⚡️ Purge All Caches") {
                    Task { await model.purgeAllCaches() }
                }
            } else if isPurgeableItem {
                if model.purgeableItemMap[child.id]?.url != nil {
                    Button("Reveal in Finder") {
                        model.revealInFinder(nodeID: child.id)
                    }
                }
                Button("Move to Collector Tray") {
                    model.addToCollector(nodeID: child.id)
                }
                if model.purgeableItemMap[child.id]?.url != nil {
                    Divider()
                    Button("Move to Trash") {
                        Task { await model.deleteNode(child.id, immediately: false) }
                    }
                    Button("Delete Immediately") {
                        Task { await model.deleteNode(child.id, immediately: true) }
                    }
                }
            } else if !isVirtualRoot {
                Button("Reveal in Finder") {
                    model.revealInFinder(nodeID: child.id)
                }
                Button("Move to Collector Tray") {
                    model.addToCollector(nodeID: child.id)
                }
                Divider()
                Button("Move to Trash") {
                    Task { await model.deleteNode(child.id, immediately: false) }
                }
                Button("Delete Immediately") {
                    Task { await model.deleteNode(child.id, immediately: true) }
                }
            }
        }
    }
    
    func performSearch(query: String) {
        searchTask?.cancel()
        guard !query.isEmpty, let store = model.treeStore else {
            searchResults = []
            return
        }
        
        let lowerQuery = query.lowercased()
        
        searchTask = Task.detached {
            var results: [Node] = []
            for node in store.nodes {
                if Task.isCancelled { return }
                // Skip empty roots or small useless things to keep search clean
                if node.id == 0 { continue }
                if node.allocatedBytes == 0 { continue }
                
                let name = String(decoding: node.nameBytes, as: UTF8.self).lowercased()
                if name.contains(lowerQuery) {
                    results.append(node)
                    if results.count >= 100 { break } // Limit to 100 results for speed
                }
            }
            
            // Sort by size descending
            results.sort { $0.allocatedBytes > $1.allocatedBytes }
            
            let finalResults = results
            await MainActor.run {
                if !Task.isCancelled {
                    self.searchResults = finalResults
                }
            }
        }
    }
    
    func formatSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    func colorForNode(_ node: Node) -> Color {
        if let seg = model.currentSegments.first(where: { $0.nodeID == node.id }) {
            return Theme.color(for: seg.hueKey, ring: 1, kind: seg.kind)
        }
        return Theme.color(for: Int(node.id) % 12, ring: 1, kind: node.kind)
    }
}
