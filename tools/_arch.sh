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
