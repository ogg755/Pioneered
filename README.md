![logo](https://github.com/timewasternl/Pioneered/blob/master/images/pioneered_logo.png?raw=true)

Pioneer-inspired Mixxx theme **plus a patched Mixxx build** that together turn a
Raspberry Pi and a Pioneer DDJ-400 into a standalone XDJ-style console: boot the
Pi, plug in your rekordbox USB sticks, and DJ — no laptop.

This is a fork of [timewasternl/Pioneered](https://github.com/timewasternl/Pioneered)
(original Pi standalone mod [video](https://www.youtube.com/watch?v=kyrJW7Vaf68)),
extended with a set of Mixxx source patches (`mixxx-patch/`), a Pi USB
auto-mount layer (`pi/`), and prebuilt arm64 packages.

## Screenshot
![skin_preview](https://github.com/timewasternl/Pioneered/blob/master/skin_preview.png?raw=true)

## Features

### Skin (upstream + this fork)
* Tabbed view: Overview, Browse and Samples — inspired by the Pioneer XDJ interface
* Fully scalable, minimum resolution 480x420; tiny resource footprint
* Small waveform overviews at the bottom, keylock and quantize buttons
* BeatFX section with three effect units and level meters
* Touch-optimized Browse tab: two-pane playlist/track view, LOAD 1 / LOAD 2
  buttons, one-tap **USB A / USB B** source buttons

### Patched Mixxx (mixxx-patch/, prebuilt in Releases)
* **USB workflow like a real XDJ**
  * One-tap browse of rekordbox USB sticks (USB A / USB B buttons)
  * Hold a USB button ~5 s to safely eject: playing decks block the eject
    ("USB LOCKED"), paused decks are auto-unloaded, and the stick is unmounted
    so it is safe to pull
  * Sticks plugged in after startup are picked up automatically
* **Library built for a small touch screen**
  * "Tracks visible in list" zoom preference (default 8 rows): row height *and*
    font scale to fit exactly N tracks in the list
  * Fixed column set — **#, Title, Artist, Key, Duration** — with proportional
    widths that always fill the screen
  * Track lists always open sorted by # ascending
  * **Key traffic light**: the Key cell lights up green when the track is
    Camelot-compatible with the master deck (the deck that started playing
    most recently); keys are always shown as note names (Am, F♯m, …)
* **Waveforms & playback like Pioneer gear**
  * Rekordbox-style **red bar markers** on the beatgrid (first beat of every
    bar), with the grid correctly anchored on rekordbox's "1"
  * Waveform frequency bands are not affected by the EQ knobs (a closed EQ
    still shows the track's content, like on CDJs)
  * Loop-out with no loop-in starts the loop from the cue point
  * Filter effect with a Pioneer-style response curve and gentler default Q
* **Hardware robustness**
  * DDJ-400 (or any PortMidi controller) **auto-reconnects** if the USB
    connection drops — no trip to the preferences, no restart
  * On track load the deck tempo jumps to the physical position of the DDJ-400
    tempo fader (no more dead slider until you cross the old value)
* **Reliability**
  * Hardened rekordbox database parser: corrupt/truncated `EXPORT.PDB` files
    (e.g. from pulling a stick mid-write) can no longer crash Mixxx
  * **Hold-to-restart**: hold either on-screen LOAD button for 7 s (it blinks
    faster and faster, like the USB eject hold) to kill and relaunch Mixxx —
    recover a misbehaving session from the touchscreen, no keyboard needed

## Requirements

* Raspberry Pi 4B (or better) running Raspberry Pi OS 64-bit **trixie**
  (the packages are built against Debian trixie's Mixxx 2.5.0 source)
* A touch display (the skin is designed for small screens)
* Pioneer DDJ-400 (other controllers work, minus the DDJ-400-specific tempo
  fader sync)
* USB sticks exported from rekordbox

## Installation

### 1. Patched Mixxx packages

Download `mixxx_*.deb`, `mixxx-data_*.deb` (and optionally `mixxx-dbgsym_*.deb`
for crash diagnostics) from the
[**Releases page**](https://github.com/ogg755/Pioneered/releases), copy them to
the Pi, then:

```bash
sudo apt-mark unhold mixxx mixxx-data 2>/dev/null || true
sudo apt install -y ./mixxx_*.deb ./mixxx-data_*.deb ./mixxx-dbgsym_*.deb
sudo apt-mark hold mixxx mixxx-data   # stop apt upgrades replacing the patched build
dpkg -s mixxx | grep Version          # should show a +usbbrowse.rNN suffix
```

### 2. Skin

```bash
git clone https://github.com/ogg755/Pioneered.git
cp -r Pioneered ~/.mixxx/skins/
```

Start Mixxx and select **Pioneered** in *Preferences → Interface*.
Library sizing is automatic ("Tracks visible in list", *Preferences →
Library*, default 8 — set to Off for the stock manual row height).

### 3. USB auto-mount layer

The skin's USB A/B buttons expect sticks at `/media/USBA` and `/media/USBB`.
Install the udev/systemd machinery from `pi/`:

```bash
sudo cp pi/99-usb-automount.rules /etc/udev/rules.d/
sudo cp pi/usb-mount@.service /etc/systemd/system/
sudo cp pi/usb-mount.sh pi/usb-umount.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/usb-mount.sh /usr/local/bin/usb-umount.sh
sudo udevadm control --reload && sudo systemctl daemon-reload
```

### 4. Eject permission

Hold-to-eject runs `sudo umount` from inside Mixxx, which needs a passwordless
sudoers rule (replace `youruser`):

```bash
echo 'youruser ALL=(ALL) NOPASSWD: /usr/bin/umount /media/USBA, /usr/bin/umount /media/USBB' \
  | sudo tee /etc/sudoers.d/mixxx-usb-eject
```

### 5. Controller

Plug in the DDJ-400 and enable it in *Preferences → Controllers* with the
built-in **Pioneer DDJ-400** mapping (the patched `mixxx-data` package contains
the tempo-fader-sync version). Thanks to the reconnect watchdog this is a
one-time setup: replugging or plugging in after startup reconnects
automatically.

## Using the console

* **Short-press USB A/B**: browse that stick (first press after inserting a
  stick primes the scan — press again). **Hold ~5 s**: eject; safe to pull when
  its playlists disappear. "USB LOCKED" means a deck is *playing* from that
  stick — pause it first.
* **Key traffic light**: green Key cells are harmonically compatible with the
  deck you started most recently. Pause everything and the lights go out.
* **Zoom**: *Preferences → Library → Tracks visible in list*.

## Building the packages yourself

The GitHub Actions workflow `build-mixxx-deb.yml` (manual dispatch, `master`
branch) fetches Debian trixie's `mixxx` source, applies the patch series from
`mixxx-patch/` in order (usb-browse → pdb-corruption-hardening → xdj-behavior →
library-ui → xdj-hardware), and uploads the three .debs as an artifact. See
`mixxx-patch/VERSION.md` for the patch changelog and `docs/pi-deploy.md` for
deploy notes.

## Crash diagnostics

```bash
sudo apt install -y systemd-coredump gdb   # one-time, plus the mixxx-dbgsym deb
coredumpctl list mixxx
DEBUGINFOD_URLS="https://debuginfod.debian.net" coredumpctl gdb mixxx
```

## Contributors
* [timewasternl](https://github.com/timewasternl) (original skin)
* [GorgiAstro](https://github.com/GorgiAstro)
* [BvOBart](https://github.com/bvobart)
* [bencejuhaasz](https://github.com/bencejuhaasz)
* [ogg755](https://github.com/ogg755) (Mixxx patch series, Pi integration)

## License

GPL — see [LICENSE](LICENSE). Mixxx itself is GPL-2.0+; the patches in
`mixxx-patch/` are derivative works of Mixxx source and carry the same license.
