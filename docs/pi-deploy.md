# XDJ400 Pi deployment notes

## One-shot updater (preferred)
Copy `pi/update-pioneered.sh` to the Pi once, then to update everything
(debs + skin) from the latest GitHub release with no further input:

    sudo ./update-pioneered.sh            # latest release
    sudo ./update-pioneered.sh v2.5.0-r18 # specific release / rollback

It downloads the release's three debs and the matching skin source,
installs them non-interactively, re-holds the packages, installs the skin
to the login user's `~/.mixxx/skins/Pioneered`, and reboots after a 10 s
Ctrl-C-able countdown. Requires the release to have the three debs
attached (the manual steps below remain as fallback).

## Skin
scp -r Pioneered rpims@XDJ400.local:~/.mixxx/skins/
Select in Preferences > Interface. Library sizing (library-ui patch, r10+):
Preferences > Library > "Tracks visible in list" (default 8) sizes rows and
font automatically; set it to Off to use the old manual row height/font
(48 px / ~14 pt on unpatched builds).

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
- The first USB A/B press for a stick that is not yet in Mixxx's device list (fresh boot, or the stick was plugged in after the last scan) primes an async rescan and shows the Rekordbox landing page; the second press jumps to the device's playlists.

## Ejecting USB sticks (hold-to-eject)
- Hold USB A/USB B ~5 s: the button flashes red/white, speeding up; at 5 s the
  stick is unmounted and its playlists/tracks disappear. Safe to pull.
- "USB LOCKED" (3 s banner): a deck is PLAYING a track from that stick.
  Pause it, then retry. Paused decks don't block eject: their tracks are
  automatically unloaded when the eject fires (a paused deck still holds
  the audio file open, which would otherwise make the unmount fail).
- "EJECT FAILED" (3 s banner): unmount failed after several retries; the
  stick is still mounted. umount's stderr is logged in Mixxx's log.
- Short press is unchanged (browse toggle). Releasing mid-hold cancels.
- Eject runs `sudo umount /media/USBX` from Mixxx; the same passwordless
  sudoers rule the old Tkinter overlay used must remain in place.
- The old Tkinter overlay (usb-control.py) is retired: remove its line from
  the Openbox autostart file (~/.config/openbox/autostart) after the eject
  feature passes testing.

## Headphone (cue) distortion on ch 3-4 — diagnosis
Symptom evolution: phones out (ch 3-4) was quiet on the Pi, and after the
MIDI headphone knob was unmapped it now distorts/clips even at low volume,
while MASTER (ch 1-2) plays clean and loud through the *same* raw-ALSA
stream, format and DAC. The controller + phones are loud and clean under
Mixxx on a laptop.

Card facts (from `stream0`): 44100 Hz only; formats S16_LE and S24_3LE;
4 channels labelled `FL FR FC LFE`; **no hardware mixer controls at all**
(so there is no card volume to raise — the old "max the mixers" advice does
not apply to this interface). The `FC/LFE` labels are why `PA_ALSA_PLUGHW=1`
made it *worse*: the plug layer treated ch 3-4 as centre/subwoofer and
applied surround downmixing + an LFE low-pass to the cue bus. Do not use
PLUGHW on this card without an explicit 1:1 `ttable`.

Because ch 1-2 and ch 3-4 share one interleaved buffer yet only ch 3-4
corrupts, a whole-stream format bug is unlikely. Two suspects remain:
(A) Mixxx writes a hot/corrupt signal into the cue bus (digital, above ALSA);
(B) the S24_3LE 4-channel interleave corrupts only the trailing channel pair
on PortAudio's raw-hw path (3-byte packing misalignment).

Copy `pi/audio-diag.sh` to the Pi and run:

  ./audio-diag.sh               # card + stream0 caps + mixer controls (report)
  ./audio-diag.sh matrix        # Mixxx closed: inject -6 dBFS tones,
                                # {S16_LE,S24_3LE} x {ch1,ch3,ch4}, via aplay

At -6 dBFS nothing can legitimately clip, so any distortion is corruption.
Compare ch1 vs ch3/ch4 within each format (full table in the script header):
- ch3/4 clean both formats → suspect (A): Mixxx cue bus. Lower
  `[Master],headGain` toward unity, watch the headphone CLIP light, check
  pregains aren't stacking.
- ch3/4 distort only in S24_3LE → suspect (B): force the card to S16_LE via a
  named 1:1 `plug` pcm and select it in Mixxx (the script prints the
  `~/.asoundrc` snippet).
- ch3/4 distort in both formats → driver-level; capture `dmesg | grep -i snd`
  and the `aplay --dump-hw-params` output the matrix prints.

## Crash diagnostics
One-time setup:  sudo apt install -y systemd-coredump gdb
(Debug symbols come from the mixxx-dbgsym package installed above.)
After any Mixxx crash:
  coredumpctl list mixxx
  DEBUGINFOD_URLS="https://debuginfod.debian.net" coredumpctl gdb mixxx
  (gdb) bt
Copy the backtrace into the session for diagnosis.
