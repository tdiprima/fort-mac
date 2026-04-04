Good call — AirDrop is one of those things that can be "on" but still broken for half a dozen reasons. Here's the quick fix plus the troubleshooting rundown.

**Re-enable after the hardening script:**

```bash
defaults write com.apple.NetworkBrowser DisableAirDrop -bool false
killall Finder
```

That flips the defaults key back and restarts Finder so it picks up the change immediately.

**If it's "on" but not working**, walk through these in order — they're the usual culprits:

**Bluetooth and Wi-Fi must both be active.** AirDrop uses Bluetooth for discovery and Wi-Fi for the actual transfer. If either is off, devices won't see each other. They don't need to be on the same Wi-Fi network, but both radios need to be up.

**Firewall block-all kills it.** The hardening script sets `--setblockall on`, which silently drops AirDrop's incoming connections. To fix that while keeping the firewall itself active:

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall off
```

You can still run the firewall in normal mode — it just won't blanket-block unsigned inbound connections anymore.

**Check your AirDrop visibility setting.** In Finder → AirDrop (or System Settings → General → AirDrop & Handoff), make sure it's set to "Contacts Only" or "Everyone" rather than "No One." If you're trying to share with someone not in your contacts, it needs to be "Everyone" temporarily.

**"Do Not Disturb" / Focus modes suppress it.** If you have a Focus mode active, AirDrop notifications get swallowed and the device may not appear to others. Either disable Focus temporarily or add AirDrop as an allowed notification source.

**Bonjour multicast matters too.** The hardening script disables multicast advertisements via mDNSResponder, which can interfere with local device discovery. To re-enable:

```bash
sudo defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool false
sudo killall mDNSResponder
```

**Quick smoke test** — after making changes, open Finder, click AirDrop in the sidebar, and see if nearby devices appear within 30 seconds. If you have an iPhone handy, try sending a photo to the Mac. If the Mac shows up on the phone but the transfer fails, it's almost always the firewall block-all setting.
