# TODO — Mizu IPTV

## En cours / priorité

- [ ] **macOS** : compiler et valider sur un Mac (procédure dans
      [`AGENTS.md`](AGENTS.md#première-tâche-sur-un-mac)).
- [x] ~~Direct : barre de progression~~ → masquée pour `channel`
      (commit `9aa98be`).
- [ ] **Focus TV** : liseré de focus sur les lignes de chaînes (aujourd'hui un
      simple `focusColor`, trop discret à 3 m).
- [ ] **APK release** : keystore + `flutter build apk --split-per-abi`
      (199 Mo → ~40 Mo par architecture).
- [ ] Vérifier que les films lancés ici produisent une ligne `vod` lisible par
      l'app Zen (`serie_progress.runtimeType = 'vod'`) — non confirmé.

## Avant publication du dépôt

- [x] ~~Clé publishable par défaut~~ → retirée du code : écran de configuration
      au premier lancement, `.env` ou variables d'environnement.
- [x] ~~Créer le remote~~ → `github.com/iesta/mizu-iptv` (privé).
- [ ] Passer le dépôt en public (après les captures de démo).
- [ ] Refaire les captures d'écran sur un **compte de démo** : celles existantes
      exposent les profils, sources et favoris réels.

## Écarté

- **webOS (LG)** — abandonné le 2026-10-24. Décision produit : pas de client web
  pour l'instant. Raison technique pour mémoire : webOS n'accepte que des apps
  HTML/JS (`.ipk`), donc c'était un client séparé (pas un portage Flutter), avec
  la limite MPEG-TS de `<video>`. Ne pas relancer sans une demande explicite.

## Rappels

- Un panneau Xtream renvoie `461` quand on l'interroge trop vite ou trop
  souvent : une requête à la fois, espacées ; ne pas paralléliser les tests.
- Realtime n'est pas publié côté Zen → polling 45 s (déjà en place).
