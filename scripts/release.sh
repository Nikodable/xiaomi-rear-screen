#!/usr/bin/env bash
# Construit les deux archives et crée la GitHub Release correspondante (nécessite la CLI `gh`, connectée).
# Rien n'est publié sans confirmation. Voir docs/RELEASING.md.
# Option --dry-run : construit les archives et affiche les notes, sans rien commiter, taguer ni publier.
set -euo pipefail
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"

if [[ $DRY -eq 0 ]]; then
  command -v gh >/dev/null || { echo "La CLI GitHub (gh) est requise : https://cli.github.com"; exit 1; }
  git diff --quiet && git diff --cached --quiet || { echo "Des modifications ne sont pas commitées."; exit 1; }
  [[ -z "$(git ls-files --others --exclude-standard)" ]] || { echo "Des fichiers ne sont pas suivis par git (git add)."; exit 1; }
else
  echo "[simulation] rien ne sera commité, tagué ni publié."
fi
grep -q "^## \[$VERSION\]" CHANGELOG.md || { echo "CHANGELOG.md n'a pas de section [$VERSION]."; exit 1; }
git rev-parse "$TAG" >/dev/null 2>&1 && { echo "Le tag $TAG existe déjà."; exit 1; }

macos/build.sh
windows/build.sh

NOTES="$(mktemp)"
awk -v v="$VERSION" '$0 ~ "^## \\["v"\\]" {p=1; next} /^## \[/ {p=0} p' CHANGELOG.md > "$NOTES"
FILES=("macos/dist/RearScreen-macOS-arm64-v$VERSION.zip" "windows/dist/RearScreen-Windows-x64-v$VERSION.zip")

echo; echo "Version : $VERSION  (tag $TAG)"; printf ' - %s\n' "${FILES[@]}"; echo "Notes :"; sed 's/^/   /' "$NOTES"; echo
[[ $DRY -eq 1 ]] && { echo; echo "[simulation terminée] archives prêtes ci-dessus ; aucune publication."; exit 0; }
read -r -p "Créer le tag et publier la release sur GitHub ? [y/N] " ok
[[ "$ok" == "y" ]] || { echo "Annulé."; exit 0; }

git tag "$TAG" && git push origin "$TAG"
gh release create "$TAG" "${FILES[@]}" --title "Rear Screen $VERSION" --notes-file "$NOTES"
