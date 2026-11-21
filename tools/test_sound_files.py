"""Checks the WAV files the addon ships (sound/grymod/**) against what the Source engine accepts for EmitSound:

    python tools/test_sound_files.py [folder]

(the folder defaults to sound/grymod of the addon)

The engine refuses a WAV whose rate is not 11025, 22050 or 44100 ("Invalid sample rate (32000) for sound ...") and the
sound then does not play. Also checked: plain PCM (format tag 1, not WAVE_FORMAT_EXTENSIBLE, not ADPCM), 16 bits, one or
two channels, a RIFF/WAVE header whose chunk sizes fit the file, a data chunk that is a whole number of frames and at
least one frame. Exit code 1 and one line per problem on failure.
"""
import glob
import os
import struct
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sound", "grymod")
RATES = (11025, 22050, 44100)


def problems(path):
    data = open(path, "rb").read()
    found = []

    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return ["not a RIFF/WAVE file"]

    if struct.unpack("<I", data[4:8])[0] + 8 != len(data):
        found.append("the RIFF size (%d) does not match the file (%d)" % (struct.unpack("<I", data[4:8])[0] + 8, len(data)))

    pos, fmt, pcm = 12, None, None

    while pos + 8 <= len(data):
        tag, size = struct.unpack("<4sI", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + size]

        if tag == b"fmt ":
            fmt = struct.unpack("<HHIIHH", body[:16])
            fmt_size = size
        elif tag == b"data":
            pcm = body

            if pos + 8 + size > len(data):
                found.append("the data chunk is cut")

        pos += 8 + size + (size & 1)

    if fmt is None or pcm is None:
        return found + ["no fmt or no data chunk"]

    tag, channels, rate, byte_rate, align, bits = fmt

    if tag != 1:
        found.append("format tag %d: only plain PCM (1) is accepted (no extensible, no ADPCM)" % tag)

    if fmt_size != 16:
        found.append("fmt chunk of %d bytes (16 expected)" % fmt_size)

    if rate not in RATES:
        found.append("invalid sample rate (%d): must be 44100, 22050 or 11025" % rate)

    if bits != 16:
        found.append("%d bits: 16 expected" % bits)

    if channels not in (1, 2):
        found.append("%d channels: 1 or 2 expected" % channels)

    if channels * bits // 8 != align or byte_rate != rate * align:
        found.append("inconsistent block align or byte rate")

    if align and len(pcm) % align:
        found.append("the data is not a whole number of frames")

    if not pcm:
        found.append("no samples")

    return found


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else ROOT
    files = sorted(glob.glob(os.path.join(root, "**", "*.wav"), recursive=True))
    bad = 0

    if not files:
        print("no WAV under", os.path.normpath(root))

        return 1

    for path in files:
        for text in problems(path):
            bad += 1
            print("%s: %s" % (os.path.relpath(path, root).replace(os.sep, "/"), text))

    print("%d files, %d problems" % (len(files), bad))

    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
