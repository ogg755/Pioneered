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
3. The artifact contains `mixxx_*_arm64.deb`, `mixxx-data_*_all.deb`, and
   `mixxx-dbgsym_*.deb` (debug symbols for crash backtraces); install together.
   On a re-deploy, unhold first — held packages can block even newer versions:
   sudo apt-mark unhold mixxx mixxx-data 2>/dev/null || true
   sudo apt install -y /tmp/mixxx_*_arm64.deb /tmp/mixxx-data_*_all.deb /tmp/mixxx-dbgsym_*.deb
   sudo apt-mark hold mixxx mixxx-data        # stop apt upgrade replacing them
4. Verify: mixxx --version shows a "+usbbrowse" suffix.

## Upgrading Mixxx later
sudo apt-mark unhold mixxx mixxx-data, update `mixxx-patch/VERSION.md` facts,
re-check the patch applies to the new apt source, re-run the workflow,
reinstall, re-hold.

## USB auto-mount layer (pi/ directory)
The udev/systemd mount machinery lives on the Pi and is versioned in `pi/`:
- `pi/99-usb-automount.rules` -> `/etc/udev/rules.d/99-usb-automount.rules`
- `pi/usb-mount@.service`     -> `/etc/systemd/system/usb-mount@.service`
- `pi/usb-mount.sh`           -> `/usr/local/bin/usb-mount.sh` (chmod +x)
- `pi/usb-umount.sh`          -> `/usr/local/bin/usb-umount.sh` (chmod +x)
After changing the rules/unit: `sudo udevadm control --reload` and
`sudo systemctl daemon-reload`. The mount script serializes slot selection
with flock; without it, two sticks inserted simultaneously both grabbed
/media/USBA (the second mount stacking over the first) and USBB stayed empty.

## Behavior contract
- USB sticks must mount at /media/USBA and /media/USBB (udev scripts).
- On an unpatched Mixxx the skin still works; USB buttons are inert.
- On a fresh boot the first USB A/B press primes Mixxx's Rekordbox device scan (async) and shows the Rekordbox landing page; the second press jumps to the device's playlists.

## Ejecting USB sticks (hold-to-eject)
- Hold USB A/USB B ~5 s: the button flashes red/white, speeding up; at 5 s the
  stick is unmounted and its playlists/tracks disappear. Safe to pull.
- "USB LOCKED" (2 s banner): a deck is PLAYING a track from that stick.
  Pause it, then retry. Paused decks don't block eject: their tracks are
  automatically unloaded when the eject fires (a paused deck still holds
  the audio file open, which would otherwise make the unmount fail).
- "EJECT FAILED" (2 s banner): unmount failed after several retries; the
  stick is still mounted. umount's stderr is logged in Mixxx's log.
- Short press is unchanged (browse toggle). Releasing mid-hold cancels.
- Eject runs `sudo umount /media/USBX` from Mixxx; the same passwordless
  sudoers rule the old Tkinter overlay used must remain in place.
- The old Tkinter overlay (usb-control.py) is retired: remove its line from
  the Openbox autostart file (~/.config/openbox/autostart) after the eject
  feature passes testing.

## Crash diagnostics
One-time setup:  sudo apt install -y systemd-coredump gdb
(Debug symbols come from the mixxx-dbgsym package installed above.)
After any Mixxx crash:
  coredumpctl list mixxx
  DEBUGINFOD_URLS="https://debuginfod.debian.net" coredumpctl gdb mixxx
  (gdb) bt
Copy the backtrace into the session for diagnosis.
