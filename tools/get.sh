#!/bin/sh
# Installation en une ligne (Linux) :
#
#   curl -fsSL https://raw.githubusercontent.com/iesta/mizu-iptv/main/tools/get.sh | sh
#
# Télécharge la dernière AppImage, l'installe dans ~/.local (sans root), crée le
# lanceur, l'entrée de menu et l'icône. Demande au passage quel backend Supabase
# utiliser (celui de Zen IPTV par défaut).
#
# Options (ou variables d'environnement équivalentes) :
#   --backend zen|own     MIZU_BACKEND      (défaut : question, sinon zen)
#   --url URL             MIZU_BACKEND_URL
#   --key KEY             MIZU_PUBLISHABLE_KEY
#   --from FICHIER        installe une AppImage locale (test, hors ligne)
#
# Désinstallation : ~/.local/share/mizu/uninstall.sh
set -eu

REPO="iesta/mizu-iptv"
RAW="https://raw.githubusercontent.com/$REPO/main"

# Backend public de Zen IPTV (clé « publishable », publique par conception :
# elle est aussi embarquée dans l'AppImage distribuée).
ZEN_URL="https://api.zeniptv.app"
ZEN_KEY="sb_publishable_FHN4ODlO5E4bt0ezliSoqQ_3CgYEyQs"

FROM=""
BACKEND="${MIZU_BACKEND:-}"
OWN_URL="${MIZU_BACKEND_URL:-}"
OWN_KEY="${MIZU_PUBLISHABLE_KEY:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --from)    FROM="$2"; shift 2 ;;
    --backend) BACKEND="$2"; shift 2 ;;
    --url)     OWN_URL="$2"; shift 2 ;;
    --key)     OWN_KEY="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "option inconnue: $1" >&2; exit 1 ;;
  esac
done

case "$(uname -s)" in
  Linux) ;;
  *) echo "Ce script installe la version Linux. macOS : voir INSTALL.md (Homebrew)." >&2; exit 1 ;;
esac

case "$(uname -m)" in
  aarch64|arm64) ARCH=aarch64 ;;
  x86_64|amd64)  ARCH=x86_64 ;;
  *) echo "architecture non gérée : $(uname -m)" >&2; exit 1 ;;
esac

# --- Backend ---------------------------------------------------------------
# `curl | sh` : stdin est le script, donc on lit les réponses sur /dev/tty.
if [ -z "$BACKEND" ]; then
  if [ -r /dev/tty ]; then
    printf '\nUtiliser le backend Supabase de Zen IPTV ? [O/n] ' >&2
    if read -r answer </dev/tty; then :; else answer=""; fi
    case "$answer" in
      n|N|non|no) BACKEND=own ;;
      *)          BACKEND=zen ;;
    esac
  else
    BACKEND=zen
  fi
fi

if [ "$BACKEND" != "zen" ]; then
  if [ -z "$OWN_URL" ] && [ -r /dev/tty ]; then
    printf 'URL de ton instance Supabase (https://xxx.supabase.co) : ' >&2
    read -r OWN_URL </dev/tty || OWN_URL=""
  fi
  if [ -z "$OWN_KEY" ] && [ -r /dev/tty ]; then
    printf 'Clé publishable (sb_publishable_...) : ' >&2
    read -r OWN_KEY </dev/tty || OWN_KEY=""
  fi
  if [ -z "$OWN_URL" ] || [ -z "$OWN_KEY" ]; then
    echo "URL et clé requises pour un backend personnalisé (--url / --key)." >&2
    exit 1
  fi
  CFG_URL="$OWN_URL"
  CFG_KEY="$OWN_KEY"
else
  CFG_URL="$ZEN_URL"
  CFG_KEY="$ZEN_KEY"
fi

# --- Téléchargement --------------------------------------------------------
PREFIX="${HOME}/.local"
APP_DIR="$PREFIX/opt/mizu-app"
BIN="$PREFIX/bin/mizu"
DESKTOP_DIR="$PREFIX/share/applications"
ICON_DIR="$PREFIX/share/icons/hicolor/256x256/apps"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mizu"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

if [ -n "$FROM" ]; then
  SRC="$FROM"
  echo "source locale : $SRC"
else
  SRC="$TMP/mizu.AppImage"
  API="https://api.github.com/repos/$REPO/releases/latest"

  echo "recherche de la dernière release…"
  ASSETS="$(curl -fsSL "$API" 2>/dev/null | tr ',' '\n' \
            | grep -o 'https://[^"]*\.AppImage' | sort -u || true)"

  if [ -z "$ASSETS" ]; then
    cat >&2 <<EOF

Aucune release publiée pour l'instant.

Installer depuis les sources :
  git clone https://github.com/$REPO.git && cd mizu-iptv
  ./tools/install-linux.sh

Autres méthodes : INSTALL.md

EOF
    exit 1
  fi

  URL="$(printf '%s\n' "$ASSETS" | grep -- "-$ARCH\.AppImage$" | head -1 || true)"
  if [ -z "$URL" ]; then
    AVAILABLE="$(printf '%s\n' "$ASSETS" | sed 's|.*/||' | tr '\n' ' ')"
    cat >&2 <<EOF

Pas d'AppImage pour $ARCH dans la dernière release.
Disponible : $AVAILABLE

Construis-la sur cette machine (les scripts détectent l'architecture) :
  git clone https://github.com/$REPO.git && cd mizu-iptv
  ./tools/install-linux.sh                 # build + installation dans ~/.local
  # ou seulement l'artefact portable :
  ./tools/package-appimage.sh

EOF
    exit 1
  fi

  echo "téléchargement : $URL"
  if ! curl -fsSL -o "$SRC" "$URL"; then
    echo "téléchargement impossible : $URL" >&2
    echo "Installer depuis les sources : voir INSTALL.md" >&2
    exit 1
  fi
fi

[ -f "$SRC" ] || { echo "fichier introuvable : $SRC" >&2; exit 1; }

# --- Installation ----------------------------------------------------------
echo "installation dans $APP_DIR"
mkdir -p "$APP_DIR" "$(dirname "$BIN")" "$DESKTOP_DIR" "$ICON_DIR" \
         "$PREFIX/share/mizu"
cp "$SRC" "$APP_DIR/mizu.AppImage"
chmod 755 "$APP_DIR/mizu.AppImage"
ln -sf "$APP_DIR/mizu.AppImage" "$BIN"

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
rm -f "$BIN" "$DESKTOP_DIR/app.mizu.iptv.desktop" "$ICON_DIR/app.mizu.iptv.png"
rm -rf "$APP_DIR" "$PREFIX/share/mizu"
echo "Mizu IPTV désinstallé."
EOF
chmod 755 "$PREFIX/share/mizu/uninstall.sh"

# --- Configuration du backend ---------------------------------------------
# config.json prime sur les valeurs compilées dans l'AppImage : écrire ici
# garantit le comportement choisi, même si le binaire embarque un défaut.
mkdir -p "$CONFIG_DIR"
OLD_UMASK=$(umask)
umask 077
cat > "$CONFIG_DIR/config.json" <<EOF
{
  "backend_url": "$CFG_URL",
  "publishable_key": "$CFG_KEY"
}
EOF
umask "$OLD_UMASK"

command -v update-desktop-database >/dev/null 2>&1 && \
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true

echo
echo "installé :"
echo "  $APP_DIR/mizu.AppImage"
echo "  $BIN  (lanceur terminal)"
echo "  $DESKTOP_DIR/app.mizu.iptv.desktop"
echo "  backend : $CFG_URL"
if [ "$BACKEND" = "zen" ]; then
  echo "  (compte Zen IPTV ; change-le dans Préférences si besoin)"
else
  echo "  (instance personnelle ; la base doit être préparée, voir SUPABASE.md)"
fi
echo
echo "Lancer : mizu"
echo "Désinstaller : $PREFIX/share/mizu/uninstall.sh"
