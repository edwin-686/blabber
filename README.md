<div align="center">
  <img src="logo.png" alt="Blabber Logo" width="128" height="128">
  <h1>Blabber</h1>
  <p><strong>Local-first voice transcription for macOS using Whisper AI</strong></p>
</div>

Blabber is a macOS menu bar application that provides fast, accurate voice transcription with a privacy-first approach. Record audio with customizable hotkeys and get instant transcriptions using local Whisper AI or cloud providers.

<!-- TODO: Add screenshots here -->

## Features

### 🎤 Voice Transcription
- **Local Whisper AI** - On-device transcription using whisper-cpp (no internet required)
- **Cloud Options** - Support for OpenAI, Anthropic, Google, xAI, and Ollama
- **Automatic Paste** - Transcriptions automatically paste into your active application

### ⌨️ Customizable Hotkeys
- **Press-and-Hold** - Hold a key combination to record
- **Double-Tap** - Quick double-tap activation
- **Workflow Mode** - Send transcriptions to LLM workflows for post-processing

### 📝 Transcription History
- Search and filter past transcriptions
- Pin important transcriptions for quick access
- Export history to JSON

### 🤖 LLM Workflows
- Create custom workflows to process transcriptions with AI
- Built-in templates (grammar correction, summarization, translation)
- Chain multiple prompts together

### 🔒 Privacy-Focused
- **Local-first** - All transcriptions happen on your device by default
- **No data collection** - Blabber doesn't send any data to external servers
- **Secure storage** - API keys stored in macOS Keychain
- **Optional cloud** - You control when and if cloud providers are used

## Installation

### Download DMG
1. Download the latest release from [GitHub Releases](https://github.com/edwin-686/blabber/releases/latest)
2. Open the DMG file
3. Drag Blabber.app to your Applications folder
4. Launch Blabber and complete the onboarding wizard

### Build from Source

**Prerequisites:**
- macOS 12.0 or later
- Xcode 14.0 or later
- [whisper-cpp](https://github.com/ggerganov/whisper.cpp) installed via Homebrew

**Install whisper-cpp:**
```bash
brew install whisper-cpp
```

**Clone and build:**
```bash
git clone https://github.com/edwin-686/blabber.git
cd blabber
open Blabber.xcodeproj
```

Build and run in Xcode (⌘R) or via command line:
```bash
xcodebuild -project Blabber.xcodeproj -scheme Blabber -configuration Release build
```

The built app will be in `build/Release/Blabber.app`.

## System Requirements

- **macOS:** 12.0 (Monterey) or later
- **Architecture:** Apple Silicon (M1/M2/M3) or Intel
- **Dependencies:** whisper-cpp (for local transcription)
- **Permissions:** Microphone, Accessibility (for global hotkeys)

## Usage

### First Launch
The onboarding wizard will guide you through setup:
1. **whisper-cpp Installation** - Verify whisper-cpp is installed (or get instructions to install it)
2. **Accessibility Permissions** - Grant permission for global hotkeys and auto-paste
3. **Microphone Access** - Grant permission for audio recording
4. **Model Download** - Download a Whisper AI model for local transcription
5. Start transcribing!

### Recording Audio
- Press and hold your configured hotkey to record
- Speak clearly into your microphone
- Release the hotkey when done
- Transcription will automatically paste into your active application

### Managing History
- Click the Blabber menu bar icon
- Select "Show History" to view all transcriptions
- Use the search bar to filter results
- Pin important transcriptions with the pin icon

### Creating Workflows
- Open Settings → Workflows
- Click "+" to create a new workflow
- Configure your LLM provider and prompt
- Assign to a hotkey for quick access

## Privacy

Blabber is designed with privacy as a core principle:

- **No analytics or tracking** - We don't collect any usage data
- **Local processing** - Default transcription happens entirely on your device
- **No accounts required** - Use Blabber without creating any accounts
- **Encrypted storage** - API keys stored securely in macOS Keychain
- **Optional cloud** - Cloud transcription is opt-in and only used when you explicitly configure it

Your transcriptions belong to you and stay on your device.

## Configuration

Blabber stores configuration in standard macOS locations:
- **Settings:** `~/Library/Preferences/com.kt.Blabber.plist`
- **History:** `~/Library/Application Support/Blabber/history.json`
- **Models:** `~/Library/Application Support/Blabber/Models/`

## Troubleshooting

### Hotkeys not working
- Ensure Accessibility permissions are granted in System Settings → Privacy & Security → Accessibility
- Check that your hotkey doesn't conflict with system or other app shortcuts

### Microphone not recording
- Verify microphone permissions in System Settings → Privacy & Security → Microphone
- Test your microphone in another app to ensure it's working

### Local transcription not working
- Ensure whisper-cpp is installed: `brew list whisper-cpp`
- Download a Whisper model in Settings → Transcription → Local

### App won't launch
- Check Console.app for error messages
- Try deleting `~/Library/Preferences/com.kt.Blabber.plist` and relaunching

## Contributing

Blabber is primarily developed for personal use, but bug reports and feedback are welcome via [GitHub Issues](https://github.com/edwin-686/blabber/issues).

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.

## Links

- **Website:** [blabbernotes.com](https://blabbernotes.com)
- **Issues:** [GitHub Issues](https://github.com/edwin-686/blabber/issues)
- **X (Twitter):** [@BlabberNotes](https://x.com/BlabberNotes)
- **Buy Me a Coffee:** [Support Blabber](https://buymeacoffee.com/blabbernotes)

---

**Made with ❤️ for privacy-conscious Mac users**
