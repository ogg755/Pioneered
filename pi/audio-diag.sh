#!/bin/bash
# Diagnoses the DDJ-400 headphone (cue, ch 3-4) distortion on the Pi's raw-ALSA
# path, and locates whether the corruption is above ALSA (Mixxx's cue bus) or
# in the ALSA/PortAudio sample path.
#
# The crux this script is built around:
#   MASTER (ch 1-2) plays clean and loud through raw hw:.
#   CUE    (ch 3-4) distorts through the SAME raw hw: stream / format / DAC.
# Because both channel pairs ride one interleaved buffer, a whole-stream format
# bug is unlikely (it would smear ch 1-2 too). That leaves two suspects with
# different fixes:
#   (A) Mixxx is writing a hot/corrupt signal INTO ch 3-4 (cue bus, digital).
#   (B) The S24_3LE 4-channel interleave corrupts only the TRAILING channel
#       pair on PortAudio's raw-hw path (3-byte packing misalignment reads as
#       both wrong-level and harsh -- matches "was quiet, now distorts"). The
#       laptop escapes it by playing through a converted plug/PulseAudio path.
#
# The 'matrix' mode injects a KNOWN-GOOD tone straight into the hardware with
# aplay -- Mixxx completely out of the loop -- at -6 dBFS (half scale). At -6
# dBFS nothing can legitimately clip, so ANY distortion is corruption, not
# overdrive. It sweeps {S16_LE, S24_3LE} x {ch1, ch3, ch4} so you can compare
# the leading pair against the trailing pair in each format.
#
# Facts baked in (from this card's stream0): 44100 Hz only; formats S16_LE and
# S24_3LE; 4 channels; ALSA labels them FL FR FC LFE (cosmetic for raw hw --
# they do NOT remap on hw:, only the plug layer acts on them, which is why
# PA_ALSA_PLUGHW=1 wrongly applied surround/LFE downmixing). No hardware mixer
# controls exist, so there is nothing to un-attenuate.
#
# Usage:
#   ./audio-diag.sh            # report: card, stream0 caps, mixer controls
#   ./audio-diag.sh matrix     # inject -6 dBFS tones: {S16,S24_3LE} x {ch1,3,4}
#                              # Quit Mixxx first (the card is exclusive-access).
#
# Reading the matrix (compare ch1 vs ch3/ch4 within EACH format):
#   * ch3/ch4 CLEAN in both formats  -> hardware + ALSA path are innocent. The
#       distortion is suspect (A): Mixxx's cue bus. Next: in Mixxx, drop
#       [Master],headGain toward unity, check the headphone CLIP light, and
#       confirm [ChannelN],pregain / cue pregain are not stacking. The signal,
#       not the transport, is hot.
#   * ch3/ch4 distort ONLY in S24_3LE (clean in S16_LE) -> suspect (B): the
#       24-bit packed path corrupts the trailing pair. Fix = force the whole
#       card to S16_LE for every client (see the "Forcing S16_LE" note the
#       script prints at the end), so PortAudio cannot pick S24_3LE.
#   * ch3/ch4 distort in BOTH formats (ch1 clean) -> the trailing DAC pair is
#       being driven wrong at the driver level regardless of format: likely a
#       snd-usb-audio quirk for this interface. Capture `dmesg | grep -i snd`
#       and the aplay --dump-hw-params below and bring them back.
#   * ch1 ALSO distorts -> not channel-specific; re-check cabling/power and the
#       stream0 caps printed by the no-arg run.

set -u

CARD=$(awk '/DDJ/{print $1; exit}' /proc/asound/cards)
if [ -z "$CARD" ]; then
    echo "DDJ-400 not found in /proc/asound/cards:" >&2
    cat /proc/asound/cards >&2
    exit 1
fi
echo "== DDJ-400 is ALSA card $CARD (device hw:$CARD,0)"

# --- tone generator: raw interleaved 4-ch PCM to stdout ---------------------
# args: <format S16_LE|S24_3LE> <channel 1..4> <freq Hz> <secs>
# One channel carries a -6 dBFS sine; the other three are digital silence.
gen_tone() {
    python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys, struct, math
fmt, ch, freq, secs = sys.argv[1], int(sys.argv[2]) - 1, float(sys.argv[3]), float(sys.argv[4])
rate, chans, amp = 44100, 4, 0.5  # amp 0.5 = -6 dBFS: cannot clip
out = sys.stdout.buffer
for n in range(int(rate * secs)):
    s = amp * math.sin(2 * math.pi * freq * n / rate)
    for c in range(chans):
        v = s if c == ch else 0.0
        if fmt == "S16_LE":
            out.write(struct.pack("<h", int(v * 32767)))
        else:  # S24_3LE: low 3 bytes of a little-endian 32-bit int
            out.write(struct.pack("<i", int(v * 8388607))[0:3])
PY
}

if [ "${1:-}" = "matrix" ]; then
    if pgrep -x mixxx >/dev/null; then
        echo "Mixxx is running and holds the card exclusively. Quit it first." >&2
        exit 1
    fi
    command -v python3 >/dev/null || { echo "python3 required for tone gen." >&2; exit 1; }
    command -v aplay   >/dev/null || { echo "aplay (alsa-utils) required." >&2; exit 1; }

    echo
    echo "== What the hardware will actually accept for a 4-ch stream:"
    aplay -D "hw:$CARD,0" --dump-hw-params -d 1 /dev/zero 2>&1 | sed -n '1,40p' || true

    echo
    echo "== Injecting -6 dBFS 440 Hz tones straight to hw:$CARD,0 (Mixxx bypassed)."
    echo "   Set the controller's HEADPHONES MIX toward CUE to hear ch 3/4."
    echo "   Listen for: clean vs. distorted, and loud vs. quiet. -6 dBFS CANNOT"
    echo "   clip, so any distortion is corruption in the path, not overdrive."
    for fmt in S16_LE S24_3LE; do
        for ch in 1 3 4; do
            case $ch in
                1) where="MASTER  L (reference, should be clean)";;
                3) where="PHONES  L (cue)";;
                4) where="PHONES  R (cue)";;
            esac
            echo
            echo "-- $fmt  ch$ch  $where"
            if ! gen_tone "$fmt" "$ch" 440 2 | \
                 aplay -D "hw:$CARD,0" -c 4 -r 44100 -f "$fmt" -t raw -q; then
                echo "   !! aplay failed for $fmt ch$ch -- the card rejected this"
                echo "      format/config; note it, that itself is a finding."
            fi
        done
    done

    echo
    echo "== Interpretation: compare ch1 against ch3/ch4 WITHIN each format."
    echo "   See this script's header for the full decision table."
    echo
    echo "== Forcing S16_LE (only if S24_3LE is the one that distorts):"
    echo "   Mixxx opens hw: directly, so a plug/dmix .asoundrc it never selects"
    echo "   won't help. Instead expose a NAMED pcm that IS S16 and is 1:1 (no"
    echo "   FC/LFE surround routing), then pick it as the Mixxx output device."
    echo "   Put in ~/.asoundrc (then choose 'ddj_s16' in Mixxx Sound Hardware):"
    echo
    echo "     pcm.ddj_s16 {"
    echo "       type plug"
    echo "       slave {"
    echo "         pcm \"hw:$CARD,0\""
    echo "         format S16_LE"
    echo "         channels 4"
    echo "         rate 44100"
    echo "       }"
    echo "       ttable.0.0 1  ttable.1.1 1  ttable.2.2 1  ttable.3.3 1"
    echo "     }"
    echo
    echo "   The explicit 1:1 ttable stops ALSA from treating ch3/4 as FC/LFE"
    echo "   (the surround/subwoofer downmix that made PA_ALSA_PLUGHW worse)."
    exit 0
fi

# --- report mode ------------------------------------------------------------
echo
echo "== USB stream capabilities (rates/formats the interface really takes):"
cat "/proc/asound/card$CARD/stream0" 2>/dev/null || echo "(no stream0 info)"

echo
echo "== Mixer controls (expected: none on this interface):"
amixer -c "$CARD" contents 2>&1 | sed -n '1,40p'
echo "   (if truly empty, there is no hardware volume to raise -- the fix is"
echo "    downstream, in the sample path or Mixxx's cue bus, not here.)"

echo
echo "Next: './audio-diag.sh matrix' with Mixxx closed. Compare ch1 vs ch3/ch4"
echo "in S16_LE and S24_3LE to localize the corruption. See the header table."
