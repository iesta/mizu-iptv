#!/usr/bin/env bash
# Construit (et installe si demandé) le Flatpak de Mizu IPTV.
#
#   tools/package-flatpak.sh            # construit dist/app.mizu.iptv.flatpak
#   tools/package-flatpak.sh --install  # + installation utilisateur + lancement
#
# Prérequis : flatpak et flatpak-builder.
#   Arch/Omarchy : sudo pacman -S flatpak flatpak-builder
#   puis : flatpak remote-add --if-not-exists --user flathub \
#            https://flathub.org/repo/flathub.flatpakrepo
#          flatpak install --user flathub org.freedesktop.Platform//24.08 \
#            org.freedesktop.Sdk//24.08
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/packaging/flatpak/app.mizu.iptv.yml"
DIST="$ROOT/dist"
BUILD_DIR="$ROOT/dist/flatpak-build"

command -v flatpak >/dev/null || { echo "flatpak manquant" >&2; exit 1; }
command -v flatpak-builder >/dev/null || {
  echo "flatpak-builder manquant : sudo pacman -S flatpak-builder" >&2
  exit 1
}

echo "== build release =="
"$ROOT/tools/build.sh" linux

echo "== flatpak-builder =="
mkdir -p "$DIST"
flatpak-builder --user --force-clean --repo="$DIST/repo" "$BUILD_DIR" "$MANIFEST"

echo "== bundle =="
OUT="$DIST/app.mizu.iptv.flatpak"
flatpak build-bundle "$DIST/repo" "$OUT" app.mizu.iptv
ls -lh "$OUT"

if [[ "${1:-}" == "--install" ]]; then
  echo "== installation utilisateur =="
  flatpak install --user -y --reinstall "$OUT"
  flatpak run app.mizu.iptv
fi

echo
echo "Installer plus tard : flatpak install --user $OUT"
echo "Lancer : flatpak run app.mizu.iptv"
