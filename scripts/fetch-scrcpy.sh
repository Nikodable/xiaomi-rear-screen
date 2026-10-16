#!/usr/bin/env bash
# Télécharge scrcpy (officiel, Genymobile) dans third_party/ et vérifie l'empreinte SHA-256.
# Usage : scripts/fetch-scrcpy.sh [--mac] [--win]   (sans option : les deux)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/third_party"
V="4.1"
BASE="https://github.com/Genymobile/scrcpy/releases/download/v$V"

MAC_FILE="scrcpy-macos-aarch64-v$V.tar.gz"
MAC_SHA="20fd47c9014dd5e0fa77091f3cb7adbda8445a360c4584aeaa0150b5b3988ff3"
WIN_FILE="scrcpy-win64-v$V.zip"
WIN_SHA="5b12172b3264b2889f4583ee64752ce832e29bc8b1089dca81093459697165db"

want_mac=0; want_win=0
if [[ $# -eq 0 ]]; then want_mac=1; want_win=1; fi
for a in "$@"; do case "$a" in --mac) want_mac=1;; --win) want_win=1;; *) echo "option inconnue : $a"; exit 2;; esac; done

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

fetch() { # fichier empreinte
  local f="$1" sum="$2"
  mkdir -p "$DEST"
  if [[ ! -f "$DEST/$f" ]]; then
    echo "→ téléchargement de $f"
    curl -fL --progress-bar -o "$DEST/$f" "$BASE/$f"
  fi
  if [[ "$(sha256 "$DEST/$f")" != "$sum" ]]; then
    echo "✗ empreinte SHA-256 inattendue pour $f — fichier supprimé" >&2
    rm -f "$DEST/$f"; exit 1
  fi
  echo "✓ $f vérifié"
}

if [[ $want_mac -eq 1 ]]; then
  fetch "$MAC_FILE" "$MAC_SHA"
  [[ -x "$DEST/scrcpy-macos-aarch64-v$V/scrcpy" ]] || tar -xzf "$DEST/$MAC_FILE" -C "$DEST"
fi
if [[ $want_win -eq 1 ]]; then
  # le zip est embarqué tel quel dans l'exécutable Windows
  fetch "$WIN_FILE" "$WIN_SHA"
  [[ -f "$DEST/scrcpy-win64-v$V.zip" ]]
fi
