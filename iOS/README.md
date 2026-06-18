# Wisp for iPhone

This is the iPhone companion for Wisp. It uses a small iOS app for recording and a custom keyboard extension for launching dictation and inserting the latest finished text.

## Why The App Opens

iOS custom keyboards cannot access the microphone directly. The keyboard launches the Wisp app for recording, then the app saves the finished text to the shared App Group. Return to the Wisp Keyboard and tap **Insert**.

## Targets

- `WispMobile`: SwiftUI app that records, transcribes, optionally composes with OpenAI, and saves the latest result.
- `WispKeyboard`: custom keyboard extension with Dictate, Compose, Insert, and Next Keyboard buttons.

## Build

Install XcodeGen once:

```bash
brew install xcodegen
```

Generate the project:

```bash
cd iOS
xcodegen generate
```

Simulator build:

```bash
xcodebuild -project WispMobile.xcodeproj \
  -scheme WispMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Device Setup

Open `WispMobile.xcodeproj` in Xcode and select your Apple development team for both targets:

- `WispMobile`
- `WispKeyboard`

Keep the App Group capability on both targets:

```text
group.local.wisp.mobile
```

Then run the `WispMobile` scheme on your iPhone. After install, enable the keyboard in:

```text
Settings > General > Keyboard > Keyboards > Add New Keyboard > Wisp Keyboard
```

Turn on **Allow Full Access** so the keyboard can open Wisp and read the shared latest text.
