"""Extracts the suit, HUD, quick menu, binocular and underwater sounds of GryMod from the Crysis SP demo, at their original quality.

    python tools/extract_sounds.py "C:/Program Files (x86)/Electronic Arts/Crytek/Crysis SP Demo/Game" --ffmpeg C:/ext/ffmpeg.exe

It reads Game/Sounds.pak (FMOD FSB3 banks: interface_suit, interface_bank00, physics_bullets) and Localized/english.pak (the
suit voices, MPEG-1 Layer II) and writes sound/grymod/{suit,hud,menu,binoculars,water}/*.wav under the addon (or --out).
The underwater sounds come from physics_player_foley.fsb (ADPCM) and environment_amb_natural.fsb (the ambience loop is
MPEG-1 Layer II inside the bank: its frames are decoded as they are, 383 frames of 1152 samples = the header's sample count).
Needs numpy and scipy (only for the reboot sound, whose two layers are summed at 44.1 kHz) and ffmpeg (the voices and the
ambience loop).
Nothing from the game is kept in the repository except the WAV files this writes.

The banks hold IMA ADPCM: blocks of 36 bytes per channel, the four-byte groups of the channels interleaved. A block holds
64 samples (the header's predictor is the first one, then 63 nibbles; the 64th nibble is padding): the sample count of
every FSB header is a multiple of 64 and the loops are exactly 10.000 s with it. Decoders that read 65 samples per
block (the usual MS IMA layout, and the tool the first GryMod sounds came from) play 1.56 percent too slow and insert a
sample in every block. See docs/superpowers/plans/2026-11-21-audio-provenance.md.
"""
import argparse
import io
import math
import os
import struct
import subprocess
import sys
import tempfile
import wave
import zipfile

import numpy as np
from scipy import signal

IDX = [-1, -1, -1, -1, 2, 4, 6, 8]
STEP = [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97,
        107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
        876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428,
        4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350,
        22385, 24623, 27086, 29794, 32767]


def parse_fsb(data):
    """The samples of an FSB3 bank: dicts with name, frames, rate, channels, bytes."""
    magic, count, header_size = struct.unpack("<4sII", data[:12])
    assert magic == b"FSB3", magic
    off, headers = 24, []

    for _ in range(count):
        size, = struct.unpack("<H", data[off:off + 2])
        name = data[off + 2:off + 32].split(b"\0")[0].decode("latin1")
        frames, packed, _, _, mode, rate = struct.unpack("<IIIIII", data[off + 32:off + 56])
        headers.append(dict(name=name, frames=frames, packed=packed, rate=rate, channels=2 if mode & 0x40 else 1))
        off += size

    pos = 24 + header_size

    for h in headers:
        h["bytes"] = data[pos:pos + h["packed"]]
        pos += h["packed"]

    return headers


def decode_ima(h):
    """16-bit samples (frames x channels) of a sample, 64 per block and channel."""
    ch, data = h["channels"], h["bytes"]
    block = 36 * ch
    out = np.zeros((len(data) // block * 64, ch), dtype=np.int16)

    for b in range(len(data) // block):
        blk = data[b * block:(b + 1) * block]

        for c in range(ch):
            pred, idx = struct.unpack("<hB", blk[c * 4:c * 4 + 3])
            idx = min(idx, 88)
            samples = [pred]

            for g in range((block - 4 * ch) // (4 * ch)):
                start = 4 * ch + (g * ch + c) * 4

                for byte in blk[start:start + 4]:
                    for n in (byte & 15, byte >> 4):
                        diff = STEP[idx] >> 3

                        if n & 1:
                            diff += STEP[idx] >> 2

                        if n & 2:
                            diff += STEP[idx] >> 1

                        if n & 4:
                            diff += STEP[idx]

                        pred = max(-32768, min(32767, pred + (-diff if n & 8 else diff)))
                        idx = max(0, min(88, idx + IDX[n & 7]))
                        samples.append(pred)

            out[b * 64:(b + 1) * 64, c] = samples[:64]

    return out[:h["frames"]]


def write_wav(path, pcm, rate):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    w = wave.open(path, "wb")
    w.setnchannels(pcm.shape[1])
    w.setsampwidth(2)
    w.setframerate(rate)
    w.writeframes(pcm.astype("<i2").tobytes())
    w.close()


# (published name, bank, sample name in the bank): the shipped name is the game's, in lower case
SUIT = [
    ("suit_armor_108", "interface_suit", "suit_armor_108.wav"),
    ("suit_speed_activate_07_good", "interface_suit", "suit_speed_activate_07_good.wa"),
    ("suit_strength_101_r", "interface_suit", "suit_strength_101_r.wav"),
    ("suit_cloak_chameleon_101_r", "interface_suit", "suit_cloak_chameleon_101_r.wav"),
    ("suit_sound_137", "interface_suit", "suit_sound_137.wav"),
    ("servo_speed_loop_01c", "interface_suit", "servo_speed_loop_01c.wav"),
    ("servo_speed_loop_01_underwater", "interface_suit", "servo_speed_loop_01_underwater"),
    ("servo_speed_stop_fp_2", "interface_suit", "servo_speed_stop_fp_2.wav"),
    ("servo_speed_stop_01_underwater", "interface_suit", "servo_speed_stop_01_underwater"),
    ("suit_medical_use_new", "interface_suit", "suit_medical_use_new.wav"),
    ("suit_usage_error", "interface_suit", "suit_usage_error.wav"),
]
ARMOR_HITS = (2, 3, 4, 5, 6, 7, 9, 10, 11, 13, 14, 15, 16)
VOICES = ("suit_maximum_armor", "suit_maximum_speed", "suit_maximum_strength", "suit_modification_engaged",
          "suit_energy_critical")
HUD = [
    ("hud_activate_01", "interface_bank00", "hud_activate_01.wav"),
    ("hud_malfunction_hit", "interface_bank00", "hud_malfunction_hit.wav"),
]
MENU = [
    ("modification_menu_appear", "interface_suit", "modification_menu_appear.WAV"),
    ("modification_menu_dissapear", "interface_suit", "modification_menu_dissapear.WAV"),
    ("preset_navigation_beep_02", "interface_suit", "preset_navigation_beep_02.WAV"),
    ("temperature_beep", "interface_suit", "temperature_beep.WAV"),
]
WATER = ([("underwater_feedback_%02d" % n, "physics_player_foley", "underwater_feedback_%02d.wav" % n) for n in range(1, 6)]
         + [("drown_feedback_%02d" % n, "physics_player_foley", "drown_feedback_%02d.wav" % n) for n in range(1, 8)]
         + [("dive_in_slow_01", "physics_player_foley", "dive_in_slow_01.wav")]
         + [("dive_in_fast_%02d" % n, "physics_player_foley", "dive_in_fast_%02d.wav" % n) for n in range(1, 4)]
         + [("dive_out", "physics_player_foley", "dive_out.wav")])
AMBIENCE = ("ambience_underwater_loop_02", "environment_amb_natural", "ambience_underwater_loop_02.wa")
BINOCULARS = [(n, "interface_suit", n + ".wav") for n in (
    "binocular_select", "binocular_deselect", "binocular_ambience", "binocular_zoom_in", "binocular_zoom_out",
    "binocular_tagged")]

# the hud_reboot event plays two layers together: hud_reboot at 0.253906 and hud_reboot_oneshot at 1.0. Their sum peaks
# at 1.103 of full scale, so the file is stored 1 dB lower (the mix table gives it -11 dB instead of -12).
REBOOT_LAYER = 0.253906
REBOOT_HEADROOM = 10 ** (-1 / 20)


def to_44100(pcm, rate):
    x = pcm.astype(np.float64) / 32768

    if rate != 44100:
        g = math.gcd(44100, rate)
        x = signal.resample_poly(x, 44100 // g, rate // g, axis=0)

    return x


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("game", help="the demo's Game folder (with Sounds.pak and Localized/english.pak)")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    args = parser.parse_args()
    sounds = zipfile.ZipFile(os.path.join(args.game, "Sounds.pak"))
    english = zipfile.ZipFile(os.path.join(args.game, "Localized", "english.pak"))
    banks = {}

    def bank(name):
        if name not in banks:
            folder = "physics" if name.startswith("physics") else "environment" if name.startswith("environment") else "interface"
            banks[name] = {h["name"]: h for h in parse_fsb(sounds.read("Sounds/%s/%s.fsb" % (folder, name)))}

        return banks[name]

    def sample(bank_name, name):
        samples = bank(bank_name)
        # the bank cuts the names at 30 characters
        return samples[next(n for n in samples if n.lower() == name.lower() or (len(n) >= 29 and name.lower().startswith(n.lower())))]

    def save(folder, name, pcm, rate):
        path = os.path.join(args.out, "sound", "grymod", folder, name + ".wav")
        write_wav(path, pcm, rate)
        print("%-70s %7d frames %5d Hz %d ch" % (os.path.relpath(path, args.out), pcm.shape[0], rate, pcm.shape[1]))

    def plain(folder, entries):
        for name, bank_name, source in entries:
            h = sample(bank_name, source)
            save(folder, name, decode_ima(h), h["rate"])

    plain("suit", SUIT)

    for n in ARMOR_HITS:
        name = "suit_bullet_impact_fp_%02d" % n
        h = sample("physics_bullets", name + ".wav")
        save("suit", name, decode_ima(h), h["rate"])

    for name in VOICES:
        with tempfile.TemporaryDirectory() as tmp:
            mp2 = os.path.join(tmp, name + ".mp2")
            wav = os.path.join(tmp, name + ".wav")
            open(mp2, "wb").write(english.read("Languages/dialog/suit/male/%s.mp2" % name))
            subprocess.run([args.ffmpeg, "-v", "error", "-y", "-i", mp2, "-acodec", "pcm_s16le", wav], check=True)
            w = wave.open(wav)
            pcm = np.frombuffer(w.readframes(w.getnframes()), "<i2").reshape(-1, w.getnchannels())
            rate = w.getframerate()
            w.close()
            save("suit", name, pcm, rate)

    plain("hud", HUD)
    layer = to_44100(decode_ima(sample("interface_bank00", "hud_reboot.wav")), 44100) * REBOOT_LAYER
    oneshot_h = sample("interface_bank00", "hud_reboot_oneshot.wav")
    oneshot = to_44100(decode_ima(oneshot_h), oneshot_h["rate"])
    mix = np.zeros((max(len(layer), len(oneshot)), 2))
    mix[:len(layer)] += layer
    mix[:len(oneshot)] += oneshot
    mix *= REBOOT_HEADROOM
    save("hud", "hud_reboot", np.clip(np.round(mix * 32768), -32768, 32767).astype(np.int16), 44100)
    plain("menu", MENU)
    plain("binoculars", BINOCULARS)
    plain("water", WATER)
    name, bank_name, source = AMBIENCE
    h = sample(bank_name, source)

    with tempfile.TemporaryDirectory() as tmp:
        mp2 = os.path.join(tmp, "loop.mp2")
        wav = os.path.join(tmp, "loop.wav")
        open(mp2, "wb").write(h["bytes"])
        subprocess.run([args.ffmpeg, "-v", "error", "-y", "-i", mp2, "-acodec", "pcm_s16le", wav], check=True)
        w = wave.open(wav)
        pcm = np.frombuffer(w.readframes(w.getnframes()), "<i2").reshape(-1, w.getnchannels())
        rate = w.getframerate()
        w.close()

    assert pcm.shape[0] == h["frames"] and rate == h["rate"], (pcm.shape, rate, h["frames"], h["rate"])
    save("water", name, pcm, rate)


if __name__ == "__main__":
    sys.exit(main())
