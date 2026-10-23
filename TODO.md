# TODO — Mizu IPTV

## En cours / priorité

- [ ] **macOS** : compiler et valider sur un Mac (procédure dans
      [`AGENTS.md`](AGENTS.md#première-tâche-sur-un-mac)).
- [ ] **Direct** : masquer la barre de progression/seek quand
      `contentType == 'channel'` (mpv annonce parfois une durée bidon).
- [ ] **Focus TV** : liseré de focus sur les lignes de chaînes (aujourd'hui un
      simple `focusColor`, trop discret à 3 m).
- [ ] **APK release** : keystore + `flutter build apk --split-per-abi`
      (199 Mo → ~40 Mo par architecture).
- [ ] Vérifier que les films lancés ici produisent une ligne `vod` lisible par
      l'app Zen (`serie_progress.runtimeType = 'vod'`) — non confirmé.

## Avant publication du dépôt

- [ ] Trancher le sort de la **clé publishable** par défaut (la garder avec une
      note, ou demander la clé au premier lancement).
- [ ] Créer le remote (`gh repo create`, **privé d'abord**), puis passer public.
- [ ] Refaire les captures d'écran sur un **compte de démo** : celles existantes
      exposent les profils, sources et favoris réels.

## webOS (LG) — mis de côté le 2026-10-23

**Verdict technique** : faisable, mais c'est un **client web séparé**, pas un
portage Flutter. Les apps LG webOS sont du HTML/CSS/JS empaqueté en `.ipk` avec
`ares-cli` (Node.js, utilisable depuis Linux). Il n'existe pas de moteur Flutter
natif sur webOS ; un `flutter build web` embarqué serait lourd et fragile.

**Le point bloquant est la vidéo, pas le langage :**

| Format | `<video>` webOS |
|---|---|
| HLS `.m3u8` (H.264/AAC) | ✅ natif |
| MP4 (H.264) | ✅ |
| MPEG-TS (`.ts`, défaut Xtream) | ❌ |
| MKV / HEVC | ⚠️ selon le millésime |

La plupart des panneaux Xtream servent du **MPEG-TS** en direct, d'où le besoin
de HLS côté fournisseur (pas de transcodage ffmpeg sur une TV).

**Test qui tranche (2 requêtes)** :

```bash
# avec les identifiants d'une source et un stream_id de chaîne
curl -sI "http://<host>/live/<user>/<pass>/<stream_id>.m3u8"   # attendu : application/vnd.apple.mpegurl
curl -sI "http://<host>/live/<user>/<pass>/<stream_id>.ts"     # comparaison
curl -s  "http://<host>/get.php?username=<u>&password=<p>&type=m3u_plus&output=hls" | head
```

**Statut au 2026-10-23** : test **impossible**, le panneau `pelicanDaddy`
répond `HTTP 461` (ban temporaire après une journée de requêtes intensives).
À retenter plus tard, ou à tester depuis le **navigateur de la TV** (même moteur
que l'app webOS).

**Si le HLS passe, plan de reprise** :

1. `webos/` dans ce dépôt : `appinfo.json` (id `com.mizu.iptv`, 1920×1080),
   `ares-package`, `ares-install`.
2. `supabase-js` (auth + tables déjà documentées dans `re/PROTOCOL.md`), mêmes
   règles : `content_id` TMDB, favoris par profil, `serie_progress`.
3. UI 10-foot en colonnes (TV / Films / Séries) + navigation D-pad
   (flèches, Enter, Back = keycode 461).
4. `<video>` + HLS natif, pas de hls.js sauf besoin.
5. MVP estimé : ~1 semaine (login, sources, favoris, reprise, live HLS, VOD MP4).

**Distribution** : Developer Mode LG (compte dev, session de 50 h renouvelable,
`ares-install` sur le port 9922/3000) pour tester ; LG Content Store = compte
partenaire + revue, hors scope. Le SDK webOS TV inclut un **simulateur Linux**
pour itérer sur l'UI sans la TV.

## Rappels

- Un panneau Xtream renvoie `461` quand on l'interroge trop vite ou trop
  souvent : une requête à la fois, espacées ; ne pas paralléliser les tests.
- Realtime n'est pas publié côté Zen → polling 45 s (déjà en place).
