# Changelog

All notable changes. Format based on [Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).
The macOS and Windows apps share one version number.

## [1.3.0] — 2026-10-21
### Added
- **Phone frame** (optional, rear screen only): a *Frame* menu that always starts on **No frame**.
  - *macOS:* live mirror inside a phone-shaped window (view only), plus framed photos and framed videos.
  - *Windows:* framed photos.
  - Built-in **Default** frame, an original illustration with the camera module around the rear display.
  - **Transparent background** by default: the desktop shows through around the phone in the live window (with a shadow following its shape) and photos are transparent PNGs. Videos stay black (MP4 has no transparency).
  - **Your own frames**: drop a `frame.png` + `frame.json` folder in your personal folder; `scripts/make-custom-frame.py` builds one from any phone picture (grid, colour detection, lens cut-outs, background removal). The tool never writes inside the repository.
- Guide: [docs/FRAMES.md](docs/FRAMES.md).

### Changed
- README rewritten with an annotated quick tour, a language board and a live-mirror screenshot (the tour and board now show the *Frame* menu).

### Notes
- Live frame mode reads the video stream directly (no scrcpy window), so there is no touch control in that mode.
- Windows: live frame and framed videos are not available yet; the frame code is compiled but untested on a Windows PC.

## [1.2.0] — 2026-10-21
### Added
- **HD ×2 (experimental)** option for the rear screen: doubles its resolution on the phone (`wm size` / `wm density`), so text and widgets are sharper in the mirror, recordings and photos (e.g. 976×596 → 1952×1192). Off by default.
  - Requires **USB debugging (Security settings)** on the phone; a clear message (in six languages) explains it if missing.
  - Only the Xiaomi rear-screen service (`*subscreen*` package) is restarted — never SystemUI or other apps — so the widgets re-layout correctly.
  - The phone is restored automatically when the mirror/recording stops, when the app quits, and **at the next launch** if a ×2 was left active (cable unplugged, crash). A custom display setting made by the user is never touched.
  - The *Screen* menu shows the doubled resolution as soon as the box is ticked; the bitrate is raised automatically while HD ×2 is active.
  - Tested on a Xiaomi 18 Pro Max (HyperOS). Gain is visible on text/widgets, not on the animated wallpaper.
- Annotated quick-tour illustration in the READMEs (and inside the downloadable archives).

### Fixed
- *macOS:* timers were slowed down by App Nap while the mirror window was in front, which delayed the automatic restore by about 10 s (now ~1 s).

### Notes
- *Windows:* the HD ×2 option is compiled and ported from the macOS code but has **not been tested on a Windows PC** yet.
- *macOS:* in one early test the first HD ×2 mirror window stayed black until it was restarted; this could not be reproduced afterwards.

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
