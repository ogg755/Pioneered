# Pi Mixxx build facts (source of truth for the patch + CI)

- Installed package: mixxx 2.5.0 (Debian source package `mixxx_2.5.0+dfsg-3`; arm64 binary in the archive is the binNMU `2.5.0+dfsg-3+b1`)
- OS: Raspberry Pi OS 64-bit, Debian codename: trixie
- Arch: arm64
- Source pool: http://deb.debian.org/debian/pool/main/m/mixxx/
  - Files: `mixxx_2.5.0+dfsg-3.dsc`, `mixxx_2.5.0+dfsg.orig.tar.xz`, `mixxx_2.5.0+dfsg-3.debian.tar.xz` (SHA256 of both tarballs verified against the .dsc)
- Package origin: Debian archive (deb.debian.org), not the Raspberry Pi archive — Raspberry Pi OS arm64 pulls `mixxx` from Debian; archive.raspberrypi.com does not carry it.
- Debian packaging patches (`debian/patches/series`): `0001-disable_soundsourcem4a.patch`, `0002-desktop_file.patch`, `0004-remove_inappropriate_arm_flags.patch`, `0005-disable_soundproxy_test.patch` — **none touch `src/library`**, so our patch applies cleanly on top of them.
- Source tree verified after extraction (in `..\mixxx-src\mixxx-2.5.0`): `src/library/librarycontrol.cpp`, `src/library/librarycontrol.h`, `src/library/library.h` all present.
- Queried: 2026-07-08

> **Caveat:** Installed version 2.5.0 confirmed by user (SSH to the Pi was
> unavailable); Debian codename **trixie** inferred from archive contents —
> packages.debian.org/trixie/mixxx shows `2.5.0+dfsg-3`, and it is the only
> Debian release shipping a 2.5.0 build (bookworm has 2.3.3, sid/forky have
> 2.5.6). **Re-verify with `apt policy mixxx` on the Pi at deploy time
> (Task 7) before installing the built .deb.**
