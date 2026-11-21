"""Compiles the addon's shaders (the .hlsl next to this file) into shaders/fxc/*.vcs with ShaderCompile (https://github.com/SCell555/ShaderCompile).

    python dev_resources/shaders/build_shaders.py --compiler PATH/ShaderCompile.exe --headers DIR_WITH_common_ps_fxc.h [--out shaders/fxc] [--suffix _r2]

Only the developer (and the CI) compiles: the players get the .vcs. Neither the compiler nor the engine's shader headers (common_ps_fxc.h,
common_vs_fxc.h, ... of the Source SDK 2013, as the guide https://github.com/meetric1/gmod_shader_guide carries them) are in this repository: pass
the folder that holds them. The file name tells the stage and the model: name_ps30.hlsl, name_vs30.hlsl (pixel and vertex shader 3.0), name_ps20b.hlsl.

The game takes a shader's code the first time it loads the name and keeps it until it is closed: to try a change without restarting it, build with
--suffix (the output files and the $pixshader / $vertexshader names of the material then carry it).
"""
import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
NAME = re.compile(r"^(?P<base>.+)_(?P<stage>ps|vs)(?P<model>30|20b|2x)\.hlsl$")


def shader_model(filename):
    """The model ShaderCompile is told with -ver, from a file name like name_ps30.hlsl (2x means 2.0b)."""
    match = NAME.match(filename)

    if not match:
        raise ValueError(f"{filename}: a shader file is called name_ps30.hlsl, name_vs30.hlsl or name_ps20b.hlsl")

    return "20b" if match["model"] in ("20b", "2x") else match["model"]


def build(src_dir, out_dir, compiler, headers_dir, suffix=""):
    """Compiles every shader of src_dir into out_dir; returns the names of the files written. `compiler` is the command (a list)."""
    if not os.path.isdir(headers_dir):
        raise FileNotFoundError(f"the SDK shader headers are not in {headers_dir} (the folder with common_ps_fxc.h)")

    sources = sorted(name for name in os.listdir(src_dir) if name.endswith(".hlsl"))
    os.makedirs(out_dir, exist_ok=True)
    written = []

    with tempfile.TemporaryDirectory() as work:
        for header in glob.glob(os.path.join(headers_dir, "*.h")):
            shutil.copy(header, work)

        for name in sources:
            model = shader_model(name)
            shutil.copy(os.path.join(src_dir, name), work)
            base = os.path.splitext(name)[0]
            command = list(compiler) + ["/O", "3", "-ver", model, "-shaderpath", work, "./" + name]
            result = subprocess.run(command, cwd=work, capture_output=True, text=True)

            if result.returncode != 0:
                raise RuntimeError(f"{name}: the compiler failed ({result.returncode})\n{result.stdout}{result.stderr}")

            produced = os.path.join(work, "shaders", "fxc", base + ".vcs")

            if not os.path.exists(produced):
                raise RuntimeError(f"{base}: the compiler wrote no {base}.vcs\n{result.stdout}{result.stderr}")

            target = base + suffix + ".vcs"
            shutil.copy(produced, os.path.join(out_dir, target))
            written.append(target)

    return written


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--compiler", required=True, help="the ShaderCompile executable")
    parser.add_argument("--headers", required=True, help="the folder with the Source SDK's common_*.h")
    parser.add_argument("--src", default=HERE)
    parser.add_argument("--out", default=os.path.join(ROOT, "shaders", "fxc"))
    parser.add_argument("--suffix", default="")
    args = parser.parse_args(argv)

    for name in build(args.src, args.out, [args.compiler], args.headers, args.suffix):
        print(os.path.normpath(os.path.join(args.out, name)))

    return 0


if __name__ == "__main__":
    sys.exit(main())
