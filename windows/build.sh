#!/usr/bin/env bash
# Compile EcranArriere.exe (Windows x64, autonome) depuis macOS ou Linux. Sortie : windows/dist/
# Prérequis : SDK .NET (macOS : brew install dotnet). Sous Windows : voir la commande « dotnet publish » en bas.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
ZIP="RearScreen-Windows-x64-v$VERSION.zip"

[[ -f "$ROOT/third_party/scrcpy-win64-v4.1.zip" ]] || "$ROOT/scripts/fetch-scrcpy.sh" --win

if ! command -v dotnet >/dev/null && command -v brew >/dev/null; then
  export DOTNET_ROOT="${DOTNET_ROOT:-$(brew --prefix dotnet)/libexec}"
  export PATH="$(brew --prefix dotnet)/bin:$PATH"
fi
export DOTNET_CLI_TELEMETRY_OPTOUT=1

rm -rf dist
dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -p:Version="$VERSION" -o dist
(
  cd dist
  rm -f ./*.pdb
  { cat ../README.md; printf '\n---\n\n'; cat "$ROOT/CHANGELOG.md"; } > README.md
  cp "$ROOT/NOTICE" NOTICE.txt
  zip -q "$ZIP" EcranArriere.exe README.md NOTICE.txt
)
ls -lh "dist/$ZIP"
# Sous Windows (PowerShell), une fois third_party/scrcpy-win64-v4.1.zip en place :
#   dotnet publish windows -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o windows/dist
