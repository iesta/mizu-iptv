# Mizu IPTV (水)

Client IPTV **non officiel** pour Linux (et, à terme, Android / Android TV /
macOS), écrit en Flutter. Il se **synchronise avec un compte Zen IPTV** :
profils, sources, favoris et reprise de lecture.

> Application de lecture uniquement : elle ne fournit aucun contenu. Utilise
> ton propre compte et tes propres sources.

## État

| Fonction | État |
|---|---|
| Connexion au compte (email / mot de passe) | ✅ |
| Profils de visionnage + sélection | ✅ |
| Sources synchronisées (Xtream + M3U) | ✅ |
| Gérer les sources : ajouter / modifier / supprimer / tester | ✅ |
| Live TV / Films / Séries, colonne de catégories + recherche | ✅ |
| Favoris par profil (noms + affiches, ajout/retrait) | ✅ |
| Reprise de lecture (« Reprendre SxEy », saison et position) | ✅ |
| Lecteur libmpv : pistes audio et sous-titres | ✅ |
| Thème : suit Omarchy si présent, sinon thème par défaut | ✅ |
| Navigation télécommande / clavier (D-pad) | ✅ sources, catalogue, fiche, lecteur |
| Build Android / Android TV | ✅ APK debug + manifest TV (Leanback) |
| Build macOS | 🚧 à faire sur un Mac (Xcode) |

## Lancer

```bash
cd app
flutter run -d linux          # ou : flutter build linux --release
```

Dépendances système (Linux) : `clang cmake ninja pkg-config libgtk-3-dev
libmpv` (media_kit).

## Android / Android TV

```bash
export ANDROID_HOME=~/dev/tools/android-sdk
cd app && flutter build apk --debug          # ou --release (signé debug)
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

L'APK est marqué `LEANBACK_LAUNCHER` (il apparaît dans le lanceur TV), avec
bannière, `touchscreen` non requis et trafic HTTP en clair autorisé (la plupart
des panneaux IPTV ne sont pas en TLS).

Télécommande / manette :

| Touche | Action |
|---|---|
| D-pad | déplacer le focus (liseré) |
| OK / Entrée / A | ouvrir, valider |
| Retour / Échap | revenir |
| CH+ / CH- (PageUp / PageDown) | changer d'onglet |
| Appui long sur une source | modifier / supprimer |
| Espace (lecteur) | lecture / pause |
| ← / → (lecteur) | ±10 s |
| ↑ / ↓ (lecteur) | volume |
| M (lecteur) | muet |

## Regarder

0. Onglet **Préférences** (roue dentée, aussi accessible avant connexion) :
   URL du backend, clé publishable, clé TMDB. Se déconnecter s'y trouve aussi.
1. Onglet **Sources** → clique une carte (ou l'icône grille) pour ouvrir le
   catalogue.
2. **Live TV** / **Films** / **Séries** : colonne de catégories à gauche,
   recherche en haut, grille ou liste à droite.
3. Chaîne → lecture directe ; film → fiche → *Lecture* ; série → fiche →
   saison → épisode.
4. Le lecteur enregistre la position dans `serie_progress` toutes les 15 s et à
   la fermeture (profil actif). ♥ ajoute aux favoris.

## Configuration

**Aucune clé n'est compilée dans l'application.** Au premier lancement, Mizu
s'ouvre sur un écran de configuration (logo 水) qui demande l'URL Supabase et la
clé publishable ; elles sont enregistrées dans `~/.config/mizu/config.json`
(chmod 600).

Trois autres façons, par ordre de priorité :

```bash
# 1. variables d'environnement
export MIZU_BACKEND_URL=https://mon-projet.supabase.co
export MIZU_PUBLISHABLE_KEY=sb_publishable_...
export MIZU_TMDB_KEY=...            # optionnel

# 2. fichier .env (répertoire courant, ~/.config/mizu/, ou à côté de l'exécutable)
cp .env.example .env && $EDITOR .env

# 3. config.json (écrit par l'écran de préférences)
```

L'écran **Préférences** (roue dentée) permet de tout modifier après coup, de
tester la connexion GoTrue, et de se déconnecter. Changer l'URL ou la clé
demande un redémarrage.

`backend_url` / `publishable_key` servent à pointer vers **ta propre instance**
(voir [`re/supabase/`](re/supabase/)). `tmdb_api_key` (gratuite) améliore les
fiches des favoris et de la reprise ; sans elle, les noms viennent de l'index
local du catalogue.

## Thème

Sur Omarchy, l'app lit `~/.local/state/omarchy/current/theme/colors.toml` et en
dérive ses couleurs (fond, cartes, accent, erreurs). Relecture toutes les 8 s :
un changement de thème s'applique à chaud. Ailleurs, thème par défaut.

## Documentation technique

- [`re/PROTOCOL.md`](re/PROTOCOL.md) — protocole de synchronisation observé
  (tables, colonnes, RPC, limites).
- [`re/supabase/`](re/supabase/) — reconstruction du schéma, export des données,
  procédure pour héberger ta propre base.

## Structure

```
app/                 client Flutter
  lib/data/          accès Supabase, Xtream, M3U, index TMDB
  lib/state/         session, profils, synchronisation
  lib/ui/            écrans (login, sources, catalogue, fiche, lecteur)
  lib/theme/         palette Omarchy / thème par défaut
re/                  ingénierie inverse et documentation du protocole
```

## Avertissement

Projet d'interopérabilité : il permet d'utiliser **ton** compte et **tes**
sources sur une plateforme non supportée. Il ne contourne aucun achat, ne
fournit aucun contenu et ne redistribue rien de l'application d'origine. Le
reverse engineering a été fait par observation (chaînes du binaire, API
publique, données de notre propre compte). Vérifie que la loi et les conditions
d'utilisation qui t'engagent l'autorisent dans ton cas.

## Licence

MIT — voir [`LICENSE`](LICENSE).
