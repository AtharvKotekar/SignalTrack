# SignalTrack

A simple, lightweight macOS menu bar application to track your attention span.

## Features
- **Menu Bar Integration:** Always visible in your menu bar so you can constantly monitor your focus time.
- **Global Shortcut:** Start and stop the timer from anywhere using `Option + Cmd + T` (`⌥⌘T`).
- **Peak Focus Tracking:** Automatically saves and displays your highest attention span.
- **Lightweight:** Native Apple Silicon app built with SwiftUI.

## How to Use
1. Launch `SignalTrack.app`. The app will appear as a timer icon in your macOS menu bar.
2. Press `Option + Cmd + T` (`⌥⌘T`) to start the focus timer.
3. When you get distracted, press `Option + Cmd + T` (`⌥⌘T`) again to stop the timer.
4. Click the menu bar icon to view your peak focus time or quit the application.

## Development
This app is built using Swift and SwiftUI, and compiled directly using `swiftc`.

To compile:
```bash
# Create App Bundle structure
mkdir -p SignalTrack.app/Contents/MacOS
cp Info.plist SignalTrack.app/Contents/

# Compile Swift code
swiftc SignalTrackApp.swift -parse-as-library -o SignalTrack.app/Contents/MacOS/SignalTrack -target arm64-apple-macosx13.0
```
