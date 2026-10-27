# Installer Mizu IPTV — autres méthodes

**Français** · [English](#english)

La méthode la plus simple est dans le [README](README.md#installer) :
une ligne `curl … | sh`. Ce document couvre tout le reste : paquets gérés,
installation depuis les sources, construction des artefacts et dépannage.

---

## 1. Paquets gérés

### Flatpak (toutes distributions, y compris Fedora)

Une fois le `.flatpak` produit (voir §3) :

```bash
flatpak install --user ./dist/app.mizu.iptv.flatpak
flatpak run app.mizu.iptv
```

Le manifeste est en bac à sable avec les permissions réseau, Wayland/X11 et
`dri`, et `--persist=.config/mizu` pour conserver la configuration.

### Arch / Omarchy (paquet natif)

```bash
sudo pacman -S --needed base-devel clang cmake ninja pkgconf gtk3 mpv
yay -S --needed flutter                      # flutter vient de l'AUR
git clone https://github.com/iesta/mizu-iptv.git && cd mizu-iptv/packaging/arch
makepkg -si
```

Le `PKGBUILD` compile depuis les sources et installe dans `/opt/mizu`, avec
`/usr/bin/mizu`, l'entrée de menu et l'icône. Multi-arch (x86_64, aarch64).

### macOS (Homebrew)

```bash
brew tap iesta/mizu
brew install --cask iesta/mizu/mizu-iptv
```

Nécessite une release GitHub publique contenant le zip du `.app` (produit par
`tools/package-macos.sh` sur un Mac) et un tap `iesta/homebrew-mizu`.
Sans notarisation Apple, macOS demandera *clic droit → Ouvrir* au premier
lancement (ou `xattr -dr com.apple.quarantine "/Applications/Mizu IPTV.app"`).

---

## 2. Depuis les sources

> **aarch64 / arm64** : pas de build Linux ARM. Flutter ne publie **pas** de SDK
> Linux arm64 (les archives officielles sont x86_64 uniquement, vérifié sur
> `releases_linux.json`). Il n'y a donc ni AppImage aarch64 ni support de
> compilation sur une machine ARM, sauf à utiliser un SDK non officiel
> (`flutter-elinux`, build depuis les sources).

Installation **utilisateur, sans root** (`~/.local`), avec `tools/install-linux.sh`.

### Debian / Ubuntu

```bash
sudo apt update && sudo apt install -y clang cmake ninja-build pkg-config \
  libgtk-3-dev libmpv-dev curl git unzip xz-utils zip
git clone --depth 1 -b stable https://github.com/flutter/flutter.git ~/flutter
export PATH="$HOME/flutter/bin:$PATH"
git clone https://github.com/iesta/mizu-iptv.git && cd mizu-iptv
./tools/install-linux.sh
```

### Fedora

```bash
sudo dnf install -y clang cmake ninja-build pkgconf-pkg-config gtk3-devel \
  mpv-libs-devel curl git unzip xz zip
git clone --depth 1 -b stable https://github.com/flutter/flutter.git ~/flutter
export PATH="$HOME/flutter/bin:$PATH"
git clone https://github.com/iesta/mizu-iptv.git && cd mizu-iptv
./tools/install-linux.sh
```

### Arch / Omarchy (sans paquet)

```bash
sudo pacman -S --needed base-devel clang cmake ninja pkgconf gtk3 mpv
yay -S --needed flutter
git clone https://github.com/iesta/mizu-iptv.git && cd mizu-iptv
./tools/install-linux.sh
```

### NixOS

```bash
git clone https://github.com/iesta/mizu-iptv.git && cd mizu-iptv
./tools/build.sh linux
cp -a app/build/linux/x64/release/bundle packaging/nix/bundle
nix build ./packaging/nix#default            # → result/bin/mizu
```

*(flake non testé ; sur aarch64 remplacer `x64` par `arm64`.)*

### Ce que fait `tools/install-linux.sh`

| Quoi | Où |
|---|---|
| application | `~/.local/opt/mizu/` |
| lanceur terminal | `~/.local/bin/mizu` |
| entrée de menu | `~/.local/share/applications/app.mizu.iptv.desktop` |
| icônes | `~/.local/share/icons/hicolor/{256,512}/apps/` |

Apparaît ensuite dans le menu Omarchy (**Super + Maj + Espace** → Apps) et dans
tout lanceur XDG. `--uninstall` retire tout, `--no-build` réinstalle le dernier
build.

---

## 3. Construire les artefacts

Nécessaire seulement pour distribuer (les scripts ne servent pas à installer
depuis les sources).

```bash
./tools/package-appimage.sh    # dist/Mizu-IPTV-<arch>.AppImage (~11 Mo)
./tools/package-flatpak.sh     # dist/app.mizu.iptv.flatpak (flatpak-builder requis)
./tools/package-macos.sh       # sur un Mac : zip + sha256 pour le cask
./tools/release.sh 0.1.0       # build AppImage + publication GitHub (--draft, --apk)
```

Flatpak, prérequis :

```bash
sudo pacman -S flatpak flatpak-builder
flatpak remote-add --if-not-exists --user flathub \
  https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.freedesktop.Platform//24.08 \
  org.freedesktop.Sdk//24.08
```

### État des paquets

| Format | Cibles | État |
|---|---|---|
| **AppImage** | x86_64, aarch64 | ✅ testé x86_64 (~11 Mo) |
| **Flatpak** | toutes (Fedora, Debian…) | ⚙️ manifeste + script prêts, non testés |
| **PKGBUILD** (AUR) | Arch, Omarchy | ⚙️ `makepkg --printsrcinfo` OK, build non testé |
| **RPM** | Fedora / RHEL | 📄 squelette, non testé — Fedora recommande Flatpak |
| **Flake Nix** | NixOS | 📄 squelette, non testé |
| **Cask Homebrew** | macOS | 📄 gabarit prêt, nécessite une release GitHub |

---

## 4. Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| `libmpv` introuvable au build | dépendance manquante | Debian : `libmpv-dev` · Fedora : `mpv-libs-devel` · Arch : `mpv` |
| `flutter: command not found` | SDK absent du `PATH` | `export PATH="$HOME/flutter/bin:$PATH"` |
| HTTP 461 sur une source | panneau qui limite les requêtes | espacer, éviter plusieurs clients (souvent 1 connexion max) |
| Pas de vidéo (écran noir) sur émulateur Android | rendu logiciel de media_kit | tester sur un vrai appareil |
| `pod install` échoue (macOS) | CocoaPods à jour ? | `pod repo update`, puis rebuild |
| Rien dans le menu | cache des entrées | `update-desktop-database ~/.local/share/applications` |

---

# English

**English** · [Français](#installer-mizu-iptv--autres-méthodes)

The simplest method lives in the [README](README.md#install): a single
`curl … | sh` line. This document covers everything else: managed packages,
building from source, producing artifacts, and troubleshooting.

## 1. Managed packages

### Flatpak (any distribution, including Fedora)

Once the `.flatpak` is built (see §3):

```bash
flatpak install --user ./dist/app.mizu.iptv.flatpak
flatpak run app.mizu.iptv
```

The manifest is sandboxed with network, Wayland/X11 and `dri` permissions, plus
`--persist=.config/mizu` to keep the configuration.

### Arch / Omarchy (native package)

```bash
sudo pacman -S --needed base-devel clang cmake ninja pkgconf gtk3 mpv
yay -S --needed flutter                      # flutter is an AUR package
git clone https://github.com/iesta/mizu-iptv.git && cd mizu-iptv/packaging/arch
makepkg -si
```

The `PKGBUILD` builds from source and installs into `/opt/mizu`, with
`/usr/bin/mizu`, the menu entry and the icon. Multi-arch (x86_64, aarch64).

### macOS (Homebrew)

```bash
brew tap iesta/mizu
brew install --cask iesta/mizu/mizu-iptv
```

Requires a public GitHub release containing the `.app` zip (produced by
`tools/package-macos.sh` on a Mac) and an `iesta/homebrew-mizu` tap. Without
Apple notarization, macOS asks for *right-click → Open* on first launch (or
`xattr -dr com.apple.quarantine "/Applications/Mizu IPTV.app"`).

## 2. From source

> **aarch64 / arm64**: no Linux ARM build. Flutter does **not** ship a Linux
> arm64 SDK (official archives are x86_64 only, verified against
> `releases_linux.json`). So there is no aarch64 AppImage and no compilation on
> an ARM machine, unless you use an unofficial SDK (`flutter-elinux`, building
> from source).

**Per-user** installation, no root (`~/.local`), via `tools/install-linux.sh`.

### Debian / Ubuntu

```bash
sudo apt update && sudo apt install -y clang cmake ninja-build pkg-config \
  libgtk-3-dev libmpv-dev curl git unzip xz-utils zip
git clone --depth 1 -b stable https://github.com/flutter/flutter.git ~/flutter
export PATH="$HOME/flutter/bin:$PATH"
git clone https://github.com/iesta/mizu-iptv.git && cd mizu-iptv
./tools/install-linux.sh
```

### Fedora

```bash
sudo dnf install -y clang cmake ninja-build pkgconf-pkg-config gtk3-devel \
  mpv-libs-devel curl git unzip xz zip
git clone --depth 1 -b stable https://github.com/flutter/flutter.git ~/flutter
export PATH="$HOME/flutter/bin:$PATH"
git clone https://github.com/iesta/mizu-iptv.git && cd mizu-iptv
./tools/install-linux.sh
```

### Arch / Omarchy (without packaging)

```bash
sudo pacman -S --needed base-devel clang cmake ninja pkgconf gtk3 mpv
yay -S --needed flutter
git clone https://github.com/iesta/mizu-iptv.git && cd mizu-iptv
./tools/install-linux.sh
```

### NixOS

```bash
git clone https://github.com/iesta/mizu-iptv.git && cd mizu-iptv
./tools/build.sh linux
cp -a app/build/linux/x64/release/bundle packaging/nix/bundle
nix build ./packaging/nix#default            # → result/bin/mizu
```

*(flake untested; on aarch64 replace `x64` with `arm64`.)*

### What `tools/install-linux.sh` does

| What | Where |
|---|---|
| application | `~/.local/opt/mizu/` |
| terminal launcher | `~/.local/bin/mizu` |
| menu entry | `~/.local/share/applications/app.mizu.iptv.desktop` |
| icons | `~/.local/share/icons/hicolor/{256,512}/apps/` |

It then appears in the Omarchy menu (**Super + Shift + Space** → Apps) and any
XDG launcher. `--uninstall` removes everything, `--no-build` reinstalls the
last build.

## 3. Building artifacts

Only needed for distribution (these scripts are not required to install from
source).

```bash
./tools/package-appimage.sh    # dist/Mizu-IPTV-<arch>.AppImage (~11 MB)
./tools/package-flatpak.sh     # dist/app.mizu.iptv.flatpak (needs flatpak-builder)
./tools/package-macos.sh       # on a Mac: zip + sha256 for the cask
./tools/release.sh 0.1.0       # AppImage build + GitHub release (--draft, --apk)
```

Flatpak prerequisites:

```bash
sudo pacman -S flatpak flatpak-builder
flatpak remote-add --if-not-exists --user flathub \
  https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.freedesktop.Platform//24.08 \
  org.freedesktop.Sdk//24.08
```

### Package status

| Format | Targets | State |
|---|---|---|
| **AppImage** | x86_64, aarch64 | ✅ tested on x86_64 (~11 MB) |
| **Flatpak** | all (Fedora, Debian…) | ⚙️ manifest + script ready, untested |
| **PKGBUILD** (AUR) | Arch, Omarchy | ⚙️ `makepkg --printsrcinfo` OK, build untested |
| **RPM** | Fedora / RHEL | 📄 skeleton, untested — Fedora recommends Flatpak |
| **Nix flake** | NixOS | 📄 skeleton, untested |
| **Homebrew cask** | macOS | 📄 template ready, needs a GitHub release |

## 4. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `libmpv` not found at build time | missing dependency | Debian: `libmpv-dev` · Fedora: `mpv-libs-devel` · Arch: `mpv` |
| `flutter: command not found` | SDK not on `PATH` | `export PATH="$HOME/flutter/bin:$PATH"` |
| HTTP 461 on a source | panel rate-limiting | space out requests, avoid multiple clients (often 1 connection max) |
| No video (black screen) on Android emulator | media_kit software rendering | test on a real device |
| `pod install` fails (macOS) | stale CocoaPods | `pod repo update`, then rebuild |
| Nothing in the menu | desktop entry cache | `update-desktop-database ~/.local/share/applications` |
