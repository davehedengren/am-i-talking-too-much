# Am I Talking Too Much?

An iOS app that measures how much you're talking relative to others in the room.

## Overview

"Am I Talking Too Much?" is an iOS application designed to help users become more aware of their speaking patterns in group conversations. The app uses the device's microphone to analyze speaking patterns, differentiating between the user's voice and other speakers in the room.

### Key Features

- **Voice Recognition**: Calibrates to recognize the user's voice
- **Real-time Monitoring**: Tracks speaking time percentages as conversations happen
- **Statistical Analysis**: Provides a breakdown of speaking time distribution
- **Historical Data**: Stores past conversations for trend analysis
- **Personalized Feedback**: Offers suggestions for more balanced conversations

## Technical Details

### Voice Recognition

The app uses a combination of techniques to identify the user's voice:

1. **Initial Calibration**: During setup, the app records a sample of the user's voice to create a voice profile
2. **Audio Analysis**: Extracts characteristics like pitch, intensity, and speech patterns
3. **On-device Processing**: Basic voice detection runs locally on the device
4. **Optional Advanced Analysis**: Can leverage more sophisticated analysis if needed

### Privacy

- All audio processing is done on-device by default
- The app does not record or store actual conversation content
- Only speaking time metrics are saved
- Optional advanced analysis could use external APIs, but this would be clearly indicated

## Development

### Requirements

- iOS 15.0+
- Xcode 13.0+
- Swift 5.5+

### Project Structure

- **AudioManager**: Handles audio recording and real-time analysis
- **VoiceAnalyzer**: Manages voice identification and processing
- **DataStore**: Stores and retrieves session data
- **Views**: SwiftUI interfaces for the app

### Setting Up for Development

1. Clone the repository
2. Open the project in Xcode
3. Ensure you have necessary permissions in your development environment (microphone access)
4. Build and run on a device (simulator does not support microphone input)

## Usage

1. **Initial Setup**: Follow the voice calibration process when first launching the app
2. **Start Recording**: Press the "Start Recording" button at the beginning of a conversation
3. **During Conversation**: The app will show real-time statistics about speaking time
4. **End Session**: Tap "Stop Recording" to end the session and view detailed results
5. **Review History**: Visit the History tab to see patterns across multiple conversations

## Future Enhancements

- Machine learning model to improve voice recognition accuracy
- Support for identifying multiple speakers
- Integration with meetings apps for virtual meeting analysis
- Apple Watch companion app for discreet monitoring
- Integration with speech quality metrics (pace, clarity, etc.)

## License

This project is available under the MIT License. See the LICENSE file for more details.

## Acknowledgments

- The team behind AVFoundation for the audio processing capabilities
- Apple's Speech framework for voice analysis tools
- The open-source community for inspiration and best practices 