# Shotty

An on-device-only screenshot organizer for iPhone and iPad. It uses PhotoKit to fetch screenshots, Vision OCR to extract text, NaturalLanguage for lightweight local language tags, and SwiftData for the local index.

No server, OpenAI API, Firebase, Supabase, or cloud OCR is used.

## Build and Launch

```sh
./scripts/build-and-launch.sh
```

The script builds with `xcodebuild`, boots the configured simulator, installs the app, launches it, and saves a screenshot to `screenshots/latest.png`.

Defaults:

- Scheme: `Shotty`
- Simulator: `iPhone 17`
- Runtime: `iOS 26.2`

Override when needed:

```sh
SIMULATOR_NAME="iPhone 16 Pro" SIMULATOR_RUNTIME="iOS 18.5" ./scripts/build-and-launch.sh
```

Run on a connected iPhone:

```sh
RUN_DESTINATION=device ./scripts/build-and-launch.sh
```

The first launch asks for Photos access. The app only stores a local SwiftData index: screenshot local identifier, extracted text, capture date, tags, detected type, and dimensions.
