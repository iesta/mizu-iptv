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

## Installer (Linux)

```bash
./tools/install-linux.sh     # build release + installation utilisateur
```

Installe sans root :

| Quoi | Où |
|---|---|
| application | `~/.local/opt/mizu/` |
| lanceur terminal | `~/.local/bin/mizu` |
| entrée de menu | `~/.local/share/applications/app.mizu.iptv.desktop` |
| icônes | `~/.local/share/icons/hicolor/{256,512}/apps/` |

L'apparaît ensuite dans le menu Omarchy (**Super + Maj + Espace** → Apps), et
dans les autres lanceurs XDG. Désinstallation : `tools/install-linux.sh
--uninstall`. Réinstallation sans rebuild : `--no-build`.

## Paquets Linux (AppImage / Flatpak)

**AppImage** — binaire portable, rien à installer :

```bash
./tools/package-appimage.sh
./dist/Mizu-IPTV-x86_64.AppImage
```

Embarque Flutter, libmpv et les assets (~11 Mo). Tourne sur n'importe quelle
distribution x86_64 avec Wayland ou X11 ; aucune dépendance système à installer.

**Flatpak** — nécessaire pour une intégration « bac à sable » :

```bash
sudo pacman -S flatpak flatpak-builder        # Arch / Omarchy
flatpak remote-add --if-not-exists --user flathub \
  https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.freedesktop.Platform//24.08 \
  org.freedesktop.Sdk//24.08

./tools/package-flatpak.sh            # construit dist/app.mizu.iptv.flatpak
./tools/package-flatpak.sh --install   # + installation et lancement
```

Le manifeste (`packaging/flatpak/app.mizu.iptv.yml`) empaquette le bundle
compilé sur l'hôte (pas de SDK Flutter dans le bac à sable) avec les
permissions réseau, Wayland/X11 et `dri`.

### Distribution Linux : quel format pour quelle distro

| Format | Cibles | État |
|---|---|---|
| **AppImage** | toutes (x86_64, aarch64) | ✅ testé x86_64 (~11 Mo, portable) |
| **Flatpak** | toutes, y compris **Fedora** | ⚙️ manifeste + script prêts, non testés (`flatpak-builder` manquant ici) |
| **PKGBUILD** (Arch/AUR) | Arch, Omarchy | ⚙️ analyse `makepkg` OK ; build non testé (`flutter` vient de l'AUR) |
| **RPM** | Fedora / RHEL | 📄 squelette (`packaging/fedora/`), non testé — Fedora recommande Flatpak |
| **Flake Nix** | NixOS | 📄 squelette (`packaging/nix/`), non testé, empaquette un bundle précompilé |

En pratique :

- **Fedora / Ubuntu / openSUSE** → **Flatpak** (c'est ce que Fedora pousse par défaut).
- **N'importe quelle distro, sans rien installer** → **AppImage**.
- **Arch / Omarchy** → PKGBUILD (`makepkg -si`), ou Flatpak.
- **NixOS** → flake, à condition d'accepter de compiler le bundle à la main avant.

Les deux formats universels (AppImage, Flatpak) sont générés par
`tools/package-appimage.sh` et `tools/package-flatpak.sh`, avec détection
d'architecture (`tools/_arch.sh`).

## Lancer en développement

```bash
./tools/build.sh linux        # injecte .env dans le binaire
cd app && flutter run -d linux
```

`tools/build.sh` passe `--dart-define-from-file=../.env` : les valeurs de `.env`
sont **compilées** dans l'application, donc elle est configurée dès
l'installation (pratique pour un APK distribué).

Dépendances système (Linux) : `clang cmake ninja pkg-config libgtk-3-dev
libmpv` (media_kit).

## Android / Android TV

```bash
export ANDROID_HOME=~/dev/tools/android-sdk
./tools/build.sh apk-debug        # ou : apk (release)
adb install -r app/build/app/outputs/flutter-apk/app-debug.apk
```

L'APK embarque la configuration de `.env` : au premier lancement il va
directement à l'écran de connexion, sans demander l'URL ni la clé.

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

## Héberger sa propre instance Supabase

Le client peut pointer vers **ton** projet Supabase au lieu de l'instance de
Zen — utile pour ne plus dépendre d'un service tiers, ou pour sauvegarder tes
données. Tout est détaillé dans [`re/supabase/README.md`](re/supabase/README.md),
en résumé :

1. **Créer un projet** sur <https://supabase.com> (ou self-host).
2. **SQL Editor** → exécuter [`re/supabase/schema.sql`](re/supabase/schema.sql)
   (tables, index, RLS par propriétaire, RPC `favorites_apply_order`, trigger
   de création des préférences).
3. **Authentication** → activer *Email* (Apple/Google possible avec tes propres
   identifiants OAuth).
4. **Créer ton utilisateur** (écran d'inscription du client, ou *Authentication
   → Users*).
5. **Importer tes données** :
   ```bash
   cd re/supabase
   python3 export-data.py --out seed.sql          # mots de passe des sources vidés
   python3 export-data.py --out seed.sql --with-credentials   # tout, fichier sensible
   ```
   puis exécuter `seed.sql` dans le SQL Editor (les UUID de profils et de
   sources sont conservés, donc favoris et progression restent rattachés).
6. **Pointer le client** : renseigner l'URL et la clé publishable dans
   **Préférences**, dans `.env` (avant build), ou via
   `MIZU_BACKEND_URL` / `MIZU_PUBLISHABLE_KEY`.

Ce que ça ne fait pas : l'app Zen officielle garde son URL et sa clé compilées,
elle ne peut pas être redirigée. Cette instance sert à **Mizu** (et à
sauvegarder tes données).

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
