# Shotty

<p float="left">
  <img width="49%" height="1278" alt="IMG_0042" src="https://github.com/user-attachments/assets/de83400a-2d43-4c9e-a099-7f71eca75478" />
  <img width="49%" height="1278" alt="IMG_0041" src="https://github.com/user-attachments/assets/1b5dd243-9d8c-4e82-8de1-e1c4f22de01d" />
</p>

<img width="1180" height="820" alt="IMG_0040" src="https://github.com/user-attachments/assets/7aec4af7-0d9d-4062-a172-1dd2a5f5bf1d" />
<img width="1180" height="820" alt="IMG_0039" src="https://github.com/user-attachments/assets/e0ebfa40-1f57-4ec1-a2c4-27ce71f21bd4" />

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
