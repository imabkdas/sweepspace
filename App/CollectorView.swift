import SwiftUI
import ScannerCore

public struct CollectorView: View {
    @Bindable var model: AppModel
    @State private var showConfirm = false
    
    public var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("Collector Tray")
                    .font(.headline)
                Spacer()
                Text("\(model.collectorNodes.count) items")
                    .foregroundColor(.secondary)
                Text(formatSize(model.collectorTotalSize))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundColor(.red)
                
                Button(role: .destructive, action: {
                    showConfirm = true
                }) {
                    Text("Delete...")
                }
                .disabled(model.collectorNodes.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            if !model.collectorNodes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(model.collectorNodes), id: \.self) { nodeID in
                            HStack {
                                Text(model.name(for: nodeID))
                                    .lineLimit(1)
                                Button {
                                    model.removeFromCollector(nodeID: nodeID)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                }
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .alert(
            "Delete \(model.collectorNodes.count) item(s)?",
            isPresented: $showConfirm
        ) {
            Button("Move to Trash", role: .destructive) {
                Task { await model.deleteCollected(immediately: false) }
            }
            Button("Delete Immediately", role: .destructive) {
                Task { await model.deleteCollected(immediately: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will free up \(formatSize(model.collectorTotalSize)) of disk space.")
        }
        .alert(
            "Deletion Error",
            isPresented: Binding(
                get: { model.lastError != nil },
                set: { if !$0 { model.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }
    
    func formatSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
