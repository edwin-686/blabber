# Changelog

All notable changes to Blabber will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-11-10

### Added
- Initial public release
- Local voice transcription using Whisper AI (whisper-cpp)
- Cloud transcription support for multiple providers:
  - OpenAI Whisper API
  - Anthropic Claude
  - Google Gemini
  - xAI Grok
  - Ollama (local LLM)
- Customizable global hotkeys:
  - Press-and-hold mode
  - Double-tap mode
  - Workflow mode
- Transcription history with search and filtering
- Pin important transcriptions for quick access
- LLM workflow system for post-processing transcriptions
- Automated paste functionality
- macOS menu bar interface
- Onboarding wizard for first-time setup
- Model management for local Whisper models
- Update checking mechanism

### Security
- Local-first privacy - all transcriptions happen on-device by default
- API keys stored securely in macOS Keychain
- No data collection or analytics
- No external dependencies for basic functionality

[1.0.0]: https://github.com/edwin-686/blabber/releases/tag/v1.0.0
