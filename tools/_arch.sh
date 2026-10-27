# Détection d'architecture partagée par les scripts de packaging.
# À sourcer : . "$(dirname "$0")/_arch.sh"
#
# FLUTTER_ARCH_DIR : nom du dossier produit par `flutter build linux`
# APPIMAGE_ARCH    : nom utilisé par appimagetool
case "$(uname -m)" in
  aarch64|arm64)
    FLUTTER_ARCH_DIR="arm64"
    APPIMAGE_ARCH="aarch64"
    ;;
  x86_64|amd64)
    FLUTTER_ARCH_DIR="x64"
    APPIMAGE_ARCH="x86_64"
    ;;
  *)
    echo "architecture non gérée : $(uname -m)" >&2
    exit 1
    ;;
esac

# Vérifie que Flutter est utilisable pour compiler (message utile sinon).
# $1 = cible (linux, apk, apk-debug, macos…). Le blocage « pas de SDK Linux
# arm64 » ne concerne que la cible Linux desktop : un APK Android se compile
# sans problème depuis un hôte arm64.
require_flutter() {
  local target="${1:-linux}"
  if [ "$(uname -s)" = "Linux" ] && [ "$FLUTTER_ARCH_DIR" = "arm64" ] &&
     [ "$target" = "linux" ]; then
    cat >&2 <<'MSG'
Linux arm64 : Flutter ne publie pas de SDK Linux arm64 (x86_64 uniquement).
Un build local est donc impossible avec le SDK officiel — voir INSTALL.md,
section « aarch64 / arm64 ». Sur une machine x86_64, l'AppImage publiée
fonctionne sans rien compiler : voir la méthode « une ligne » du README.
MSG
    exit 1
  fi

  if ! command -v flutter >/dev/null 2>&1; then
    if [ "$(uname -s)" = "Darwin" ]; then
      cat >&2 <<'MSG'
Flutter introuvable dans le PATH.

Sur macOS :
  brew install --cask flutter
ou : https://docs.flutter.dev/get-started/install/macos
MSG
    else
      cat >&2 <<'MSG'
Flutter introuvable dans le PATH.

Option la plus rapide (aucune compilation) — si tu es en x86_64 :
  curl -fsSL https://raw.githubusercontent.com/iesta/mizu-iptv/main/tools/get.sh | sh

Pour compiler depuis les sources, installe le SDK :
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git ~/flutter
  export PATH="$HOME/flutter/bin:$PATH"

Puis relance ce script. Détails par distribution : INSTALL.md
MSG
    fi
    exit 1
  fi
}
