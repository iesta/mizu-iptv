#!/bin/sh
# Installation en une ligne (Linux) :
#
#   curl -fsSL https://raw.githubusercontent.com/iesta/mizu-iptv/main/tools/get.sh | sh
#
# Télécharge la dernière AppImage publiée, l'installe dans ~/.local (sans root)
# et crée le lanceur + l'entrée de menu.
#
# Test local (sans release) :
#   ./tools/get.sh --from dist/Mizu-IPTV-x86_64.AppImage
#
# Désinstallation : ~/.local/share/mizu/uninstall.sh
set -eu

REPO="iesta/mizu-iptv"
RAW="https://raw.githubusercontent.com/$REPO/main"
FROM=""

while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM="$2"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "option inconnue: $1" >&2; exit 1 ;;
  esac
done

case "$(uname -s)" in
  Linux) ;;
  *) echo "Ce script installe la version Linux. macOS : voir le README (Homebrew)." >&2; exit 1 ;;
esac

case "$(uname -m)" in
  aarch64|arm64) ARCH=aarch64 ;;
  x86_64|amd64)  ARCH=x86_64 ;;
  *) echo "architecture non gérée : $(uname -m)" >&2; exit 1 ;;
esac

PREFIX="${HOME}/.local"
APP_DIR="$PREFIX/opt/mizu-app"
BIN="$PREFIX/bin/mizu"
DESKTOP_DIR="$PREFIX/share/applications"
ICON_DIR="$PREFIX/share/icons/hicolor/256x256/apps"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

if [ -n "$FROM" ]; then
  SRC="$FROM"
  echo "source locale : $SRC"
else
  SRC="$TMP/mizu.AppImage"
  URL="https://github.com/$REPO/releases/latest/download/Mizu-IPTV-$ARCH.AppImage"
  echo "téléchargement : $URL"
  if ! curl -fsSL -o "$SRC" "$URL"; then
    cat >&2 <<EOF

Aucune release téléchargeable pour $ARCH.

Trois alternatives :
  1. Paquets gérés : flatpak install --user ./app.mizu.iptv.flatpak
  2. Compiler depuis les sources : voir README, section « Installer »
  3. Arch/Omarchy : yay -S mizu-iptv (une fois publié sur l'AUR)

EOF
    exit 1
  fi
fi

[ -f "$SRC" ] || { echo "fichier introuvable : $SRC" >&2; exit 1; }

echo "installation dans $APP_DIR"
mkdir -p "$APP_DIR" "$(dirname "$BIN")" "$DESKTOP_DIR" "$ICON_DIR"
cp "$SRC" "$APP_DIR/mizu.AppImage"
chmod 755 "$APP_DIR/mizu.AppImage"
ln -sf "$APP_DIR/mizu.AppImage" "$BIN"

# Icône : depuis la release si possible, sinon embarquée dans l'AppImage.
if ! curl -fsSL -o "$ICON_DIR/app.mizu.iptv.png" \
      "$RAW/app/assets/logo_256.png" 2>/dev/null; then
  "$APP_DIR/mizu.AppImage" --appimage-extract 'app.mizu.iptv.png' >/dev/null 2>&1 \
    && cp squashfs-root/app.mizu.iptv.png "$ICON_DIR/app.mizu.iptv.png" 2>/dev/null \
    && rm -rf squashfs-root || true
fi

cat > "$DESKTOP_DIR/app.mizu.iptv.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Mizu IPTV
GenericName=IPTV Player
Comment=Client IPTV synchronisé (compte Zen)
Exec=$APP_DIR/mizu.AppImage
Icon=app.mizu.iptv
Terminal=false
Categories=AudioVideo;Video;Player;TV;
Keywords=iptv;tv;live;m3u;xtream;
StartupNotify=true
StartupWMClass=app.mizu.iptv
EOF

cat > "$PREFIX/share/mizu/uninstall.sh" <<EOF
#!/bin/sh
# Désinstalle Mizu IPTV installé par tools/get.sh
rm -f "$BIN" "$DESKTOP_DIR/app.mizu.iptv.desktop" "$ICON_DIR/app.mizu.iptv.png"
rm -rf "$APP_DIR" "$PREFIX/share/mizu"
echo "Mizu IPTV désinstallé."
EOF
chmod 755 "$PREFIX/share/mizu/uninstall.sh"

command -v update-desktop-database >/dev/null 2>&1 && \
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true

echo
echo "installé :"
echo "  $APP_DIR/mizu.AppImage"
echo "  $BIN  (lanceur terminal)"
echo "  $DESKTOP_DIR/app.mizu.iptv.desktop"
echo
echo "Lancer : mizu"
echo "Désinstaller : $PREFIX/share/mizu/uninstall.sh"
