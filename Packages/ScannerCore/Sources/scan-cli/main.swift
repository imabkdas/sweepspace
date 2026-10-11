import Foundation
import ScannerCore
import Darwin

@main
struct ScanCLI {
    static func main() async {
        let args = CommandLine.arguments
        // Default to the user's home directory if no path is provided
        let path = args.count > 1 ? args[1] : FileManager.default.homeDirectoryForCurrentUser.path
        
        let url = URL(fileURLWithPath: path)
        print("🚀 Starting benchmark scan of: \(url.path)")
        
        let scanner = Scanner()
        let options = ScanOptions()
        let stream = scanner.scan(root: url, options: options)
        
        let start = Date()
        
        for await event in stream {
            switch event {
            case .progress(let fileCount, let bytes, let currentPath):
                // Progress is throttled in the scanner, but we won't print here to keep CLI output clean for the benchmark
                break
                
            case .done(let store):
                let elapsed = Date().timeIntervalSince(start)
                let root = store.nodes[0]
                
                var usage = rusage()
                getrusage(RUSAGE_SELF, &usage)
                let peakRSS = usage.ru_maxrss // On macOS, this is in bytes
                
                print("\n✅ --- Scan Complete ---")
                print("⏱  Elapsed time: \(String(format: "%.3f", elapsed)) seconds")
                print("📁 Total items scanned: \(root.itemCount)")
                print("💽 Allocated size on disk: \(formatSize(root.allocatedBytes))")
                
                // Unreadable check
                let skipped = store.nodes.filter { NodeFlags(rawValue: $0.flags).contains(.unreadable) }.count
                if skipped > 0 {
                    print("⚠️ Skipped (permission denied): \(skipped) items")
                }
                
                print("\n🧠 --- Memory Profile ---")
                print("Peak memory (RSS): \(formatSize(UInt64(peakRSS)))")
                
                let memoryPerNode = Int(peakRSS) / max(1, Int(root.itemCount))
                print("Memory per node: \(memoryPerNode) bytes")
                
                if memoryPerNode < 150 {
                    print("🎯 PASS: Memory per node is well under the 150-byte requirement!")
                } else {
                    print("⚠️ WARN: Memory per node exceeds the 150-byte limit.")
                }
                
            case .error(let path, let reason):
                print("❌ Error at \(path): \(reason)")
            }
        }
    }
    
    static func formatSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
