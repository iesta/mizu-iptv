#!/usr/bin/env bash
# Compile Mizu IPTV en injectant la configuration locale (.env).
#
#   tools/build.sh apk          # APK release
#   tools/build.sh apk-debug    # APK debug
#   tools/build.sh linux        # binaire Linux
#   tools/build.sh macos        # app macOS (sur un Mac)
#
# Le fichier .env est lu à la racine du dépôt (ignoré par git) et passé à
# Flutter via --dart-define-from-file : les valeurs sont compilées dans le
# binaire, donc l'app est configurée dès l'installation.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"
TARGET="${1:-linux}"
shift || true

DEFINES=()
if [[ -f "$ENV_FILE" ]]; then
  DEFINES=("--dart-define-from-file=$ENV_FILE")
  echo "config: $ENV_FILE"
else
  echo "config: aucune (.env absent) — l'app demandera la configuration au lancement"
fi

cd "$ROOT/app"
case "$TARGET" in
  apk)       flutter build apk --release "${DEFINES[@]}" "$@" ;;
  apk-debug) flutter build apk --debug   "${DEFINES[@]}" "$@" ;;
  linux)     flutter build linux         "${DEFINES[@]}" "$@" ;;
  macos)     flutter build macos         "${DEFINES[@]}" "$@" ;;
  *) echo "cible inconnue: $TARGET (apk|apk-debug|linux|macos)" >&2; exit 1 ;;
esac
