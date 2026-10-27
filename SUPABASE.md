# Zen IPTV — structure du backend Supabase et reproduction

**Français** · [English](#english)

Ce document décrit le backend du service **Zen IPTV** tel qu'il a été observé,
puis comment en monter une copie pour Mizu IPTV (ou pour sauvegarder tes
données). Il ne s'agit pas d'une documentation fournie par l'éditeur : tout a
été établi par observation (chaînes du binaire, API publique, données de notre
propre compte).

Fichiers associés :

- [`re/supabase/schema.sql`](re/supabase/schema.sql) — tables, index, RLS, RPC
- [`re/supabase/export-data.py`](re/supabase/export-data.py) — export de tes données
- [`re/supabase/README.md`](re/supabase/README.md) — procédure détaillée
- [`re/PROTOCOL.md`](re/PROTOCOL.md) — protocole complet, y compris Xtream/M3U

---

## 1. Ce qu'est le backend

Zen IPTV n'a pas de backend maison : c'est **Supabase**, utilisé de façon
standard.

| Brique Supabase | Utilisée par Zen ? | Usage |
|---|---|---|
| **GoTrue** (`/auth/v1`) | oui | comptes email/mot de passe, Apple, Google |
| **PostgREST** (`/rest/v1`) | oui | toutes les données (7 tables) |
| **Storage** (`/storage/v1`) | non observé | — |
| **Realtime** (`/realtime/v1`) | **non** | tables absentes de la publication `supabase_realtime` |
| **Edge Functions** (`/functions/v1`) | oui (partiel) | ex. `qr_auth` |

Endpoints relevés dans le binaire de l'app 2.0.4 :

```
https://api.zeniptv.app/auth/v1
https://api.zeniptv.app/rest/v1
https://api.zeniptv.app/realtime/v1
https://api.zeniptv.app/storage/v1
https://api.zeniptv.app/functions/v1
```

L'authentification accepte : **email/mot de passe**, **Apple**, **Google**
(pas d'accès anonyme).

---

## 2. Modèle de données

Sept tables dans le schéma `public`. Deux règles structurantes :

1. **Tout est rattaché à un profil de visionnage**, pas directement au compte
   (sauf les sources et les préférences).
2. **`content_id` est un identifiant TMDB** pour les films et séries, et le
   **nom de la chaîne** pour le direct — pas l'identifiant du fournisseur IPTV.

### `watch_profiles` — profils

| Colonne | Type | Notes |
|---|---|---|
| `id` | uuid (PK) | |
| `user_id` | uuid | propriétaire |
| `name` | text | « Harry », « jm »… |
| `color` | int8 | ARGB 32 bits |

### `user_preferences` — préférences du compte (1 ligne par utilisateur)

| Colonne | Type |
|---|---|
| `user_id` | uuid (PK) |
| `show_ended_movies` | bool |
| `playlist_refresh_rate_days` | int |
| `ms_prot_other_apps` | bool |

### `playlist_sources` — sources Xtream / M3U

| Colonne | Type | Notes |
|---|---|---|
| `id` | uuid (PK) | |
| `user_id` | uuid | |
| `name` | text | nom affiché |
| `runtimeType` | text | **camelCase** : `xtream` ou `m3u` |
| `host` | text | Xtream : `http://serveur:port` |
| `url` | text | M3U : URL de la playlist |
| `username`, `password` | text | Xtream — **en clair** |
| `epg_url` | text | optionnel |
| `color` | int8 | ARGB |
| `group_channels_categories` | bool | |

### `favorites` — liste « Ma liste », par profil

| Colonne | Type | Notes |
|---|---|---|
| `watch_profile_id` | uuid | PK composite |
| `content_id` | text | **id TMDB** (film/série) ou **nom de chaîne** |
| `content_type` | text | `channel` \| `vod` \| `serie` |
| `sort_order` | int | ordre manuel |
| `added_at` | timestamptz | |

### `serie_progress` — reprise de lecture

| Colonne | Type | Notes |
|---|---|---|
| `watch_profile_id` | uuid | PK composite |
| `serie_id` | text | id TMDB (ou slug) |
| `season_number`, `episode_number` | int | |
| `watch_time` | int | secondes |
| `watch_progress` | float8 | 0 → 1 |
| `last_watched` | timestamptz | |
| `all_episodes_watched` | bool | |
| `runtimeType` | text | `serie` (ou `vod` pour un film) |
| `version_id` | int8 | regroupement de versions (SD/HD/FHD) |

### `masked_categories` — catégories masquées par profil

| Colonne | Type |
|---|---|
| `watch_profile_id` | uuid (PK composite) |
| `category_id` | text |
| `category_type` | text |
| `source_id` | uuid |

### `tmdb_mappings` — remappage TMDB manuel

| Colonne | Type |
|---|---|
| `source_id` | uuid |
| `content_type` | text |
| `mapped_tmdb_id` | text |

### Fonction SQL

```sql
favorites_apply_order(
  p_content_ids      text[],
  p_content_type     text,
  p_watch_profile_id uuid
)
```

Réordonne les favoris d'un profil selon l'ordre du tableau. Signature obtenue
depuis l'erreur PostgREST de l'instance d'origine (`favorites_reorder`, présent
dans le binaire, n'existe pas).

### Sécurité

Le serveur applique **RLS** : chaque utilisateur ne lit que ses lignes (les
requêtes non authentifiées renvoient `[]`, pas d'erreur). Les politiques de
`schema.sql` reproduisent cette intention : propriétaire direct
(`user_id = auth.uid()`), ou rattachement via le profil / la source.

### Ce qui est incertain

| Élément | Statut |
|---|---|
| Colonnes, types | **observés** sur l'instance réelle |
| Clé unique `serie_progress (watch_profile_id, serie_id)` | **prouvée** (un `upsert onConflict` a été accepté) |
| Autres clés primaires | supposées, cohérentes avec les colonnes |
| Politiques RLS exactes | non inspectables → réécrites à l'identique en intention |
| Triggers, index, buckets Storage | inconnus, non utilisés par Mizu |

---

## 3. Reproduire cette base

### 3.1 Créer le projet

1. <https://supabase.com> → *New project* (ou instance auto-hébergée).
2. Note l'**URL du projet** (`https://xxxx.supabase.co`) et la **clé
   publishable** (*Project Settings → API*).

### 3.2 Créer le schéma

Deux méthodes, au choix.

**CLI Supabase (recommandé)** — le script fait tout : connexion, migration
générée depuis `schema.sql`, `supabase db push`.

```bash
# une fois : authentification (Personal Access Token ou navigateur)
supabase login            # ou : export SUPABASE_ACCESS_TOKEN=sbp_…

# puis, depuis le dépôt
re/supabase/setup.sh --project-ref abcdefghijklmnopqrst
# options : --password '…'  (mot de passe de la base)
#           --seed          (importe tes données ensuite)
#           --dry-run       (montre la migration sans l'appliquer)
#           --db-url '…'    (connexion directe au lieu du project-ref)
```

Le script utilise la CLI installée, sinon `npx supabase`. Il génère
`re/supabase/cli/supabase/migrations/<horodatage>_zen_init.sql` à partir de
[`schema.sql`](re/supabase/schema.sql) — source unique, donc pas de dérive.

**SQL Editor** — coller le contenu de
[`re/supabase/schema.sql`](re/supabase/schema.sql) puis exécuter.

Dans les deux cas, le schéma créé comprend : les 7 tables, les index, les
politiques RLS, la fonction `favorites_apply_order` et un trigger qui initialise
`user_preferences` à l'inscription. Il est **idempotent** : on peut le rejouer.

### 3.3 Authentification

*Authentication → Providers* : activer **Email**. Apple/Google sont possibles
avec **tes** identifiants OAuth (ceux de Zen ne fonctionneront pas).

### 3.4 Créer ton utilisateur

Via l'écran d'inscription de Mizu, ou *Authentication → Users → Add user*.

### 3.5 Importer tes données

```bash
cd re/supabase

# Sans les mots de passe des sources (recommandé)
python3 export-data.py --out seed.sql

# Avec les identifiants Xtream (fichier sensible)
python3 export-data.py --out seed.sql --with-credentials
```

Puis exécuter `seed.sql` dans le SQL Editor. Les UUID des profils et des
sources sont conservés : favoris, progression et catégories masquées restent
rattachés aux bons profils.

### 3.6 Pointer le client

Voir la section suivante.

---

## 4. La méthode `.env`

Le client ne contient **aucune clé**. Sa configuration vient, par ordre de
priorité :

1. **variables d'environnement** (`MIZU_BACKEND_URL`, `MIZU_PUBLISHABLE_KEY`,
   `MIZU_TMDB_KEY`) ;
2. **`config.json`** écrit par l'écran *Préférences* ;
3. **valeurs compilées depuis `.env`** (`--dart-define-from-file`) ;
4. **fichier `.env`** lu à l'exécution (répertoire courant,
   `~/.config/mizu/.env`, ou à côté de l'exécutable).

### Exemple : l'instance Zen

C'est exactement ce qui est utilisé pour parler au service d'origine :

```bash
# .env à la racine du dépôt — jamais commité
MIZU_BACKEND_URL=https://api.zeniptv.app
MIZU_PUBLISHABLE_KEY=sb_publishable_FHN4ODlO5E4bt0ezliSoqQ_3CgYEyQs
MIZU_TMDB_KEY=
```

- `MIZU_BACKEND_URL` : racine Supabase. Le client en déduit `/auth/v1` et
  `/rest/v1`.
- `MIZU_PUBLISHABLE_KEY` : clé *publishable* (publique par conception, livrée
  dans tous les clients Zen). Ce n'est pas un secret, mais c'est leur
  identifiant d'accès : elle n'accorde que ce que la RLS autorise.
- `MIZU_TMDB_KEY` : optionnelle, améliore titres/affiches (voir plus bas).

Compiler avec ces valeurs les **embarque** dans le binaire :

```bash
./tools/build.sh linux     # ou apk / apk-debug / macos
# équivaut à : flutter build … --dart-define-from-file=../.env
```

Résultat : l'application est configurée dès l'installation, sans écran de
configuration. C'est ce qui est fait pour l'APK Android.

### Exemple : ta propre instance

Après l'étape 3, remplace simplement les deux valeurs :

```bash
MIZU_BACKEND_URL=https://ton-projet.supabase.co
MIZU_PUBLISHABLE_KEY=sb_publishable_…
```

Puis `./tools/build.sh …`, ou plus simple : saisis-les dans **Préférences**
(roue dentée) — un redémarrage est demandé, car `Supabase.initialize` a lieu au
démarrage.

### Équivalent `config.json`

```json
{
  "backend_url": "https://ton-projet.supabase.co",
  "publishable_key": "sb_publishable_…",
  "tmdb_api_key": "…",
  "user_agent": "MizuIPTV/1.0 (Flutter)"
}
```

Emplacement : `~/.config/mizu/config.json` sur Linux,
`~/Library/Application Support/app.mizu.iptv/config.json` sur macOS, dossier
applicatif sur Android. Permissions `600`.

### User-Agent

`user_agent` (ou `MIZU_USER_AGENT`) s'applique à toutes les requêtes vers les
panneaux IPTV — API Xtream, playlists M3U **et** flux vidéo. Utile quand un
fournisseur filtre les User-Agent inconnus.

---

## 5. Limites

- **L'app Zen officielle ne peut pas être redirigée** : son URL et sa clé sont
  compilées dans son binaire. Cette reproduction sert à **Mizu** et à la
  sauvegarde de tes données.
- **Pas de Realtime** : les tables ne sont pas dans la publication
  `supabase_realtime` de l'instance d'origine. Mizu compense par un polling de
  45 s. Si tu montes ta propre base, tu peux activer Realtime (ligne commentée
  en fin de `schema.sql`).
- **Edge Functions et Storage** ne sont pas reproduits : non nécessaires au
  client (`qr_auth`, paywall et achats sont propriétaires).
- **Mots de passe Xtream en clair** : c'est le choix de Zen, conservé dans le
  schéma. Ta base, ta responsabilité.

## 6. Légal

Ce travail porte sur **ton** compte : l'analyse et l'export sont en lecture
seule sur l'instance d'origine. Ne redistribue ni les données, ni le schéma
comme s'il s'agissait d'un document officiel. Aucun contournement d'achat
(Zen Access) n'est proposé : Mizu réutilise l'abonnement existant du compte.

---

# English

**English** · [Français](#zen-iptv--structure-du-backend-supabase-et-reproduction)

This document describes the **Zen IPTV** backend as observed, then how to build
a copy of it for Mizu IPTV (or to back up your data). It is not vendor
documentation: everything was established by observation (binary strings,
public API, our own account's data).

Related files: [`re/supabase/schema.sql`](re/supabase/schema.sql),
[`re/supabase/export-data.py`](re/supabase/export-data.py),
[`re/supabase/README.md`](re/supabase/README.md),
[`re/PROTOCOL.md`](re/PROTOCOL.md).

## 1. What the backend is

Zen IPTV runs on **Supabase**, used the standard way.

| Supabase part | Used by Zen? | Purpose |
|---|---|---|
| **GoTrue** (`/auth/v1`) | yes | email/password, Apple, Google sign-in |
| **PostgREST** (`/rest/v1`) | yes | all data (7 tables) |
| **Storage** (`/storage/v1`) | not observed | — |
| **Realtime** (`/realtime/v1`) | **no** | tables absent from the `supabase_realtime` publication |
| **Edge Functions** (`/functions/v1`) | partially | e.g. `qr_auth` |

Endpoints found in the 2.0.4 binary:

```
https://api.zeniptv.app/auth/v1
https://api.zeniptv.app/rest/v1
https://api.zeniptv.app/realtime/v1
https://api.zeniptv.app/storage/v1
https://api.zeniptv.app/functions/v1
```

Sign-in methods: **email/password**, **Apple**, **Google** (no anonymous).

## 2. Data model

Seven tables in the `public` schema. Two structural rules:

1. **Everything hangs off a watch profile**, not the account directly (except
   sources and preferences).
2. **`content_id` is a TMDB id** for movies and series, and the **channel name**
   for live TV — not the IPTV provider's id.

| Table | Key columns |
|---|---|
| `watch_profiles` | `id` (PK), `user_id`, `name`, `color` |
| `user_preferences` | `user_id` (PK), `show_ended_movies`, `playlist_refresh_rate_days`, `ms_prot_other_apps` |
| `playlist_sources` | `id` (PK), `user_id`, `name`, `runtimeType` (`xtream`/`m3u`), `host`, `url`, `username`, `password`, `epg_url`, `color`, `group_channels_categories` |
| `favorites` | `watch_profile_id` + `content_id` + `content_type` (PK), `sort_order`, `added_at` |
| `serie_progress` | `watch_profile_id` + `serie_id` (PK), `season_number`, `episode_number`, `watch_time`, `watch_progress`, `last_watched`, `all_episodes_watched`, `runtimeType`, `version_id` |
| `masked_categories` | `watch_profile_id` + `category_id` + `category_type` (PK), `source_id` |
| `tmdb_mappings` | `source_id`, `content_type`, `mapped_tmdb_id` |

SQL function (signature taken from the origin server's PostgREST error):

```sql
favorites_apply_order(p_content_ids text[], p_content_type text,
                      p_watch_profile_id uuid)
```

Security is enforced by **RLS**: unauthenticated reads return `[]`, never an
error. `schema.sql` reproduces the intent (row owner, or ownership through the
profile / source).

**What is certain vs inferred:** columns and types are observed; the unique key
`serie_progress (watch_profile_id, serie_id)` is proven (an `upsert
onConflict` was accepted); other primary keys, RLS policies, triggers, indexes
and Storage buckets are reconstructed or unknown.

## 3. Reproducing the database

1. Create a project on <https://supabase.com> (or self-host). Note the project
   **URL** and **publishable key** (*Project Settings → API*).
2. Create the schema, either way:

   **Supabase CLI (recommended)**

   ```bash
   supabase login          # or: export SUPABASE_ACCESS_TOKEN=sbp_…
   re/supabase/setup.sh --project-ref abcdefghijklmnopqrst
   # options: --password '…' (database password), --seed (import your data),
   #          --dry-run (show the migration), --db-url '…' (direct connection)
   ```

   The script uses the installed CLI, otherwise `npx supabase`. It generates a
   migration from [`schema.sql`](re/supabase/schema.sql) (single source, no
   drift), then runs `supabase db push`.

   **SQL Editor** — paste [`re/supabase/schema.sql`](re/supabase/schema.sql)
   and run it.

   The schema is **idempotent**: it can be replayed.
3. *Authentication → Providers*: enable **Email** (Apple/Google with **your**
   OAuth credentials).
4. Create your user (Mizu's sign-up screen, or *Authentication → Users*).
5. Import your data:

   ```bash
   cd re/supabase
   python3 export-data.py --out seed.sql                    # credentials stripped
   python3 export-data.py --out seed.sql --with-credentials # sensitive file
   ```

   Then run `seed.sql`. Profile and source UUIDs are preserved, so favourites
   and progress stay attached to the right profiles.
6. Point the client (next section).

## 4. The `.env` method

The client ships **no keys**. Configuration is resolved in this order:

1. **environment variables** (`MIZU_BACKEND_URL`, `MIZU_PUBLISHABLE_KEY`,
   `MIZU_TMDB_KEY`);
2. **`config.json`** written by the *Preferences* screen;
3. **compile-time values from `.env`** (`--dart-define-from-file`);
4. **runtime `.env` file** (current directory, `~/.config/mizu/.env`, or next to
   the executable).

### Example: the Zen instance

```bash
# .env at the repository root — never committed
MIZU_BACKEND_URL=https://api.zeniptv.app
MIZU_PUBLISHABLE_KEY=sb_publishable_FHN4ODlO5E4bt0ezliSoqQ_3CgYEyQs
MIZU_TMDB_KEY=
```

Building with these values **embeds** them:

```bash
./tools/build.sh linux     # or apk / apk-debug / macos
# equivalent to: flutter build … --dart-define-from-file=../.env
```

The app is then configured on first launch, with no setup screen — this is how
the Android APK is produced.

### Example: your own instance

```bash
MIZU_BACKEND_URL=https://your-project.supabase.co
MIZU_PUBLISHABLE_KEY=sb_publishable_…
```

Rebuild, or simply enter both values in **Preferences** (a restart is required,
since `Supabase.initialize` runs at startup).

`config.json` equivalent:

```json
{
  "backend_url": "https://your-project.supabase.co",
  "publishable_key": "sb_publishable_…",
  "tmdb_api_key": "…",
  "user_agent": "MizuIPTV/1.0 (Flutter)"
}
```

Location: `~/.config/mizu/config.json` on Linux,
`~/Library/Application Support/app.mizu.iptv/config.json` on macOS, the app
support directory on Android. Mode `600`.

## 5. Limitations

- **The official Zen app cannot be redirected**: its URL and key are compiled
  into the binary. This reproduction serves **Mizu** and your data backup.
- **No Realtime**: the tables are not in the origin instance's
  `supabase_realtime` publication; Mizu falls back to 45 s polling. On your own
  project you may enable it (commented line at the end of `schema.sql`).
- **Edge Functions and Storage** are not reproduced (not needed by the client).
- **Xtream passwords are stored in clear text** — Zen's design, kept in the
  schema. Your database, your responsibility.

## 6. Legal

This work covers **your** account: analysis and export are read-only on the
origin instance. Do not redistribute the data or the schema as if it were
vendor documentation. No purchase bypass (Zen Access) is provided: Mizu reuses
the account's existing subscription.
