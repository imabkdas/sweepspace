import SwiftUI
import UniformTypeIdentifiers
import ScannerCore

public struct StartView: View {
    @Bindable var model: AppModel
    
    @State private var showSettings = false
    @State private var volumes: [URL] = []
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Disks and Folders")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            if !Permissions.hasFullDiskAccess() {
                VStack(spacing: 8) {
                    Text("Degraded Mode: Missing Full Disk Access")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Text("macOS protects system folders. To scan your whole drive accurately, you must grant Full Disk Access.")
                        .multilineTextAlignment(.center)
                        .font(.caption)
                    Button("Open System Settings") {
                        Permissions.openFDASettings()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
            }
            
            List {
                ForEach(volumes, id: \.self) { url in
                    VolumeRow(url: url) {
                        model.startScan(url: url)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .padding(.top)
            
            HStack {
                Button("Scan Folder...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        model.startScan(url: url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding()
                
                Spacer()
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            let keys: [URLResourceKey] = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
            volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: .skipHiddenVolumes) ?? [URL(fileURLWithPath: "/")]
        }
        .dropDestination(for: URL.self) { items, _ in
            if let first = items.first {
                model.startScan(url: first)
                return true
            }
            return false
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

struct VolumeRow: View {
    let url: URL
    let onScan: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                let name = url.lastPathComponent == "/" ? "Macintosh HD" : url.lastPathComponent
                Text(name)
                    .font(.headline)
                
                if let info = VolumeService.info(for: url) {
                    let used = info.capacity > info.free ? info.capacity - info.free : 0
                    let usedGB = Double(used) / 1_000_000_000
                    let totalGB = Double(info.capacity) / 1_000_000_000
                    
                    Text("\(String(format: "%.1f", totalGB)) GB capacity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.gray.opacity(0.3))
                            Capsule().fill(Color.orange)
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(used) / CGFloat(info.capacity))))
                        }
                    }
                    .frame(height: 6)
                    
                    Text("\(String(format: "%.1f", usedGB)) GB used")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            
            Spacer()
            
            Button("Scan") {
                onScan()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.gray.opacity(0.2))
            .foregroundColor(.primary)
            .controlSize(.large)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
}
