cask "rightclickassistant" do
  version "1.2.0"
  sha256 "fa71e4b80a4e1e4071ca6e6a5ee0af79ae2b48c74401c215ece2eea8aa8ad813"

  url "https://github.com/guyue55/MacRightClick/releases/download/v#{version}/RightClickAssistant-v#{version}-macOS-Universal.dmg"
  name "RightClickAssistant"
  name "MacRightClick"
  desc "Finder right-click context menu assistant"
  homepage "https://github.com/guyue55/MacRightClick"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

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
    First try Control-click > Open, or System Settings > Privacy & Security
    > Open Anyway. If macOS still blocks this verified download, remove the
    quarantine attribute from this app only, then open it:

      sudo /usr/bin/xattr -dr com.apple.quarantine "/Applications/RightClickAssistant.app"
      open "/Applications/RightClickAssistant.app"

    Enter your macOS administrator password when prompted; Terminal does not
    display password characters. Do not disable Gatekeeper globally.
  EOS
end
