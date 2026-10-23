# Zen IPTV — carte du protocole (analyse statique + sondage passif)

> Document d'ingénierie inverse réalisé pour **Mizu IPTV**, client libre
> (licence MIT) du service Zen IPTV. Il décrit un service tiers par
> observation : chaînes du binaire, endpoints publics et données du compte de
> l'auteur. Voir l'avertissement du [README](../README.md).

Cible : `zeniptv.app` — *Zen IPTV*, éditeur Mayutoni, `app.zeniptv.mobile`, version 2.0.4 (build 141).
Artefact analysé : `zeniptv.app` (bundle macOS fourni), universal x86_64 + arm64.

## 1. Nature de l'app

**Flutter** (Dart AOT), pas du Swift natif :

| Élément | Détail |
|---|---|
| Runner | `Contents/MacOS/Zen IPTV` (Mach-O universal, 104 Mo) |
| Code applicatif | `Contents/Frameworks/App.framework/Versions/A/App` (Dart AOT, 22 Mo, universal) |
| Assets | `flutter_assets` (Rive, shaders, polices) |
| Plugins notables | `supabase_flutter` 2.12.0 / `supabase-dart` 2.10.2, `drift` (SQLite local), `video_player_avfoundation`, `KSPlayer`, `FFmpegKit`, `RevenueCat` (achats), `sign_in_with_apple`, `flutter_appauth`, `app_links`, `iptv_loader` (plugin maison, `flutter_rust_bridge`) |
| État | Riverpod (providers `favoritesRepositoryProvider`, `activeProfileProvider`, …) |

Conséquence : il n'y a **pas** de logique Swift à décompiler. Le « métier » (sync, sources,
favoris, progression) est dans le snapshot Dart AOT — noms de classes/fonctions et littéraux
de chaînes restent lisibles, donc la surface utile s'obtient par extraction de chaînes +
confirmation réseau, sans passer par Ghidra.

## 2. Backend = Supabase

Littéraux trouvés dans le binaire :

```
https://api.zeniptv.app
https://api.zeniptv.app/auth/v1        (GoTrue)
https://api.zeniptv.app/rest/v1        (PostgREST)
https://api.zeniptv.app/realtime/v1    (Realtime / postgres_changes)
https://api.zeniptv.app/storage/v1
https://api.zeniptv.app/functions/v1   (Edge Functions, ex. `qr_auth`)
clé publishable : sb_publishable_FHN4ODlO5E4bt0ezliSoqQ_3CgYEyQs
```

Autres services tiers : `api.themoviedb.org/3` + `image.tmdb.org` (métadonnées),
`api.revenuecat.com` (achats Zen Access), `api.opensubtitles.com` (sous-titres),
`zeniptv.app/releases/app_versions.json` (mise à jour), `zeniptv.app/api/paywall`.

Auth (`GET /auth/v1/settings`, public) : email/mot de passe, Apple, Google ; pas d'anonyme.

## 3. Schéma de synchro (vérifié sur le serveur **et sur un compte réel**)

Tables `public` confirmées par sondage REST non authentifié (RLS renvoie 0 ligne, pas de
donnée d'autrui lue) : `200 []` = table existante, `42P01` = inexistante.

| Table | Colonnes confirmées | Rôle |
|---|---|---|
| `favorites` | `watch_profile_id`, `content_id`, `content_type`, `sort_order`, `added_at` | Ma liste / favoris, ordonnés par profil |
| `watch_profiles` | `id`, `user_id`, `name`, `color` (ARGB int) | Profils de visionnage (Zen Access) |
| `serie_progress` | `watch_profile_id`, `serie_id`, `season_number`, `episode_number`, `watch_time` (s), `watch_progress` (0..1), `version_id`, `runtimeType`, `last_watched`, `all_episodes_watched` | Reprise de lecture |
| `playlist_sources` | `id`, `user_id`, `name`, `runtimeType` (`xtream`/`m3u`), `host` (xtream), `url` (m3u), `username`, `password`, `epg_url`, `color`, `group_channels_categories` | Sources synchronisées, **identifiants compris** |
| `masked_categories` | `watch_profile_id`, `category_id`, `category_type`, `source_id` | Catégories masquées par profil |
| `user_preferences` | `user_id`, `show_ended_movies`, `playlist_refresh_rate_days`, `ms_prot_other_apps` | Préférences |
| `tmdb_mappings` | `content_type`, `mapped_tmdb_id`, `source_id` | Remappage manuel TMDB |

Sémantique observée sur les lignes réelles :

- `favorites.content_type` ∈ {`channel`, `vod`, `serie`}.
- `favorites.content_id` et `serie_progress.serie_id` sont des **identifiants TMDB**
  pour `vod`/`serie` (vérifié : 597 → Titanic, 1368 → Rambo, 1398 → Les Soprano),
  et le **nom de la chaîne** pour `channel` (les ids de chaînes varient d'une
  source à l'autre). C'est ce qui explique l'absence de `source_id` dans
  `favorites` et l'existence de `tmdb_mappings` (remap manuel source → TMDB).
- `serie_progress.serie_id` : id fournisseur (numérique). `version_id` = id de la « version »
  regroupée (SD/HD/FHD…) ; `watch_progress` = fraction vue de l'épisode.
- Table `serie_progress` = progression générique : la colonne `runtimeType` existe, donc elle
  porte probablement aussi les films (`vod`). À confirmer en regardant une ligne apparaître
  après lecture d'un film (aucune ligne `vod` sur le compte de test au moment de l'analyse).
- `playlist_sources` stocke **les identifiants du fournisseur en clair** (colonne `password`) :
  la sécurité repose entièrement sur la RLS du serveur.

RPC : **`favorites_apply_order(p_content_ids, p_content_type, p_watch_profile_id)`**
— signature exacte obtenue via l'erreur PostgREST de l'instance d'origine.
`favorites_reorder` n'existe pas (simple littéral obsolète dans le binaire :
PostgREST suggère `favorites_apply_order`).

Reproduction complète du schéma : [`re/supabase/`](supabase/) (SQL + export de
données + procédure).

Clés/colonnes visibles dans le binaire et cohérentes avec ce modèle :
`preferred_watch_profile_id`, `preferred_audio_language`, `preferred_subtitle_language`,
`preferred_audio_track_id`, `preferred_subtitles_track_id`, `active_source_id`,
`last_watched`, `watch_time`, `all_episodes_watched`, `sort_order`, `category_type`,
`epg_url`, `user_agent`, `buffer_duration_seconds`, `max_buffer_duration_seconds`.

Temps réel : `postgres_changes` (progression/favoris poussés entre appareils).

## 4. Ce qu'un client Linux doit faire pour « se sync à mon compte »

1. `POST /auth/v1/token?grant_type=password` avec la publishable key → `access_token` +
   `refresh_token` (rotation via `grant_type=refresh_token`).
2. `GET /rest/v1/watch_profiles?user_id=eq.<uid>` → profils ; préférence de profil actif
   dans `user_preferences`.
3. `GET /rest/v1/playlist_sources?user_id=eq.<uid>` → sources Xtream/M3U (URL + identifiants).
   Charger les flux via l'API Xtream standard (`player_api.php`) ou le M3U.
4. `GET/POST/DELETE /rest/v1/favorites` (+ RPC de réordonnancement), `serie_progress`
   (upsert sur reprise), `masked_categories`, `tmdb_mappings`, `user_preferences`.
5. Optionnel : souscription Realtime sur ces tables pour la synchro instantanée.
6. Métadonnées : TMDB (clé de l'app à extraire si besoin) ; images `image.tmdb.org`.

## 5. Limites assumées

- Aucun contournement d'achat (RevenueCat / Zen Access) : le client Linux réutilise le
  compte et l'abonnement existants, ou se limite aux fonctions gratuites.
- Interopérabilité sur **ton** compte uniquement ; pas de redistribution d'assets ni du code
  de l'app (UI à réécrire).
- Le sondage n'a utilisé que des endpoints publics avec la clé publishable livrée dans
  l'app ; aucune donnée d'un autre utilisateur n'a été lue (RLS).

## 6. État des sources du compte de test (2026-10-23)

| Source | Type | État |
|---|---|---|
| main (`prem.platiniums.xyz`) | Xtream | HTTP 461 (bloquée/expirée) |
| iptv25 (`arox.tv`) | Xtream | expirée (2025-11-02) |
| pelicanDaddy (`fhd.iptvxvod.com:2103`) | Xtream | HTTP 461 |
| iptvxvodtan (`arox.tv`) | Xtream | expirée (2026-08-27) |
| TanIPTV (`fhd.iptvxvod.fr`) | Xtream | expirée (2026-08-27) |
| All (`iptv-org.github.io/iptv/index.m3u`) | M3U | OK — 11 302 chaînes |
| IPTV Tan | M3U | cassée : pointe vers un lien `keep.google.com` |

Le HTTP 461 est renvoyé par le panneau avant même `player_api.php` : à traiter
comme « compte bloqué ou expiré », pas comme une erreur de ce client.

## 7. Temps réel : non disponible

`postgres_changes` est absent de la publication `supabase_realtime` : les cinq
tables testées (`favorites`, `serie_progress`, `watch_profiles`,
`playlist_sources`, `user_preferences`) répondent
`Unable to subscribe to changes with given parameters. Please check Realtime is
enabled…`. L'app d'origine ne peut donc pas pousser la progression en direct :
le client Linux complète par un **polling de 45 s** (et rafraîchit au focus).

## 8. Écriture validée

Le 2026-10-23, le client Linux a lu l'épisode S1E1 de *Yaga* depuis la source
`pelicanDaddy` (Xtream) et écrit dans `serie_progress` :

```json
{"watch_profile_id":"51b24288-…","serie_id":"314360","season_number":1,
 "episode_number":1,"watch_time":88,"watch_progress":0.048754,
 "runtimeType":"serie","version_id":null,"all_episodes_watched":false,
 "last_watched":"2026-10-23T14:23:24Z"}
```

Donc : `serie_id` = id TMDB de la série (314360 = Yaga), `watch_time` en
secondes, `watch_progress` = fraction vue. `version_id` reste `null` (le client
Linux ne gère pas encore le regroupement de versions).

## 8 bis. Ce qui reste à confirmer

1. Progression des **films** : la table `serie_progress` ne contenait que des
   lignes `runtimeType = serie`. Regarder 30 s d'un film dans l'app d'origine,
   puis vérifier si une ligne `vod` apparaît (même table) ou non.
2. ~~Signature des RPC~~ → résolu : `favorites_apply_order(p_content_ids,
   p_content_type, p_watch_profile_id)`. Reste à valider le type exact de
   `p_content_ids` (`text[]` retenu dans la reproduction).
3. Rôle de `version_id` dans `serie_progress` (regroupement de versions
   SD/HD/FHD d'un même contenu).
