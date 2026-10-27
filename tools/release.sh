#!/usr/bin/env bash
# Prépare et publie une release GitHub (AppImage + sommes de contrôle).
#
#   tools/release.sh 0.1.0              # release publique
#   tools/release.sh 0.1.0 --draft      # brouillon (invisible)
#   tools/release.sh 0.1.0 --apk        # inclut aussi l'APK debug
#
# Prérequis : gh authentifié, dépôt avec remote `origin`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tools/_arch.sh"

VERSION=""
DRAFT=0
WITH_APK=0

for arg in "$@"; do
  case "$arg" in
    --draft) DRAFT=1 ;;
    --apk)   WITH_APK=1 ;;
    -*)      echo "option inconnue: $arg" >&2; exit 1 ;;
    *)       VERSION="${arg#v}" ;;
  esac
done

[[ -n "$VERSION" ]] || {
  echo "usage: tools/release.sh <version> [--draft] [--apk]" >&2
  exit 1
}

cd "$ROOT"

echo "== AppImage =="
./tools/package-appimage.sh

FILES=("dist/Mizu-IPTV-$APPIMAGE_ARCH.AppImage")

if [[ "$WITH_APK" -eq 1 ]]; then
  echo "== APK =="
  ./tools/build.sh apk
  APK="app/build/app/outputs/flutter-apk/app-release.apk"
  cp "$APK" "dist/Mizu-IPTV-$VERSION.apk"
  FILES+=("dist/Mizu-IPTV-$VERSION.apk")
fi

echo "== sommes de contrôle =="
( cd dist && shasum -a 256 Mizu-IPTV-* > SHA256SUMS )
FILES+=("dist/SHA256SUMS")
cat dist/SHA256SUMS

ARGS=(release create "v$VERSION" "${FILES[@]}"
      --title "Mizu IPTV $VERSION" --generate-notes)
[[ "$DRAFT" -eq 1 ]] && ARGS+=(--draft)

echo "== gh ${ARGS[*]} =="
gh "${ARGS[@]}"

echo
echo "release v$VERSION créée."
[[ "$DRAFT" -eq 1 ]] && echo "Brouillon : publier depuis l'interface GitHub quand tu es prêt."
echo "Installation en une ligne (une fois publique) :"
echo "  curl -fsSL https://raw.githubusercontent.com/iesta/mizu-iptv/main/tools/get.sh | sh"
