# StudioVocals

An iOS app where a singer records their voice and one tap makes it sound studio-recorded — Adobe Podcast Enhance, but for singing.

## Architecture Rules

- SwiftUI only, MVVM, iOS 17 minimum, Swift Concurrency (async/await). No third-party UI libraries.
- Audio: AVAudioEngine graph. All processing is offline (record first, process after) — no real-time monitoring in v1.
- Audio processing code lives in `AudioEngine/`, isolated from UI. The UI never touches AVAudioEngine directly — only view models do.
- All audio files: 48kHz, mono, Float32 PCM internally. Export as AAC/WAV.
- Every processing stage must be individually toggleable, for A/B testing.
- No force unwraps in audio code. All audio errors surface to the UI as readable messages.
- Write unit tests for any pure DSP math. Audio graph behavior is tested manually on device.

## Coding Style

- Small files, one type per file, no file over 300 lines.
- Prefer clarity over cleverness.
