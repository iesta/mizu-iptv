# Cask Homebrew — gabarit à publier dans un tap personnel :
#   brew tap iesta/mizu
#   brew install --cask iesta/mizu/mizu-iptv
#
# Remplacer @VERSION@ et @SHA256@ (voir tools/package-macos.sh, exécuté sur un
# Mac). Prérequis : une release GitHub publique contenant le zip du .app.
#
# Pour le dépôt officiel homebrew-cask : l'app doit être signée ET notarisée
# (compte Apple Developer), avec une URL stable et une version publiée.
cask "mizu-iptv" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/iesta/mizu-iptv/releases/download/v#{version}/Mizu-IPTV-#{version}-macos-arm64.zip"
  name "Mizu IPTV"
  desc "Client IPTV synchronisé (compte Zen)"
  homepage "https://github.com/iesta/mizu-iptv"

  # Le build macOS actuel est arm64 (Mac Apple Silicon).
  depends_on arch: :arm64
  depends_on macos: ">= :ventura"

  app "Mizu IPTV.app"

  zap trash: [
    "~/Library/Application Support/app.mizu.iptv",
    "~/Library/Caches/app.mizu.iptv",
  ]
end
