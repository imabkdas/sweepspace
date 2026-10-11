import SwiftUI
import ScannerCore

public struct SettingsView: View {
    @AppStorage("lookInsidePackages") var lookInsidePackages: Bool = false
    @AppStorage("includeHiddenFiles") var includeHiddenFiles: Bool = true
    
    @Environment(\.dismiss) var dismiss
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Scanner Settings")
                .font(.headline)
            
            Toggle("Look inside Packages (e.g. .app, .photoslibrary)", isOn: $lookInsidePackages)
                .help("When off, packages are treated as single files to save memory. When on, you can drill inside them.")
                
            Toggle("Include Hidden Files", isOn: $includeHiddenFiles)
                .help("If off, skips files and folders starting with a dot.")
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}
