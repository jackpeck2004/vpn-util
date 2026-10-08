cask "vpn-utility" do
  version "0.2.0"
  sha256 "9668ebe519287223737081d229d6011299e65247819270c036bd185f9301c078"

  url "https://github.com/jackpeck2004/vpn-util/releases/download/v#{version}/VPN-Utility-v#{version}-universal.zip"
  name "VPN Utility"
  desc "Menu bar controls for existing VPN clients"
  homepage "https://github.com/jackpeck2004/vpn-util"

  depends_on macos: :ventura

  app "VPN Utility.app"

  caveats <<~EOS
    This preview is ad-hoc signed and is not notarized.
    macOS may require its normal per-app security approval when opening it.
    Existing VPN clients remain responsible for login and authentication.
  EOS
end
