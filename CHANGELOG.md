# Changelog

All notable changes. Format based on [Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).
The macOS and Windows apps share one version number.

## [1.1.0] — 2026-10-16
### Added
- Screens now have proper names (*Front screen*, *Rear screen*, *Main screen*); virtual displays are hidden.
- **Both screens** option: mirror, record and photo of front + rear at once (two windows / two files).
- Six languages (French, English, German, Spanish, Italian, Portuguese), following the system language, with an in-app language menu.
- Mirror windows are resized and placed side by side in dual-screen mode (recording quality unchanged).

### Fixed
- Starting two mirrors at the same time made the first one fail silently (adb port conflict). They now start 2.5 s apart.
- *macOS:* mirror windows are brought to the front so Stage Manager does not hide them.

### Changed
- New original app icon (replaces the placeholder artwork).
- Repository restructured: shared text catalog in `i18n/`, scrcpy downloaded and checksum-verified by `scripts/fetch-scrcpy.sh`.

### Notes
- *Windows:* the 1.0.0 baseline was tested on a Windows PC and worked. The 1.1.0 additions (languages, both screens, staggered start) have so far been verified on macOS only — please report anything odd.

## [1.0.0]
### macOS — 2026-10-01
- First release: live mirror and recording of the rear screen, with scrcpy and adb bundled.
- Photo button (PNG screenshot).
- Quality presets (Light / Normal / Max).
- Wi-Fi: one-click switch from USB, plus manual pairing and connection.
- Helpful status messages (no phone, unauthorized, offline).
- Shows the phone's marketing name (e.g. "Xiaomi 18 Pro Max") read from the device.
- Liquid Glass interface (macOS 26+) with a translucent fallback.

### Windows — 2026-10-14
- First Windows release, ported from the macOS app, with the same features.
- Windows 11 look: Mica background, rounded cards, automatic light/dark theme.
- Single self-contained `.exe` with scrcpy and adb embedded.
- Tested on a physical Windows PC.
