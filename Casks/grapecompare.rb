cask "grapecompare" do
  version "1.8.0"
  sha256 "TO_BE_SET_BY_RELEASE_WORKFLOW"

  url "https://github.com/everettjf/grapecompare/releases/download/v#{version}/GrapeCompare-#{version}.zip"
  name "GrapeCompare"
  desc "Native file and folder comparison for macOS"
  homepage "https://xnu.app/grapecompare/"

  depends_on macos: :tahoe
  app "GrapeCompare.app"

  zap trash: [
    "~/Library/Preferences/com.xnu.compare.plist",
    "~/Library/Saved Application State/com.xnu.compare.savedState",
  ]
end
