# SimpMusic iOS native full target

This target is a clean SwiftUI/AVFoundation iOS implementation based on the
feature contract and provider behavior in the Android source. It is intentionally
separate from `iosApp/` and from the earlier minimal `iosNative/` target.

Implemented native flows:

- Home data from the YouTube Music browse endpoint
- Parallel YouTube Music and SoundCloud search
- SoundCloud Web client ID extraction, validation, caching, and progressive/HLS resolution
- YouTube Music direct audio/HLS resolution with multiple public clients
- AVPlayer background playback, lock-screen controls, queue, seek, previous/next
- LRCLIB lyrics lookup
- Favorites and listening history stored locally with `UserDefaults`
- Vietnamese-first Home, Search, Library, Now Playing, lyrics, and Settings UI
- iOS 16 deployment target with APIs that remain compatible with newer iOS versions

The Android-specific concepts are mapped to iOS equivalents: Android Auto and
widgets require future CarPlay and WidgetKit targets; Android WorkManager is
replaced here by the system audio session and lock-screen playback lifecycle.

The GitHub Actions workflow builds both simulator and unsigned device products,
runs a bounded simulator startup/crash smoke test, and publishes a separate IPA.
