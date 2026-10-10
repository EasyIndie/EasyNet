import SwiftUI

@main
struct EasyNetNativeLab: App {
    var body: some Scene {
        WindowGroup("EasyNet Native Lab") {
            VStack(alignment: .leading, spacing: 16) {
                Text("EasyNet Native Lab").font(.title)
                Text("State: idle / runtime unqualified")
                Text("Error: none — lifecycle has not run")
                Text("Generation: 0 (no runtime)")
                HStack {
                    Button("Connect") {}
                    Button("Cancel") {}
                    Button("Stop") {}
                    Button("Restart") {}
                }
                .disabled(true)
                Text("Compile experiment only. Engine, GUI and network qualification pending.")
                    .font(.caption)
            }
            .padding(24)
            .frame(minWidth: 440, minHeight: 220)
        }
    }
}
