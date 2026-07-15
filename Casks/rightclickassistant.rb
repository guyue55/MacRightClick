cask "rightclickassistant" do
  version "1.2.1"
  sha256 "9230f3db5684f537a00c15141e6dac746092ea4fef59e2ab37538d64dba46e37"

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

  uninstall_postflight do
    system_command "/usr/bin/osascript",
                   args: ["-l", "JavaScript", "-e", 'ObjC.import("AppKit"); $.NSUpdateDynamicServices();']
  end

  uninstall quit:   "guyue.RightClickAssistant",
            script: {
              executable: "/usr/bin/pluginkit",
              args:       ["-r", "/Applications/RightClickAssistant.app/Contents/PlugIns/RightClickAssistantExtension.appex"],
            },
            trash:  "~/Library/Services/RightClickAssistantQuickActions.service"

  zap trash: [
    "~/Library/Containers/guyue.RightClickAssistant",
    "~/Library/Containers/guyue.RightClickAssistant.Extension",
    "~/Library/Group Containers/group.guyue.RightClickAssistant",
    "~/Library/Preferences/guyue.RightClickAssistant.plist",
    "~/Library/Services/RightClickAssistantQuickActions.service",
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
