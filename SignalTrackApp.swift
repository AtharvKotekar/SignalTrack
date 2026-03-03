import SwiftUI
import Charts
import ApplicationServices
import Foundation

// MARK: - Models

struct FocusDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let isFocused: Bool
    let note: String
}

enum AIProvider: String, CaseIterable, Identifiable {
    case openai = "OpenAI (GPT-5.2)"
    case anthropic = "Anthropic (Claude 4.6)"
    case gemini = "Google (Gemini 3.1)"
    var id: String { self.rawValue }
}

// MARK: - App State

class AppState: ObservableObject {
    @Published var agenda: String = UserDefaults.standard.string(forKey: "savedAgenda") ?? ""
    @Published var selectedProvider: AIProvider = .gemini
    @Published var apiKey: String = UserDefaults.standard.string(forKey: "savedApiKey") ?? ""
    
    @Published var isTracking: Bool = false
    @Published var isDistracted: Bool = false
    @Published var history: [FocusDataPoint] = []
    @Published var latestObservation: String = "Starting session..."
    
    @Published var sessionStartTime: Date?
    @Published var elapsedTime: TimeInterval = 0
    
    @Published var isTestingConnection: Bool = false
    @Published var connectionStatus: String = ""
    @Published var isConnectionVerified: Bool = false
    
    private var timer: Timer?
    private var analysisTimer: Timer?
    
    func saveSettings() {
        UserDefaults.standard.set(agenda, forKey: "savedAgenda")
        UserDefaults.standard.set(apiKey, forKey: "savedApiKey")
    }
    
    func startSession() {
        DispatchQueue.main.async {
            self.connectionStatus = "Recording started."
        }
        
        saveSettings()
        isTracking = true
        isDistracted = false
        history = []
        sessionStartTime = Date()
        elapsedTime = 0
        latestObservation = "Starting session..."
        
        history.append(FocusDataPoint(timestamp: Date(), isFocused: true, note: "Session started")) // Start focused
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.sessionStartTime else { return }
            self.elapsedTime = Date().timeIntervalSince(start)
        }
        RunLoop.main.add(timer!, forMode: .common)
        
        // Take a screenshot and analyze every 5 seconds
        analysisTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.performAnalysis()
        }
    }
    
    func stopSession() {
        isTracking = false
        timer?.invalidate()
        timer = nil
        analysisTimer?.invalidate()
        analysisTimer = nil
    }
    
    func testAPIConnection() {
        guard !apiKey.isEmpty else { return }
        isTestingConnection = true
        connectionStatus = "Testing connection..."
        
        Task {
            do {
                let (success, message) = try await AIManager.testConnection(provider: selectedProvider, apiKey: apiKey)
                DispatchQueue.main.async {
                    self.isTestingConnection = false
                    self.isConnectionVerified = success
                    self.connectionStatus = message
                    if success {
                        self.saveSettings()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isTestingConnection = false
                    self.isConnectionVerified = false
                    self.connectionStatus = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func performAnalysis() {
        guard let image = takeScreenshot(), let jpegData = image.jpegData(compressionQuality: 0.5) else { return }
        
        Task {
            do {
                let (isFocused, note) = try await AIManager.evaluateFocus(
                    provider: selectedProvider,
                    apiKey: apiKey,
                    agenda: agenda,
                    imageData: jpegData
                )
                
                DispatchQueue.main.async {
                    self.latestObservation = note
                    self.history.append(FocusDataPoint(timestamp: Date(), isFocused: isFocused, note: note))
                    if !isFocused {
                        self.isDistracted = true
                        self.stopSession()
                    }
                }
            } catch {
                print("Analysis failed: \(error)")
            }
        }
    }
    
    private func takeScreenshot() -> NSImage? {
        // Capture main display
        guard let cgImage = CGWindowListCreateImage(CGRect.infinite, .optionOnScreenOnly, kCGNullWindowID, .nominalResolution) else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}

// MARK: - Extension for NSImage
extension NSImage {
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}

// MARK: - AI Manager

class AIManager {
    static func testConnection(provider: AIProvider, apiKey: String) async throws -> (Bool, String) {
        var request: URLRequest
        
        switch provider {
        case .openai:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.httpMethod = "GET"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            
        case .gemini:
            // Test models listing to verify the key.
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!)
            request.httpMethod = "GET"
            
        case .anthropic:
            // Note: Anthropic doesn't have a simple GET /models, so we'll do a small, minimal generation.
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "model": "claude-3-5-sonnet-20241022",
                "max_tokens": 1,
                "messages": [
                    ["role": "user", "content": "Hi"]
                ]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    return (true, "Connection successful! ✅")
                } else {
                    let errStr = String(data: data, encoding: .utf8) ?? "Unknown Error"
                    return (false, "HTTP \(httpResponse.statusCode): \(errStr)")
                }
            }
            return (false, "Invalid response from server.")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    static func evaluateFocus(provider: AIProvider, apiKey: String, agenda: String, imageData: Data) async throws -> (Bool, String) {
        let base64 = imageData.base64EncodedString()
        let prompt = """
        You are an AI tracking a user's focus. The user's goal/agenda is: '\(agenda)'.
        Look at this screenshot of their computer. Are they working on their agenda?
        Consider reading documentation, coding, writing relevant text, watching tutorials specifically about the agenda as working.
        Consider social media (like Twitter, Instagram), unrelated YouTube videos, or unrelated articles as distracted.
        
        You must reply with a valid JSON object matching this exact schema:
        {
            "status": "FOCUSED" or "DISTRACTED",
            "observation": "A short, 1-sentence description of exactly what the user is doing on screen right now (e.g. 'Watching a YouTube video about React', 'Scrolling through Twitter feed', 'Reading API documentation')."
        }
        Reply ONLY with the raw JSON object, no markdown formatting or backticks.
        """
        
        var request: URLRequest
        
        switch provider {
        case .openai:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "model": "gpt-5.2",
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            ["type": "text", "text": prompt],
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
                        ]
                    ]
                ],
                "max_tokens": 150
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
        case .gemini:
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)")!)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "contents": [
                    [
                        "parts": [
                            ["text": prompt],
                            ["inline_data": ["mime_type": "image/jpeg", "data": base64]]
                        ]
                    ]
                ]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "model": "claude-sonnet-4-6",
                "max_tokens": 150,
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            ["type": "text", "text": prompt],
                            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64]]
                        ]
                    ]
                ]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let responseString = String(data: data, encoding: .utf8) ?? ""
        
        let logText = "Status: \((response as? HTTPURLResponse)?.statusCode ?? 0)\nResponse: \(responseString)\n\n"
        let logPath = "/Users/atharvkotekar/Desktop/SignalTrack/SignalTrack_AILogs.txt"
        let logURL = URL(fileURLWithPath: logPath)
        if let fileHandle = try? FileHandle(forWritingTo: logURL) {
            fileHandle.seekToEndOfFile()
            if let data = logText.data(using: .utf8) { fileHandle.write(data) }
            try? fileHandle.close()
        } else {
            try? logText.write(to: logURL, atomically: true, encoding: .utf8)
        }
        
        // Extract JSON string from response depending on the provider format
        var extractedJSON = ""
        
        switch provider {
        case .openai:
            if let data = responseString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                extractedJSON = content
            }
        case .gemini:
            if let data = responseString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let first = candidates.first,
               let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let firstPart = parts.first,
               let text = firstPart["text"] as? String {
                extractedJSON = text
            }
        case .anthropic:
            if let data = responseString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? [[String: Any]],
               let first = content.first,
               let text = first["text"] as? String {
                extractedJSON = text
            }
        }
        
        // Clean up markdown block if the model returned it
        extractedJSON = extractedJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if extractedJSON.hasPrefix("```json") {
            extractedJSON = String(extractedJSON.dropFirst(7))
        } else if extractedJSON.hasPrefix("```") {
            extractedJSON = String(extractedJSON.dropFirst(3))
        }
        if extractedJSON.hasSuffix("```") {
            extractedJSON = String(extractedJSON.dropLast(3))
        }
        
        var isFocused = true
        var observation = "Observing..."
        
        if let data = extractedJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let status = json["status"] as? String {
                isFocused = !status.localizedCaseInsensitiveContains("DISTRACTED")
            }
            if let obs = json["observation"] as? String {
                observation = obs
            }
        } else {
            // Fallback if parsing fails
            isFocused = !extractedJSON.localizedCaseInsensitiveContains("DISTRACTED")
            observation = "Could not parse detailed observation."
        }
        
        return (isFocused, observation)
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var appState = AppState()
    
    var body: some View {
        VStack {
            if appState.isTracking || appState.isDistracted {
                TrackingView(appState: appState)
            } else {
                SetupView(appState: appState)
            }
        }
        .frame(minWidth: 400, minHeight: 350)
        .padding()
    }
}

struct SetupView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("AI Focus Tracker")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("What is your agenda for this session?")
                    .font(.headline)
                TextField("e.g. Learning CLI tools from Missing Semester", text: $appState.agenda)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Provider")
                    .font(.headline)
                Picker("", selection: $appState.selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.headline)
                SecureField("Enter your API key", text: $appState.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: appState.apiKey) { _ in appState.isConnectionVerified = false; appState.connectionStatus = "" }
            }
            .onChange(of: appState.selectedProvider) { _ in appState.isConnectionVerified = false; appState.connectionStatus = "" }
            
            if !appState.connectionStatus.isEmpty {
                Text(appState.connectionStatus)
                    .font(.subheadline)
                    .foregroundColor(appState.connectionStatus.contains("⚠️") ? .orange : (appState.isConnectionVerified ? .green : (appState.isTestingConnection ? .blue : .red)))
            }
            
            Spacer()
            
            HStack {
                Spacer()
                if !appState.isConnectionVerified {
                    Button(action: {
                        appState.testAPIConnection()
                    }) {
                        Text(appState.isTestingConnection ? "Testing..." : "Test Connection")
                            .font(.title3)
                            .fontWeight(.bold)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.apiKey.isEmpty || appState.isTestingConnection)
                } else {
                    Button(action: {
                        appState.startSession()
                    }) {
                        Text("Start Session")
                            .font(.title3)
                            .fontWeight(.bold)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.agenda.isEmpty)
                }
                Spacer()
            }
        }
    }
}

struct TrackingView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 20) {
            if appState.isDistracted {
                Text("DISTRACTED!")
                    .font(.system(size: 40, weight: .black))
                    .foregroundColor(.red)
                
                Text("Your session was stopped because you lost focus.")
                    .font(.headline)
                    .foregroundColor(.secondary)
            } else {
                Text("FOCUSED")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.green)
                
                Text("Monitoring: \(appState.agenda)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Text(formatTime(appState.elapsedTime))
                .font(.system(size: 60, weight: .bold, design: .monospaced))
                .monospacedDigit()
                
            VStack(spacing: 4) {
                Text("AI OBSERVATION:")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Text(appState.latestObservation)
                    .font(.subheadline)
                    .italic()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            if !appState.history.isEmpty {
                Chart {
                    ForEach(appState.history) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Focus", point.isFocused ? 1 : 0)
                        )
                        .interpolationMethod(.stepStart)
                        
                        AreaMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Focus", point.isFocused ? 1 : 0)
                        )
                        .interpolationMethod(.stepStart)
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue.opacity(0.5), .clear]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .frame(height: 100)
                .chartYAxis {
                    AxisMarks(values: [0, 1]) { value in
                        AxisValueLabel {
                            if let intVal = value.as(Int.self) {
                                Text(intVal == 1 ? "Focused" : "Distracted")
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            Button(action: {
                appState.stopSession()
                // Reset state to go back to Setup
                appState.isTracking = false
                appState.isDistracted = false
            }) {
                Text(appState.isDistracted ? "Start New Session" : "Stop Session Manually")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(appState.isDistracted ? .blue : .red)
        }
    }
    
    func formatTime(_ interval: TimeInterval) -> String {
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

@main
struct SignalTrackApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
