# Mizu IPTV — notes pour les agents

Client IPTV **Flutter** (Linux, Android/Android TV, macOS à venir) qui se
synchronise avec un compte **Zen IPTV** (backend Supabase). Projet
d'interopérabilité, licence MIT, aucune ressource de l'app d'origine n'est
embarquée.

Lire d'abord : [`README.md`](README.md) (usage), [`TODO.md`](TODO.md) (état des
tâches et pistes mises de côté), [`re/PROTOCOL.md`](re/PROTOCOL.md) (protocole
observé), [`re/supabase/`](re/supabase/) (schéma + export).

## État par plateforme

| Plateforme | État | Où ça a été validé |
|---|---|---|
| Linux | ✅ build + run + lecture | machine de dev d'origine |
| Android / Android TV | ✅ APK debug, D-pad, lecture | émulateur Android 14 1080p |
| macOS | ⚠️ **configuré mais jamais compilé** | à faire sur un Mac |

Le dossier `app/macos/` existe déjà et est configuré (icônes, entitlements,
ATS). **Ne pas relancer `flutter create --platforms=macos .`** : cela écraserait
`macos/Runner/Configs/AppInfo.xcconfig` et les entitlements.

## Première tâche sur un Mac

```bash
# prérequis : macOS 12+, Xcode + Command Line Tools, Flutter stable (>= 3.47), CocoaPods
flutter doctor            # doit être vert pour "Xcode"

cd app
flutter pub get
(cd macos && pod install)          # parfois nécessaire avant le premier build
flutter build macos --debug        # ou --release
open build/macos/Build/Products/Debug/Mizu\ IPTV.app
```

Puis vérifier, dans l'ordre :

1. l'écran de connexion s'affiche (logo 水) et le login fonctionne ;
2. **Sources** → ouvrir `pelicanDaddy` → Live TV se charge (test réseau + HTTP
   en clair : c'est le point le plus fragile, voir ATS ci-dessous) ;
3. lecture d'une chaîne (libmpv embarqué par `media_kit`) ;
4. favoris (♥) et reprise (position écrite dans `serie_progress`).

Points spécifiques macOS :

- **Entitlements** : `app-sandbox` + `com.apple.security.network.client` sont
  présents dans `DebugProfile.entitlements` et `Release.entitlements`. Sans
  `network.client`, toutes les requêtes échouent silencieusement.
- **ATS** : `NSAllowsArbitraryLoads` est activé dans `macos/Runner/Info.plist`
  parce que la majorité des panneaux IPTV sont en `http://` (non TLS).
- **Signature** : le build local est ad-hoc. Au premier lancement macOS peut
  demander *clic droit → Ouvrir*. Pour distribuer : Developer ID + `notarytool`
  (compte Apple payant), non fait volontairement.
- **`media_kit_libs_video`** tire bien `media_kit_libs_macos_video` (vérifié) :
  pas de dépendance supplémentaire à ajouter.

## Ce qui ne doit jamais être commité

- `zeniptv.app/`, `zeniptv.zip`, `*.dmg`, `*.ipa` — binaire propriétaire.
- `re/.session.json`, `re/live-dump.json`, `seed*.sql` — jetons et identifiants
  IPTV en clair.
- Toute clé privée / token. Voir [`.gitignore`](.gitignore).

Les sessions locales vivent hors du dépôt : `~/.config/mizu/session.json`
(script `re/zen-login.sh`) et `~/.local/share/app.mizu.iptv/` (app).

## Carte du code

```
app/lib/main.dart              init Supabase + media_kit + thème
app/lib/mizu_config.dart       backend configurable (fichier ou env)
app/lib/platform/app_dirs.dart chemins XDG (Linux) ou path_provider (mobile/mac)
app/lib/data/                  Supabase (sync_repository), Xtream, M3U, index TMDB
app/lib/state/app_state.dart   session, profils, sync, polling
app/lib/ui/                    login, favoris (3 colonnes), sources (+formulaire),
                               catalogue, fiche, lecteur, préférences
app/lib/ui/tv_focus.dart       focus télécommande (liseré) + Échap = retour
app/lib/theme/omarchy_theme.dart palette Omarchy sinon thème par défaut
re/                            ingénierie inverse, schéma, scripts d'export
tools/make_icons.py            logo 水 → assets Linux/Android/macOS
```

## Conventions

- UI et commentaires **en français**. Code ASCII (sauf `水` dans le logo/README).
- Aucun secret en dur. La clé publishable par défaut est surchargeable via
  `~/.config/mizu/config.json`, `MIZU_BACKEND_URL` / `MIZU_PUBLISHABLE_KEY`.
- Avant de committer : `flutter analyze` sans erreur + build de la plateforme
  touchée. Messages de commit en français, impératif, une ligne de titre.
- Variables utiles pour les tests manuels :
  `MIZU_TAB=0|1|2` (0 Favoris, 1 Sources, 2 Reprendre), `MIZU_ROUTE=browse:|xt:|xtplay:|detail:|add:`,
  `MIZU_AUTOPLAY=1`.

## Pièges connus (déjà rencontrés)

- **Focus TV** : utiliser `onFocusChange`, pas `onShowFocusHighlight` — en mode
  tactile/TV, Flutter n'active pas le highlight clavier et le liseré ne
  s'affiche jamais.
- **Panneaux Xtream** : ils renvoient `HTTP 461` quand on enchaîne les requêtes
  (limite de connexions). D'où : un seul chargement par section, filtrage local,
  indexation espacée de 3 s, bascule automatique vers une autre source.
- **Realtime** : absent de la publication `supabase_realtime` côté Zen →
  polling 45 s dans `AppState`.
- **Ne jamais écrire de progression pour une chaîne** (`contentType == 'channel'`) :
  cela créait des lignes parasites dans `serie_progress` (corrigé).
- **`content_id`** = id TMDB pour `vod`/`serie`, **nom de la chaîne** pour
  `channel`. Les TMDB ids sont résolus par l'index local du catalogue
  (`CatalogIndex`), pas par l'API TMDB (clé optionnelle).

## Reste à faire

Liste tenue à jour dans [`TODO.md`](TODO.md). En résumé : compiler macOS,
masquer la barre de seek sur le direct, liseré de focus sur les chaînes, APK
release signé, puis publication (remote privé d'abord).

**webOS (LG)** : mis de côté, analyse et plan de reprise dans `TODO.md`
(section « webOS »). Ne pas relancer ce chantier sans avoir vérifié au préalable
que le panneau sert du **HLS** — le MPEG-TS n'est pas lisible par `<video>` sur
webOS.
