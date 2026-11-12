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
  if ! command -v flutter >/dev/null 2>&1; then
    if [ "$(uname -s)" = "Darwin" ]; then
      cat >&2 <<'MSG'
Flutter introuvable dans le PATH.

Sur macOS :
  brew install --cask flutter
ou : https://docs.flutter.dev/get-started/install/macos
MSG
    elif [ "$FLUTTER_ARCH_DIR" = "arm64" ]; then
      cat >&2 <<'MSG'
Flutter introuvable dans le PATH.

Attention : il n'existe pas de SDK Flutter Linux arm64 précompilé
(les archives officielles sont x86_64 uniquement). Sur une machine arm64, il
faut un SDK bootstrappé — voir HANDOFF.md (section « Asahi Linux arm64 ») —
puis le mettre dans le PATH :

  export PATH="$HOME/dev/tools/flutter/bin:$PATH"
  flutter --version

Sur une machine x86_64, l'AppImage publiée ne demande aucune compilation :
  curl -fsSL https://raw.githubusercontent.com/iesta/mizu-iptv/main/tools/get.sh | sh
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
