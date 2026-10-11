import SwiftUI

public struct ScanningView: View {
    @Bindable var model: AppModel
    
    public var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Scanning...")
                .font(.title2)
            
            Text(model.currentPath)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 400)
            
            HStack(spacing: 40) {
                VStack {
                    Text("Found")
                        .foregroundColor(.secondary)
                    Text("\(model.scannedFiles)")
                        .font(.title3.monospacedDigit())
                }
                
                VStack {
                    Text("Size")
                        .foregroundColor(.secondary)
                    Text(formatSize(model.scannedBytes))
                        .font(.title3.monospacedDigit())
                }
            }
            .padding()
            
            Button("Stop") {
                model.stopScan()
            }
            .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    func formatSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
