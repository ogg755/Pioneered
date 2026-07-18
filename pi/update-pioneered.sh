#!/bin/bash
# One-shot Pioneered updater for the XDJ400 Pi.
#
#   sudo ./update-pioneered.sh          # install the latest GitHub release
#   sudo ./update-pioneered.sh v2.5.0-r18   # install a specific release (also allows rollback)
#
# Fetches the release's three Mixxx debs and the matching skin from
# github.com/ogg755/Pioneered, installs them non-interactively, re-holds the
# packages, then reboots (Ctrl-C during the countdown to skip the reboot).
set -euo pipefail

REPO="ogg755/Pioneered"

# Root is needed for apt; the skin belongs to the login user.
if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi
SKIN_USER="${SUDO_USER:-rpims}"
SKIN_HOME="$(getent passwd "$SKIN_USER" | cut -d: -f6)"
if [[ -z "$SKIN_HOME" ]]; then
    echo "ERROR: cannot resolve home directory for user '$SKIN_USER'" >&2
    exit 1
fi

WORKDIR="$(mktemp -d /tmp/pioneered-update.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

# --- Resolve release ---------------------------------------------------------
TAG="${1:-}"
if [[ -n "$TAG" ]]; then
    API_URL="https://api.github.com/repos/$REPO/releases/tags/$TAG"
else
    API_URL="https://api.github.com/repos/$REPO/releases/latest"
fi
echo "==> Querying $API_URL"
curl -fsSL "$API_URL" -o release.json

TAG="$(grep -m1 -o '"tag_name": *"[^"]*"' release.json | sed 's/.*: *"//;s/"//')"
if [[ -z "$TAG" ]]; then
    echo "ERROR: could not resolve a release (no tag_name in API response)" >&2
    exit 1
fi
echo "==> Release: $TAG"

mapfile -t DEB_URLS < <(grep -o '"browser_download_url": *"[^"]*\.deb"' release.json \
        | sed 's/.*: *"//;s/"//')
if [[ ${#DEB_URLS[@]} -lt 3 ]]; then
    echo "ERROR: release $TAG has ${#DEB_URLS[@]} .deb assets (expected 3:" \
         "mixxx, mixxx-data, mixxx-dbgsym). Was the release published with debs attached?" >&2
    exit 1
fi

# --- Download ----------------------------------------------------------------
for url in "${DEB_URLS[@]}"; do
    echo "==> Downloading ${url##*/}"
    curl -fL --retry 3 -o "${url##*/}" "$url"
done

echo "==> Downloading skin source for $TAG"
curl -fL --retry 3 -o skin.tar.gz "https://github.com/$REPO/archive/refs/tags/$TAG.tar.gz"
tar -xzf skin.tar.gz          # extracts to Pioneered-<tag without v>/
SKIN_SRC="$(find . -maxdepth 1 -type d -name 'Pioneered-*' | head -1)"
if [[ -z "$SKIN_SRC" || ! -f "$SKIN_SRC/skin.xml" ]]; then
    echo "ERROR: skin source missing skin.xml after extraction" >&2
    exit 1
fi

# --- Install debs ------------------------------------------------------------
echo "==> Installing Mixxx packages"
apt-mark unhold mixxx mixxx-data mixxx-dbgsym 2>/dev/null || true
DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades \
    "$WORKDIR"/mixxx_*_arm64.deb \
    "$WORKDIR"/mixxx-data_*_all.deb \
    "$WORKDIR"/mixxx-dbgsym_*_arm64.deb
apt-mark hold mixxx mixxx-data mixxx-dbgsym 2>/dev/null || true

# --- Install skin ------------------------------------------------------------
echo "==> Installing skin to $SKIN_HOME/.mixxx/skins/Pioneered"
mkdir -p "$SKIN_HOME/.mixxx/skins"
rm -rf "$SKIN_HOME/.mixxx/skins/Pioneered"
cp -r "$SKIN_SRC" "$SKIN_HOME/.mixxx/skins/Pioneered"
chown -R "$SKIN_USER:" "$SKIN_HOME/.mixxx/skins/Pioneered"

# --- Report + reboot ---------------------------------------------------------
echo
echo "==> Installed: $(dpkg-query -W -f='${Package} ${Version}\n' mixxx)"
echo "==> Skin updated from release $TAG"
echo
echo "Rebooting in 10 seconds so Mixxx restarts on the new build."
echo "Press Ctrl-C to skip the reboot (then restart Mixxx yourself)."
sleep 10
reboot
