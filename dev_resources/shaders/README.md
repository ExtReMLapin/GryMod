# Shaders

This folder (dev_resources, left out of the Workshop package and of the release zip) holds what is written before compilation: the HLSL of the
camouflage's electric sparks (a port of Crysis' `CloakSparksPS`) and the code that converts and compiles. The compiled `.vcs` the game loads are
the classic resources, in `shaders/fxc/` (gmad's white list takes `shaders/fxc/*.vcs`, not `.hlsl`).

Build (only the developer or the CI; ShaderCompile and the Source SDK's shader headers are not in this repository):

    python dev_resources/shaders/build_shaders.py --compiler ShaderCompile.exe --headers <folder with common_ps_fxc.h> [--suffix _r2]
    python dev_resources/shaders/make_cloak_shader_textures.py <folder of the original's dds>      # the noise volume and the spark profile

Things learned the hard way (all measured in the game):

- `screenspace_general` reads textures as sRGB and writes sRGB by default: a shader that calculates with what it reads needs
  `$linearread_basetexture 1` / `$linearread_texture1 1`.
- The game keeps the code of a shader name until it is closed, and a material by its name: to try a change in a running game, build with `--suffix` and
  change `Shader.PIXEL` / `Shader.VERTEX` / `Shader.materialName` (cl_cloak_shader.lua) before the first draw.
- A missing shader is not an error material (`Material:IsError()` is false): the engine draws flat magenta the first time and nothing the next
  times. cl_cloak_shader.lua tells by drawing a plate into a render target and counting blue pixels, and falls back to the older approximation.
- Never draw a view model or hands from inside their own `PostDrawViewModel` / `PostDrawPlayerHands` hook without a guard: `DrawModel` calls the hook again.
