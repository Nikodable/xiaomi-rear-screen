# Releasing

1. **Bump the version** in `VERSION` (SemVer: `1.2.0`).
2. **Update `CHANGELOG.md`**: add a `## [1.2.0] — YYYY-MM-DD` section (Added / Changed / Fixed).
3. If you changed texts: `python3 i18n/generate.py`.
4. **Build and smoke-test** on a real phone:
   - `macos/build.sh` → open the app, mirror, record, photo.
   - `windows/build.sh` → test the `.exe` on a Windows PC (at least: phone detected, mirror, **stop a recording and open the MP4**).
5. **Commit** everything, then run `scripts/release.sh`. It builds both zips, shows the notes taken from the changelog, and — after you confirm — tags `v1.2.0`, pushes the tag and creates the GitHub Release with both files attached.

## Updating scrcpy
Edit the version and the two SHA-256 values at the top of `scripts/fetch-scrcpy.sh` (checksums are on the scrcpy release page), the version in `macos/build.sh` / `windows/EcranArriere.csproj` / `windows/Program.cs` (`Tools.Version`), then rebuild and test. scrcpy 5.x changed some options — re-test mirror, record and `--list-displays`.

## Not done yet (ideas)
- **In-app update check** (reads the latest GitHub Release and shows "Update available" with a link). Deliberately **not implemented** for now.
- Automated builds with GitHub Actions on tag push (the macOS Liquid Glass code needs the macOS 26 SDK on the runner).
- Apple notarization / Windows code signing; Homebrew cask and winget packages.
- Intel macOS build (download `scrcpy-macos-x86_64`, add an x86_64 target).
