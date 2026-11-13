# The source of the Peep cask in itspriddle/homebrew-brews (Casks/peep.rb, #84). Don't edit the
# tap's copy: the release workflow runs `scripts/render-cask VERSION SHA256`, which fills in the
# version and sha256 lines below, and pushes the result to the tap.
cask "peep" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/itspriddle/peep/releases/download/v#{version}/Peep-#{version}.dmg"
  name "Peep"
  desc "Markdown viewer with a command-line tool"
  homepage "https://peep.now/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sequoia

  app "Peep.app"
  binary "#{appdir}/Peep.app/Contents/Helpers/peep"
  manpage "#{appdir}/Peep.app/Contents/Resources/man/man1/peep.1"
  bash_completion "#{appdir}/Peep.app/Contents/Resources/completions/peep.bash"
  zsh_completion "#{appdir}/Peep.app/Contents/Resources/completions/_peep"
  fish_completion "#{appdir}/Peep.app/Contents/Resources/completions/peep.fish"

  zap trash: [
    "~/Library/Application Support/Peep",
    "~/Library/Caches/now.peep.Peep",
    "~/Library/HTTPStorages/now.peep.Peep",
    "~/Library/HTTPStorages/now.peep.Peep.binarycookies",
    "~/Library/Preferences/now.peep.Peep.plist",
    "~/Library/Saved Application State/now.peep.Peep.savedState",
    "~/Library/WebKit/now.peep.Peep",
  ]
end
