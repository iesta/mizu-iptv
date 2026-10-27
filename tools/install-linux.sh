#!/usr/bin/env bash
# Installe Mizu IPTV pour l'utilisateur courant (sans root).
#
#   tools/install-linux.sh            # build release + installation
#   tools/install-linux.sh --no-build # réinstalle le dernier build
#
# Emplacements :
#   ~/.local/opt/mizu/                                   application
#   ~/.local/bin/mizu                                    lanceur en terminal
#   ~/.local/share/applications/app.mizu.iptv.desktop    entrée de menu
#   ~/.local/share/icons/hicolor/*/apps/app.mizu.iptv.png
#
# Désinstallation : tools/install-linux.sh --uninstall
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tools/_arch.sh"
APP_ID="app.mizu.iptv"
DEST="$HOME/.local/opt/mizu"
BIN_LINK="$HOME/.local/bin/mizu"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_ROOT="$HOME/.local/share/icons/hicolor"

uninstall() {
  echo "== désinstallation =="
  rm -rf "$DEST"
  rm -f "$BIN_LINK"
  rm -f "$DESKTOP_DIR/$APP_ID.desktop"
  find "$ICON_ROOT" -name "$APP_ID.png" -delete 2>/dev/null || true
  command -v update-desktop-database >/dev/null && \
    update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
  echo "terminé."
  exit 0
}

if [[ "${1:-}" == "--uninstall" ]]; then
  uninstall
fi

NO_BUILD=0
[[ "${1:-}" == "--no-build" ]] && NO_BUILD=1

if [[ "$NO_BUILD" -eq 0 ]]; then
  echo "== build release =="
  "$ROOT/tools/build.sh" linux
fi

BUNDLE="$ROOT/app/build/linux/$FLUTTER_ARCH_DIR/release/bundle"
[[ -x "$BUNDLE/mizu_iptv" ]] || {
  echo "build introuvable : $BUNDLE" >&2
  exit 1
}

echo "== installation dans ~/.local =="
rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$BUNDLE/." "$DEST/"

mkdir -p "$(dirname "$BIN_LINK")"
ln -sf "$DEST/mizu_iptv" "$BIN_LINK"

# Icônes (menu, docks, aperçus)
for size in 256 512; do
  src="$ROOT/app/assets/logo_$size.png"
  [[ -f "$src" ]] || src="$ROOT/app/assets/logo.png"
  dir="$ICON_ROOT/${size}x${size}/apps"
  mkdir -p "$dir"
  cp "$src" "$dir/$APP_ID.png"
done

mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_DIR/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Mizu IPTV
GenericName=IPTV Player
Comment=Client IPTV synchronisé (compte Zen)
Exec=$DEST/mizu_iptv
TryExec=$DEST/mizu_iptv
Icon=$APP_ID
Terminal=false
Categories=AudioVideo;Video;Player;TV;
Keywords=iptv;tv;live;m3u;xtream;stream;
StartupNotify=true
StartupWMClass=$APP_ID
EOF

command -v desktop-file-validate >/dev/null && \
  desktop-file-validate "$DESKTOP_DIR/$APP_ID.desktop" || true
command -v update-desktop-database >/dev/null && \
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
command -v gtk-update-icon-cache >/dev/null && \
  gtk-update-icon-cache -f -t "$ICON_ROOT" >/dev/null 2>&1 || true

echo
echo "installé :"
echo "  binaire   $DEST/mizu_iptv"
echo "  terminal  $BIN_LINK"
echo "  menu      $DESKTOP_DIR/$APP_ID.desktop"
echo "  icône     $ICON_ROOT/256x256/apps/$APP_ID.png"
echo
echo "Lance-le depuis le menu Omarchy (Super + Espace), ou : mizu"
