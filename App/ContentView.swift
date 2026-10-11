import SwiftUI

public struct ContentView: View {
    @State private var model = AppModel()
    
    public init() {}
    
    public var body: some View {
        Group {
            switch model.currentState {
            case .start:
                StartView(model: model)
            case .scanning:
                ScanningView(model: model)
            case .results:
                ResultsView(model: model)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}
