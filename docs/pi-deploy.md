# XDJ400 Pi deployment notes

## Skin
scp -r Pioneered rpims@XDJ400.local:~/.mixxx/skins/
Select in Preferences > Interface. Required library prefs:
Preferences > Library > row height 48 px, font size ~14 pt.

## Patched Mixxx (USB A/B buttons)
The skin's USB A/USB B buttons need the patched Mixxx build
(controls `[Library],goto_usb_a` / `goto_usb_b`, patch in `mixxx-patch/`).

1. Run the "Build patched Mixxx .deb (arm64)" GitHub Actions workflow.
2. Download the `mixxx-deb` artifact.
3. The artifact contains both `mixxx_*_arm64.deb` and `mixxx-data_*_all.deb`; both must be installed together:
   sudo apt install -y /tmp/mixxx_*_arm64.deb /tmp/mixxx-data_*_all.deb
   sudo apt-mark hold mixxx mixxx-data        # stop apt upgrade replacing them
4. Verify: mixxx --version shows a "+usbbrowse" suffix.

## Upgrading Mixxx later
sudo apt-mark unhold mixxx mixxx-data, update `mixxx-patch/VERSION.md` facts,
re-check the patch applies to the new apt source, re-run the workflow,
reinstall, re-hold.

## Behavior contract
- USB sticks must mount at /media/USBA and /media/USBB (udev scripts).
- On an unpatched Mixxx the skin still works; USB buttons are inert.
- On a fresh boot the first USB A/B press primes Mixxx's Rekordbox device scan (async) and shows the Rekordbox landing page; the second press jumps to the device's playlists.
