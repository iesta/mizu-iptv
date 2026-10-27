#!/usr/bin/env bash
# Prépare l'archive de distribution macOS + le hash pour le cask Homebrew.
# À exécuter **sur un Mac** (Xcode requis).
#
#   tools/package-macos.sh
#
# Produit dist/Mizu-IPTV-<version>-macos-arm64.zip et affiche son sha256.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ "$(uname -s)" == "Darwin" ]] || {
  echo "ce script doit tourner sur macOS (Xcode requis)" >&2
  exit 1
}

echo "== build release =="
"$ROOT/tools/build.sh" macos

APP="$ROOT/app/build/macos/Build/Products/Release/Mizu IPTV.app"
[[ -d "$APP" ]] || { echo "app introuvable: $APP" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$APP/Contents/Info.plist")
ARCH=$(uname -m)
[[ "$ARCH" == "arm64" ]] && ARCH=arm64 || ARCH=x86_64

mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/Mizu-IPTV-$VERSION-macos-$ARCH.zip"

# ditto préserve les symlinks et les attributs étendus du bundle.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"

echo
echo "archive : $OUT"
echo "sha256  : $(shasum -a 256 "$OUT" | cut -d' ' -f1)"
echo
echo "Publier sur GitHub Releases, puis renseigner @VERSION@ et @SHA256@ dans"
echo "packaging/homebrew/mizu-iptv.rb."
echo
echo "Rappel : sans notarisation, l'utilisateur devra faire clic droit → Ouvrir,"
echo "ou : xattr -dr com.apple.quarantine \"/Applications/Mizu IPTV.app\""
