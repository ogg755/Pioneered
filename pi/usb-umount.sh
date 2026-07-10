#!/bin/bash
# Unmounts whichever /media/USB* slot holds the given partition.
# Invoked by usb-mount@.service on stop (device unplugged).
DEVICE="$1"
for mp in /media/USBA /media/USBB; do
    # --mountpoint (not --target): --target resolves any path to the mount
    # containing it, so a non-mounted slot would report the root filesystem
    src=$(findmnt -n -o SOURCE --mountpoint "$mp" 2>/dev/null)
    if [ "$src" = "/dev/$DEVICE" ]; then
        umount -l "$mp" && echo "Unmounted $mp"
    fi
done
