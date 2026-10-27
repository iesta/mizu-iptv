{
  # Mizu IPTV — flake Nix. NON TESTÉ (nix absent sur la machine de dev).
  #
  # Deux approches possibles :
  #
  # 1. (celle-ci) empaqueter un bundle Flutter **déjà compilé**. Simple, mais
  #    il faut copier le bundle avant de builder :
  #
  #      ./tools/build.sh linux
  #      cp -a ../app/build/linux/x64/release/bundle ./bundle
  #      nix build .#default        # → result/bin/mizu
  #
  # 2. compiler depuis les sources dans le bac à sable : il faut alors gérer
  #    `flutter pub get` hors ligne (dart2nix / buildDartApplication) et fournir
  #    le SDK Flutter — nettement plus lourd.
  description = "Mizu IPTV — client IPTV synchronisé (compte Zen)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in {
      packages = forAll (pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "mizu-iptv";
          version = "1.0.0";

          # Bundle copié ici (voir l'en-tête) ; gitignore-le.
          src = ./bundle;

          nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.makeWrapper ];
          buildInputs = [
            pkgs.gtk3
            pkgs.mpv
            pkgs.libGL
            pkgs.libepoxy
          ];

          # Les .so livrés avec Flutter pointent vers des chemins absolus.
          dontPatchELF = true;

          installPhase = ''
            runHook preInstall

            mkdir -p $out/opt/mizu $out/bin
            cp -a . $out/opt/mizu/
            ln -s $out/opt/mizu/mizu_iptv $out/bin/mizu

            mkdir -p $out/share/applications \
                     $out/share/icons/hicolor/256x256/apps
            install -D -m 644 ${../flatpak/app.mizu.iptv.desktop} \
              $out/share/applications/app.mizu.iptv.desktop
            install -D -m 644 ${../flatpak/app.mizu.iptv.png} \
              $out/share/icons/hicolor/256x256/apps/app.mizu.iptv.png

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Client IPTV synchronisé (compte Zen)";
            license = licenses.mit;
            platforms = systems;
            mainProgram = "mizu";
          };
        };
      });
    };
}
