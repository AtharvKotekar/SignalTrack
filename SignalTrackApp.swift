import SwiftUI

@main
struct SignalTrackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 260, height: 160)
                .background(WindowAccessor())
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true // Quit app when window is closed
    }
}

struct ContentView: View {
    @State private var isRunning = false
    @State private var startTime: Date?
    @State private var elapsedTime: TimeInterval = 0
    @State private var maxTime: TimeInterval = UserDefaults.standard.double(forKey: "maxAttentionTime")
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 12) {
            Text("PEAK FOCUS: \(formatTime(maxTime))")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)

            Text(formatTime(elapsedTime))
                .font(.system(size: 52, weight: .bold, design: .monospaced))
                .monospacedDigit()
                
            Button(action: toggleTimer) {
                Text(isRunning ? "Stop" : "Start")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 100)
            }
            .keyboardShortcut(.space, modifiers: [])
            .buttonStyle(.borderedProminent)
            .tint(isRunning ? .red : .blue)
            
            Text("Press Space to toggle")
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
        .padding()
    }
    
    func toggleTimer() {
        if isRunning {
            isRunning = false
            timer?.invalidate()
            timer = nil
            if elapsedTime > maxTime {
                maxTime = elapsedTime
                UserDefaults.standard.set(maxTime, forKey: "maxAttentionTime")
            }
        } else {
            isRunning = true
            elapsedTime = 0
            startTime = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                if let start = startTime {
                    elapsedTime = Date().timeIntervalSince(start)
                }
            }
            // Ensure timer runs smoothly even when interacting with the window
            if let timer = timer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }
    
    func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.level = .floating // Stay on top
                window.isMovableByWindowBackground = true // Allow dragging by clicking anywhere
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
