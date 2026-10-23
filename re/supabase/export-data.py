#!/usr/bin/env python3
"""Exporte les données d'un compte Zen (lecture seule) vers un script SQL.

Sortie : inserts prêts à exécuter sur *ton* projet Supabase, après
`schema.sql`. Les UUID des profils et des sources sont conservés, donc les
favoris/progressions restent cohérents.

Le jeton de session est lu par défaut dans le stockage de l'app Linux
(`~/.local/share/dev.jm.zen_player/shared_preferences.json`), sinon dans
`re/.session.json`.

Usage :
    python3 export-data.py --out seed.sql
    python3 export-data.py --out seed.sql --with-credentials

Sans `--with-credentials`, les mots de passe des sources sont remplacés par
une chaîne vide (à ressaisir dans l'app).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.request

API = "https://api.zeniptv.app"
KEY = "sb_publishable_FHN4ODlO5E4bt0ezliSoqQ_3CgYEyQs"

TABLES = [
    "watch_profiles",
    "user_preferences",
    "playlist_sources",
    "favorites",
    "serie_progress",
    "masked_categories",
    "tmdb_mappings",
]


def load_token() -> tuple[str, str]:
    """Retourne (access_token, email)."""
    candidates = [
        os.environ.get("MIZU_SESSION"),
        os.path.expanduser("~/.config/mizu/session.json"),
        os.path.expanduser(
            "~/.local/share/app.mizu.iptv/shared_preferences.json"
        ),
    ]
    for path in candidates:
        if not path or not os.path.exists(path):
            continue
        try:
            data = json.load(open(path))
            if "flutter.sb-api-auth-token" in data:
                data = json.loads(data["flutter.sb-api-auth-token"])
            if data.get("access_token"):
                return data["access_token"], data["user"]["email"]
        except (KeyError, ValueError):
            continue
    sys.exit(
        "Aucune session trouvée. Lance l'app et connecte-toi, "
        "ou exécute re/zen-login.sh."
    )


def fetch(table: str, token: str) -> list[dict]:
    url = f"{API}/rest/v1/{table}?select=*"
    req = urllib.request.Request(
        url, headers={"apikey": KEY, "Authorization": f"Bearer {token}"}
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        rows = json.load(r)
    return rows if isinstance(rows, list) else []


def q(value) -> str:
    """Littéral SQL."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def insert(table: str, row: dict, columns: list[str]) -> str:
    cols = ", ".join(f'"{c}"' for c in columns)
    vals = ", ".join(q(row.get(c)) for c in columns)
    return f'insert into public.{table} ({cols}) values ({vals}) on conflict do nothing;'


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="seed.sql")
    ap.add_argument("--with-credentials", action="store_true")
    args = ap.parse_args()

    token, email = load_token()
    print(f"compte : {email}")

    data = {t: fetch(t, token) for t in TABLES}
    for t, rows in data.items():
        print(f"  {t}: {len(rows)} ligne(s)")

    lines = [
        "-- Données exportées depuis le compte Zen (usage personnel).",
        f"-- Propriétaire : {email}",
        "begin;",
        "",
        "-- L'utilisateur doit exister dans auth.users.",
        f"-- (select id from auth.users where email = {q(email)})",
        "",
    ]

    uid_expr = f"(select id from auth.users where email = {q(email)})"

    for row in data["watch_profiles"]:
        row = dict(row)
        row["user_id"] = None
        cols = ["id", "name", "color"]
        cols_sql = ", ".join(f'"{c}"' for c in cols)
        vals = ", ".join([q(row.get("id")), q(row.get("name")), q(row.get("color"))])
        lines.append(
            f"insert into public.watch_profiles ({cols_sql}, user_id) "
            f"values ({vals}, {uid_expr}) on conflict (id) do nothing;"
        )

    for row in data["user_preferences"]:
        cols = [c for c in ("show_ended_movies", "playlist_refresh_rate_days",
                            "ms_prot_other_apps") if c in row]
        cols_sql = ", ".join(f'"{c}"' for c in cols)
        vals = ", ".join(q(row.get(c)) for c in cols)
        lines.append(
            f"insert into public.user_preferences (user_id{', ' if cols else ''}{cols_sql}) "
            f"values ({uid_expr}{', ' if cols else ''}{vals}) "
            f"on conflict (user_id) do nothing;"
        )

    for row in data["playlist_sources"]:
        row = dict(row)
        if not args.with_credentials:
            row["password"] = ""
        cols = ["id", "name", "runtimeType", "host", "url", "username",
                "password", "epg_url", "color", "group_channels_categories"]
        cols_sql = ", ".join(f'"{c}"' for c in cols)
        vals = ", ".join(q(row.get(c)) for c in cols)
        lines.append(
            f"insert into public.playlist_sources ({cols_sql}, user_id) "
            f"values ({vals}, {uid_expr}) on conflict (id) do nothing;"
        )

    for row in data["favorites"]:
        lines.append(insert("favorites", row,
                            ["watch_profile_id", "content_id", "content_type",
                             "sort_order", "added_at"]))

    for row in data["serie_progress"]:
        lines.append(insert("serie_progress", row,
                            ["watch_profile_id", "serie_id", "season_number",
                             "episode_number", "watch_time", "watch_progress",
                             "last_watched", "all_episodes_watched",
                             "runtimeType", "version_id"]))

    for row in data["masked_categories"]:
        lines.append(insert("masked_categories", row,
                            ["watch_profile_id", "category_id", "category_type",
                             "source_id"]))

    for row in data["tmdb_mappings"]:
        lines.append(insert("tmdb_mappings", row,
                            ["source_id", "content_type", "mapped_tmdb_id"]))

    lines += ["", "commit;", ""]
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"écrit : {args.out}")
    if not args.with_credentials:
        print("mots de passe des sources vidés (relance avec --with-credentials "
              "pour les inclure, le fichier contiendra alors des secrets)")


if __name__ == "__main__":
    main()
