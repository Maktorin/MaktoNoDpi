import SwiftUI
import MaktoNoDpiCore

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("MaktoNoDpi")
                .font(.title2.bold())
            Text("Core \(MaktoNoDpiCore.version)")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 360, height: 240)
    }
}

#Preview {
    ContentView()
}
