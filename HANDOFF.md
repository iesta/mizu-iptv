# Handoff — session de développement (2026-10-28)

Document de reprise pour continuer sur une autre machine (Mac). Il résume
l'état du dépôt à la fin de la session OpenCode « Mizu main dev ».

## Reprendre la session OpenCode brute

- Session : `ses_e83724876ffevfUa7vjuAIo7FH` (« Mizu main dev »).
- Export **hors dépôt** : `~/mizu-opencode-session.json` (sanitized, ~3 Mo,
  chmod 600). Le copier sur l'autre machine (scp, AirDrop, clé USB) puis :
  ```bash
  opencode import ~/mizu-opencode-session.json
  ```
- Alternative brute (dépend de la version d'OpenCode) : copier
  `~/.local/share/opencode/`. L'import JSON est la voie propre.

## État du dépôt

- Branche `main`, à jour avec `origin` ; tags `v0.1`, `v0.2`, `v0.3`.
- Machine de la session : **Asahi Linux arm64 (MacBook Air M1)**.
  - Flutter 3.47.8 bootstrappé dans `~/dev/tools/flutter` (Dart 3.13.7).
  - Build **Linux arm64** OK (`build/linux/arm64/release/bundle/mizu_iptv`).
  - **Android local impossible ici** : pas de JDK/SDK/build-tools/émulateur
    Android pour Linux arm64 (Arch ARM ne fournit que `android-tools`/adb).
    Les builds APK passent par la **CI GitHub Actions** (tag `v*`).
  - L'app tourne sur le workspace Hyprland **9** (règle locale
    `~/.config/hypr/hyprland.lua`, hors dépôt).
- Prochaine étape prévue : **macOS** (build, lancement, lecture, émulateur
  Android via Android Studio sous macOS).

## Fonctionnalités livrées dans cette session

- **Accueil** configurable : onglet activable/désactivable, blocs de covers
  ordonnables et activables un par un (dernières sorties films/séries,
  tendances TMDB, reprise films/séries, favoris films/séries/TV).
- **Préférences en onglets** : Préférences, Compte (3 sections : Compte,
  Synchro, Données brutes), TMDB, À propos.
- **Notes sur 10** partout, étoiles à 5 icônes (2 points/étoile).
- **Favoris** : tri du plus récent, ouverture des chaînes, état « source
  supprimée » + action de retrait.
- **Reprendre** : modes grille/liste, recherche, tri, taille de vignettes,
  progression visible.
- **Catalogue** : recherche avec X, panneau latéral (taille vignettes, tri),
  note sur les covers, ordre des sections, sélecteur de version des séries
  (plusieurs `series_id` pour un même TMDB).
- **Fiche** : backdrop plein écran + dégradé, genres en tags, bande-annonce
  (TMDB, ouverture externe), menu « … » (jouer du début, reprendre avec
  l'heure, annuler le suivi, favoris).
- **Lecteur** : contrôles au clic, OSD de saut cumulés (10 s / 1 min / 10 min),
  reprise auto, relance sur erreur (HTTP 461), touches média, Ctrl+F.
- **Cache disque des images** : `~/.cache/mizu/images` (TTL 30 j, max 500 Mo).
- **Raccourcis** : `Échap` ferme la fiche/préférences, `Ctrl+,` ouvre les
  préférences partout, `f`/`,` dans le catalogue, touches média Linux.
- **MPRIS (Linux)** : service `org.mpris.MediaPlayer2.mizu` ajouté via le
  paquet `dbus` — à **vérifier** (voir ci-dessous).

## Points à vérifier / en suspens

1. **MPRIS** : lors du test, le nom n'apparaissait pas sur le bus
   (`mizu` absent de `busctl --user list`) ; le service DBus standalone
   fonctionne. À diagnostiquer sur Linux (démarrage dans `PlayerPage`).
   Non applicable sous macOS.
2. **macOS** : le build et le lancement sont validés ; la **lecture vidéo**
   (media_kit/libmpv via CocoaPods) reste à tester.
3. **Android** : impossible à compiler localement sur Asahi ; utiliser la CI
   (release `v*` en vanilla, ou `workflow_dispatch` avec `flavor=zen`).
4. **Blocs TMDB** (dernières sorties/tendances) : nécessitent la clé TMDB et
   ne montrent que les contenus **présents dans le catalogue** (jouables).
   « Les plus regardés » = tendances TMDB (pas de feed Xtream).
5. **Silo** : une seule entrée sur les sources actives (`series_id` 2243) ; les
   libellés FR/MULTI sont dans les titres d'épisodes. Le sélecteur de version
   fonctionne pour les séries à plusieurs `series_id` (ex. Shaka iLembe).
6. **Cache images** : pas d'interface de purge (supprimer le dossier), TTL/taille
   codés (`cached_image.dart`).
7. **APK release signé** : keystore à créer (TODO).

## Reprise sur le Mac

```bash
git clone <remote> mizu-iptv && cd mizu-iptv
cd app && flutter pub get
cd macos && pod install && cd ..
# .env par machine (jamais commité)
cp ../.env.example ../.env && $EDITOR ../.env
../tools/build.sh macos
open build/macos/Build/Products/Release/Mizu\ IPTV.app
```

- Config macOS : `~/Library/Application Support/app.mizu.iptv/config.json`.
- Émulateur Android : Android Studio (macOS Apple Silicon) → image
  système arm64 → `flutter run` (le SDK Android local est fourni par Studio).
- Raccourcis de la session (Ctrl+, / Échap / `f`) fonctionnent aussi.

## Ce qui n'est pas dans le dépôt (à récupérer séparément)

- `.env` de la machine (URL Supabase, clé publishable, clé TMDB).
- Session OpenCode exportée : `~/mizu-opencode-session.json`.
- Règle Hyprland workspace 9 (`~/.config/hypr/hyprland.lua`), spécifique Linux.
- Identifiants des sources IPTV (dans Supabase, jamais dans le repo).

## Fichiers clés ajoutés cette session

```
app/lib/ui/home_tab.dart          onglet Accueil (blocs)
app/lib/ui/home_blocks.dart       définitions des blocs
app/lib/ui/cached_image.dart      cache disque des covers (TTL/limite)
app/lib/ui/catalog_options.dart   options de tri partagées
app/lib/platform/mpris_service.dart  MPRIS Linux (dbus)
```
