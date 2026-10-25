#!/usr/bin/env bash
# Construit une AppImage autonome de Mizu IPTV.
#
#   tools/package-appimage.sh
#
# Prérequis : rien de particulier (appimagetool est téléchargé dans
# ~/.cache/mizu-tools s'il manque). Le binaire est portable : il embarque
# Flutter, libmpv et les assets, et se lance sans installation.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ID="app.mizu.iptv"
NAME="Mizu IPTV"
DIST="$ROOT/dist"
BUILD="$ROOT/app/build/linux/x64/release/bundle"
TOOLS="${XDG_CACHE_HOME:-$HOME/.cache}/mizu-tools"
ARCH="x86_64"

echo "== build release =="
"$ROOT/tools/build.sh" linux

[[ -x "$BUILD/mizu_iptv" ]] || { echo "bundle introuvable: $BUILD" >&2; exit 1; }

echo "== AppDir =="
APPDIR="$DIST/Mizu.AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/lib/mizu" "$APPDIR/usr/share/icons/hicolor/256x256/apps" \
         "$APPDIR/usr/share/applications"
cp -a "$BUILD/." "$APPDIR/usr/lib/mizu/"
cp "$ROOT/app/assets/logo_256.png" "$APPDIR/$APP_ID.png"
cp "$ROOT/app/assets/logo_256.png" "$APPDIR/.DirIcon"
cp "$ROOT/app/assets/logo_256.png" \
   "$APPDIR/usr/share/icons/hicolor/256x256/apps/$APP_ID.png"

cat > "$APPDIR/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$NAME
Comment=Client IPTV synchronisé (compte Zen)
Exec=mizu_iptv
Icon=$APP_ID
Terminal=false
Categories=AudioVideo;Video;Player;TV;
StartupWMClass=$APP_ID
X-AppImage-Version=1.0
EOF
cp "$APPDIR/$APP_ID.desktop" "$APPDIR/usr/share/applications/"

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
# AppRun : lance le bundle Flutter embarqué.
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/mizu/mizu_iptv" "$@"
EOF
chmod +x "$APPDIR/AppRun"

echo "== appimagetool =="
TOOL="$TOOLS/appimagetool-$ARCH.AppImage"
if [[ ! -x "$TOOL" ]]; then
  mkdir -p "$TOOLS"
  curl -sSL -o "$TOOL" \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ARCH.AppImage"
  chmod +x "$TOOL"
fi

echo "== AppImage =="
mkdir -p "$DIST"
OUT="$DIST/Mizu-IPTV-$ARCH.AppImage"
ARCH=$ARCH "$TOOL" --no-appstream "$APPDIR" "$OUT" \
  || ARCH=$ARCH "$TOOL" --appimage-extract-and-run --no-appstream "$APPDIR" "$OUT"

rm -rf "$APPDIR"
ls -lh "$OUT"
echo
echo "Lancer : $OUT"
echo "Installer (optionnel) : ~/.local/bin + entrée .desktop via tools/install-linux.sh"
