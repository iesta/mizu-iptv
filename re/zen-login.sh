#!/usr/bin/env bash
# Connexion locale au compte Zen IPTV (Supabase GoTrue).
# Le mot de passe n'est jamais affiché, jamais passé en argument, jamais journalisé.
# Il est envoyé une seule fois en HTTPS à api.zeniptv.app, comme le fait l'app.
# Le jeton est écrit hors du dépôt (~/.config/mizu/session.json, chmod 600).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="https://api.zeniptv.app"
KEY="sb_publishable_FHN4ODlO5E4bt0ezliSoqQ_3CgYEyQs"
SESSION="${MIZU_SESSION:-$HOME/.config/mizu/session.json}"

umask 077
mkdir -p "$(dirname "$SESSION")"

if [[ "${1:-}" == "--whoami" ]]; then
  [[ -f "$SESSION" ]] || { echo "Pas de session. Lance $0 d'abord."; exit 1; }
  TOKEN=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["access_token"])' "$SESSION")
  curl -s -m 20 -H "apikey: $KEY" -H "Authorization: Bearer $TOKEN" "$BASE/auth/v1/user" |
    python3 -c 'import json,sys; d=json.load(sys.stdin); print("id:",d.get("id")); print("email:",d.get("email")); print("providers:",[i.get("provider") for i in d.get("identities") or []])'
  exit 0
fi

read -r -p "Email du compte Zen: " EMAIL
read -r -s -p "Mot de passe (non affiché): " PASSWORD; echo

PAYLOAD=$(python3 -c 'import json,sys;print(json.dumps({"email":sys.argv[1],"password":sys.argv[2]}))' "$EMAIL" "$PASSWORD")
unset PASSWORD

RESP=$(curl -s -m 30 -w '\n%{http_code}' -X POST \
  "$BASE/auth/v1/token?grant_type=password" \
  -H "apikey: $KEY" \
  -H "Content-Type: application/json" \
  --data-binary "$PAYLOAD")

CODE="${RESP##*$'\n'}"
BODY="${RESP%$'\n'*}"

if [[ "$CODE" != "200" ]]; then
  echo "Échec ($CODE): $(echo "$BODY" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); print(d.get("error_description") or d.get("msg") or d.get("message") or d)
except Exception: print(sys.stdin.read()[:200])' 2>/dev/null || echo "$BODY" | head -c 200)"
  exit 1
fi

printf '%s' "$BODY" > "$SESSION"
chmod 600 "$SESSION"

python3 - "$SESSION" <<'PY'
import json,sys,datetime
d=json.load(open(sys.argv[1]))
u=d.get("user") or {}
print("Connecté:", u.get("email"), "| uid:", u.get("id"))
print("access_token expire dans", d.get("expires_in"), "s | refresh_token:", "oui" if d.get("refresh_token") else "non")
PY
echo "Session enregistrée dans $SESSION (lisible par toi seul)."
echo "Vérifier: $0 --whoami"
