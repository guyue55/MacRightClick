cask "rightclickassistant" do
  version "1.1.1"
  sha256 "6c548dc44b675f0c3d650c1c9179c861b3dbd19817adbc222f488a216cc8776a"

  url "https://github.com/guyue55/MacRightClick/releases/download/v#{version}/RightClickAssistant-v#{version}-macOS-Universal.dmg"
  name "RightClickAssistant"
  name "MacRightClick"
  desc "Finder right-click context menu assistant"
  homepage "https://github.com/guyue55/MacRightClick"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "RightClickAssistant.app"

  uninstall quit:   "guyue.RightClickAssistant",
            script: {
              executable: "/usr/bin/pluginkit",
              args:       ["-r", "guyue.RightClickAssistant.Extension"],
            }

  zap trash: [
    "~/Library/Containers/guyue.RightClickAssistant",
    "~/Library/Containers/guyue.RightClickAssistant.Extension",
    "~/Library/Group Containers/group.guyue.RightClickAssistant",
    "~/Library/Preferences/guyue.RightClickAssistant.plist",
  ]

  caveats <<~EOS
    RightClickAssistant is an Ad-hoc signed, not notarized community build.
    If macOS blocks the first launch, Control-click the app and choose Open,
    or allow it in System Settings > Privacy & Security. Do not disable
    Gatekeeper globally.
  EOS
end
