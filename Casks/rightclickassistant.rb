cask "rightclickassistant" do
  version :latest
  sha256 :no_check

  url "https://github.com/guyue55/MacRightClick/releases/latest/download/RightClickAssistant-Latest.dmg"
  name "RightClickAssistant"
  name "MacRightClick"
  desc "Finder right-click context menu assistant"
  homepage "https://github.com/guyue55/MacRightClick"

  depends_on macos: ">= :ventura"

  app "RightClickAssistant.app"

  uninstall quit: "guyue.RightClickAssistant"

  zap trash: [
    "~/Library/Containers/guyue.RightClickAssistant",
    "~/Library/Containers/guyue.RightClickAssistant.Extension",
    "~/Library/Group Containers/group.guyue.RightClickAssistant",
    "~/Library/Preferences/guyue.RightClickAssistant.plist",
  ]
end
