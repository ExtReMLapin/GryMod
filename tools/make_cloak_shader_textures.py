"""Writes the textures the camouflage's pixel shader reads, from the originals that tools/extract_cloak_textures.py puts in its `dds` folder.

    python tools/make_cloak_shader_textures.py DDS_DIR [--out-dir materials/grymod/cloak]

- noise3d.vtf          the original's 128 cube of noise, a real VOLUME texture (one 8-bit channel, repeating, data: no sRGB, no mips);
- spark_profile.vtf    the 256 x 1 colours of cloak_sparks, read at three offsets of the noise (repeating along the row).

The shader itself is shaders/src/grymod_cloak_*.hlsl (tools/build_shaders.py compiles it); the material that runs it is made by
lua/grymod/client/cl_cloak_shader.lua. Both textures are DATA the shader calculates with, so that material reads them without the engine's sRGB
conversion ($linearread_*). Holds no resource of the game.

Needs Python 3.12 and numpy.
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")))

from tools import extract_cloak_textures as ect  # noqa: E402
from tools.flash2lua import vtf  # noqa: E402


def noise_volume_bytes(volume):
    """The VTF of a (depth, height, width, 4) volume: only its first channel is kept (the noise), repeating, no mips."""
    return vtf.vtf_bytes(volume, "i8", srgb=False, mips=False, clamp="")


def spark_profile_bytes(profile):
    """The VTF of the (1, 256, 4) spark profile: colours that repeat along the row, no mips, no sRGB."""
    return vtf.vtf_bytes(profile, "rgba8888", srgb=False, mips=False, clamp="t")


def load_inputs(dds_dir):
    def read(name):
        with open(os.path.join(dds_dir, name), "rb") as f:
            return ect.decode_dds(f.read())[1]

    return read("noise3d.dds"), read("cloak_sparks.dds")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("dds_dir")
    parser.add_argument("--out-dir", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "materials", "grymod", "cloak"))
    args = parser.parse_args(argv)

    volume, profile = load_inputs(args.dds_dir)
    os.makedirs(args.out_dir, exist_ok=True)
    files = {"noise3d.vtf": noise_volume_bytes(volume), "spark_profile.vtf": spark_profile_bytes(profile)}
    for name, data in files.items():
        with open(os.path.join(args.out_dir, name), "wb") as out:
            out.write(data)
        print("%s: %d bytes" % (os.path.normpath(os.path.join(args.out_dir, name)), len(data)))

    return 0


if __name__ == "__main__":
    sys.exit(main())
