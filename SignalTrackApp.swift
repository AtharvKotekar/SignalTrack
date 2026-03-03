import SwiftUI
import Carbon

class TimerState: ObservableObject {
    @Published var isRunning = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var maxTime: TimeInterval = UserDefaults.standard.double(forKey: "maxAttentionTime")
    
    private var startTime: Date?
    private var timer: Timer?

    init() {
        HotKeyManager.shared.action = { [weak self] in
            self?.toggleTimer()
        }
        HotKeyManager.shared.register()
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
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self, let start = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
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

class HotKeyManager {
    static let shared = HotKeyManager()
    var action: (() -> Void)?
    
    func register() {
        let keyCode: UInt32 = 17 // kVK_ANSI_T
        let modifiers: UInt32 = 256 | 2048 // cmdKey | optionKey
        
        var hotKeyID = EventHotKeyID(signature: 0x5349474E, id: 1) // 'SIGN'
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.action?()
            }
            return noErr
        }, 1, &eventType, ptr, nil)
        
        var hotKeyRef: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

@main
struct SignalTrackApp: App {
    @StateObject private var timerState = TimerState()

    var body: some Scene {
        MenuBarExtra {
            VStack {
                Text("PEAK FOCUS: \(timerState.formatTime(timerState.maxTime))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                
                Divider()
                
                Button(timerState.isRunning ? "Stop (⌥⌘T)" : "Start (⌥⌘T)") {
                    timerState.toggleTimer()
                }
                
                Divider()
                
                Button("Quit SignalTrack") {
                    NSApplication.shared.terminate(nil)
                }
            }
        } label: {
            HStack {
                if timerState.isRunning {
                    Image(systemName: "timer")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "timer")
                }
                Text(timerState.formatTime(timerState.elapsedTime))
                    .monospacedDigit()
            }
        }
    }
}
