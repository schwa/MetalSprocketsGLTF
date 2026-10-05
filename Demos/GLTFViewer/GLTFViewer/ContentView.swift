import GLTFViewerSupport
import SwiftUI

struct ContentView: View {
    var body: some View {
        SamplesView()
    }
}

#Preview {
    ContentView()
        .environment(SampleLibrary())
}
