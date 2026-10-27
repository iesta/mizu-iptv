#!/usr/bin/env bash
# Recrée la stack de synchronisation Zen sur TON projet Supabase, via la CLI.
#
#   re/supabase/setup.sh                      # interactif
#   re/supabase/setup.sh --project-ref abcdefghijklmnopqrst
#   re/supabase/setup.sh --project-ref … --password 'mypass' --seed
#
# Prérequis : CLI Supabase (binaire `supabase`, sinon `npx supabase`), et un
# `supabase login` (ou SUPABASE_ACCESS_TOKEN). Le script demande le mot de
# passe de la base du projet quand la CLI en a besoin.
#
# Ce qu'il fait :
#   1. vérifie l'authentification et choisit le projet
#   2. génère une migration à partir de schema.sql
#   3. `supabase db push` (applique le schéma : tables, index, RLS, RPC)
#   4. option --seed : importe tes données (export-data.py + psql/--db-url)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCHEMA="$HERE/schema.sql"
WORKDIR="$HERE/cli"                 # contient supabase/migrations/
MIGRATIONS="$WORKDIR/supabase/migrations"

PROJECT_REF=""
DB_PASSWORD=""
DB_URL=""
WITH_SEED=0
DRY_RUN=0
YES=0

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-ref) PROJECT_REF="$2"; shift 2 ;;
    --password)    DB_PASSWORD="$2"; shift 2 ;;
    --db-url)      DB_URL="$2"; shift 2 ;;
    --seed)        WITH_SEED=1; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    --yes|-y)      YES=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "option inconnue: $1" >&2; exit 1 ;;
  esac
done

# Validation précoce de la ref (avant tout appel réseau)
if [[ -n "$PROJECT_REF" ]] && [[ ! "$PROJECT_REF" =~ ^[a-z0-9]{20}$ ]]; then
  echo "ref invalide : '$PROJECT_REF' (20 caractères, ex. abcdefghijklmnopqrst)" >&2
  exit 1
fi

# --- CLI Supabase ----------------------------------------------------------
if command -v supabase >/dev/null 2>&1; then
  SUPA=(supabase)
elif command -v npx >/dev/null 2>&1; then
  SUPA=(npx --yes supabase@latest)
  echo "CLI supabase absent : utilisation de 'npx supabase' (téléchargement à la première exécution)."
else
  cat >&2 <<'EOF'
CLI Supabase introuvable.
  npm i -g supabase          # ou : brew install supabase/tap/supabase
  # Arch : yay -S supabase-bin   (ou npx supabase)
EOF
  exit 1
fi

run() { "${SUPA[@]}" "$@"; }

echo "== version =="
run --version

# --- Authentification ------------------------------------------------------
if ! run projects list -o json >/dev/null 2>&1; then
  echo
  echo "Non authentifié (ou jeton invalide)."
  if [[ -t 0 ]] && [[ "$YES" -eq 0 ]]; then
    echo "Ouverture de 'supabase login'…"
    run login
  else
    cat >&2 <<'EOF'
Authentifie-toi d'abord :
  supabase login
ou exporte SUPABASE_ACCESS_TOKEN=sbp_… (Personal Access Token)
EOF
    exit 1
  fi
fi

# --- Choix du projet -------------------------------------------------------
if [[ -z "$PROJECT_REF" ]]; then
  echo
  echo "== projets disponibles =="
  TMP_JSON="$(mktemp)"
  if run projects list -o json >"$TMP_JSON" 2>/dev/null; then
    python3 - "$TMP_JSON" <<'PYLIST'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("  (liste illisible)")
    sys.exit(0)
if isinstance(data, dict):
    data = data.get("projects", [])
if not data:
    print("  (aucun projet)")
for i, p in enumerate(data, 1):
    ref = p.get("id") or p.get("ref") or ""
    print(f"  {i}. {p.get('name','')}  [{ref}]  {p.get('region','')}")
PYLIST
  else
    echo "  (impossible de lister les projets)"
  fi
  rm -f "$TMP_JSON"
  printf '\nRef du projet (ou Entrée pour annuler) : '
  read -r PROJECT_REF || PROJECT_REF=""
  [[ -n "$PROJECT_REF" ]] || { echo "annulé."; exit 0; }
fi

# --- Migration depuis schema.sql ------------------------------------------
mkdir -p "$MIGRATIONS"
STAMP="$(date +%Y%m%d%H%M%S)"
MIGRATION="$MIGRATIONS/${STAMP}_zen_init.sql"
{
  echo "-- Généré par re/supabase/setup.sh à partir de schema.sql"
  echo "-- Projet : $PROJECT_REF — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  cat "$SCHEMA"
} > "$MIGRATION"
echo
echo "migration : $MIGRATION"

# --- Push ------------------------------------------------------------------
if [[ -n "$DB_URL" ]]; then
  PUSH_ARGS=(db push --db-url "$DB_URL" --yes)
else
  PUSH_ARGS=(db push --project-ref "$PROJECT_REF" --yes)
  [[ -n "$DB_PASSWORD" ]] && PUSH_ARGS+=(--password "$DB_PASSWORD")
fi
[[ "$DRY_RUN" -eq 1 ]] && PUSH_ARGS+=(--dry-run)

echo
echo "== supabase ${PUSH_ARGS[*]} =="
run "${PUSH_ARGS[@]}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo
  echo "mode --dry-run : rien n'a été appliqué."
  exit 0
fi

# --- Données (optionnel) ---------------------------------------------------
if [[ "$WITH_SEED" -eq 1 ]]; then
  echo
  echo "== données =="
  SEED="$HERE/seed.sql"
  python3 "$HERE/export-data.py" --out "$SEED"

  if [[ -n "$DB_URL" ]] && command -v psql >/dev/null 2>&1; then
    echo "application de seed.sql via psql…"
    psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$SEED"
  else
    cat <<EOF

seed.sql généré : $SEED

Pour l'importer, au choix :
  • SQL Editor du dashboard → coller le contenu du fichier
  • psql "<connection string>" -f "$SEED"
    (la connection string est dans Project Settings → Database ; ajoute
     --db-url "<connection string>" pour que ce script le fasse)

EOF
  fi
else
  echo
  echo "(données non importées ; relance avec --seed, ou exécute export-data.py)"
fi

cat <<EOF

== terminé ==
Projet : https://$PROJECT_REF.supabase.co

Il reste à :
  1. Authentication → Providers → activer Email (Apple/Google en option)
  2. créer ton utilisateur (écran d'inscription de Mizu, ou dashboard)
  3. pointer le client :
       ~/.config/mizu/config.json  { "backend_url": "https://$PROJECT_REF.supabase.co",
                                     "publishable_key": "sb_publishable_…" }
     (ou Préférences, ou .env avant build)
EOF
