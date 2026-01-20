# Am I Talking Too Much?

A macOS application that helps you monitor your speaking time during conversations to ensure you're not dominating discussions.

## Features

- **Real-time speaking percentage tracking**: Monitor how much of the conversation time you're using
- **Voice calibration**: Setup your voice profile for accurate tracking
- **History tracking**: Review past conversations and your speaking patterns
- **Customizable goals**: Set your target speaking percentage
- **Notification alerts**: Get notified when you exceed your speaking threshold

## Requirements

- macOS 14.0 or later
- Xcode 15.0 or later (for development)
- Swift 6.0

## Building the App

1. Clone the repository
2. Open Terminal and navigate to the project directory
3. Run `swift build` to build the project
4. Run `.build/debug/am-i-talking-too-much-app` to start the application

## Simulation Mode

By default, the app runs in simulation mode, which doesn't require microphone access. This allows you to test the app functionality without real audio input.

The simulation mode:
- Generates random speaking patterns to simulate a conversation
- Updates the UI in real-time just like the real recording mode
- Allows you to test all app functionality

To disable simulation mode and use real microphone input:
1. Open `AudioManager.swift`
2. Change `var isSimulationMode = true` to `var isSimulationMode = false` 
3. Rebuild the app

## Usage

1. **Start a recording**: Click the microphone button to begin tracking a conversation
2. **View statistics**: Watch your speaking percentage and time in real-time
3. **Stop recording**: Click the stop button when the conversation ends
4. **Review history**: Navigate to the History tab to see past sessions
5. **Adjust settings**: Set your target speaking percentage in the Settings tab

## Development

The app is structured using:
- SwiftUI for the user interface
- AVFoundation for audio processing
- Swift Package Manager for dependency management

## License

This project is available as open source under the terms of the MIT License. 