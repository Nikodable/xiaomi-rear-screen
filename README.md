<p align="center"><img src="docs/icon.png" width="112" alt="Rear Screen icon"></p>

# Rear Screen

Mirror, record and photograph the **rear screen** (and the front screen) of a Xiaomi phone from your **Mac** or **PC**, over USB or Wi-Fi — in one click, with no command line.

Built on top of [scrcpy](https://github.com/Genymobile/scrcpy) and `adb`, which are bundled: nothing else to install.
Developed with a Xiaomi 18 Pro Max (rear display), but it works with any Android phone that has several displays — or just one.

## Features
- **Live mirror** of the front screen, the rear screen, or **both at once**
- **Record** to MP4 (one file per screen) · **Photo** to PNG
- Quality presets: Light / Normal / Max
- **Wi-Fi**: one-click switch from USB, or manual pairing with a code
- Shows your phone's real name (e.g. "Xiaomi 18 Pro Max") and clear help when something is wrong
- Six languages: Français, English, Deutsch, Español, Italiano, Português
- macOS: Liquid Glass look · Windows 11: Mica look

## Download
Get the latest build from the **[Releases](https://github.com/Nikodable/xiaomi-rear-screen/releases/latest)** page:

| Platform | File | Install guide |
|---|---|---|
| macOS (Apple Silicon, macOS 12+) | `RearScreen-macOS-arm64-vX.Y.Z.zip` | [macos/README.md](macos/README.md) |
| Windows (x64, Windows 10/11) | `RearScreen-Windows-x64-vX.Y.Z.zip` | [windows/README.md](windows/README.md) |

The apps are not code-signed, so macOS / Windows show a warning on first launch — the install guides explain how to open them.
Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Build from source
```bash
git clone https://github.com/Nikodable/xiaomi-rear-screen.git && cd xiaomi-rear-screen

macos/build.sh      # needs Xcode Command Line Tools; output: macos/dist/
windows/build.sh    # needs the .NET SDK (brew install dotnet); cross-compiles from macOS/Linux; output: windows/dist/
```
`scripts/fetch-scrcpy.sh` downloads scrcpy automatically (and verifies its SHA-256) the first time.
The version number lives in the [`VERSION`](VERSION) file.

## Project layout
```
macos/      AppKit app (Swift, built with swiftc) + build script + icon
windows/    WPF app (C#, .NET) + build script
i18n/       one text catalog → generates Strings.swift and Strings.cs
scripts/    fetch-scrcpy.sh · make-icon.py · release.sh
docs/       icon and release notes for maintainers
third_party/ (not committed) downloaded scrcpy builds
```

## Translations
All texts live in [`i18n/strings.py`](i18n/strings.py). To fix a translation or add a language:
1. Edit `strings.py` (add the language to `LANGS` and a value for every key).
2. Run `python3 i18n/generate.py` — it rewrites `macos/swift/Strings.swift` and `windows/Strings.cs`.
3. Rebuild.

## License
[MIT](LICENSE) for this project's code. Bundled third-party software (scrcpy, adb, SDL, FFmpeg, libusb) keeps its own licenses — see [NOTICE](NOTICE).
Not affiliated with Xiaomi, Google or Genymobile.
