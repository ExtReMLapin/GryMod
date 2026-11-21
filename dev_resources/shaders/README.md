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
- `screenspace_general` blends by alpha only with `$alphablend 1` (`$translucent 1` does not: it draws opaque). The picture behind a model is
  `_rt_FullFrameFB`, copied by `render.UpdateScreenEffectTexture()` before the model is drawn (the engine's own Refract material reads another copy and
  ignores the alpha). A custom shader needs `$model 1`, `$softwareskin 1` and `$vertexnormal 1` to be drawn on a model with the vertex shader's skinning.
- A pixel shader the game does not have: the engine draws pure WHITE with a vertex shader it knows (whatever the alpha), flat magenta the first time
  with no vertex shader, nothing after that. `cl_cloak_refract.lua` tells the real shader apart with a plate drawn twice (alpha 0 must leave the
  background, alpha 1 must show the picture).
- The refraction layer (`grymod_cloak_refract_*`, a port of the original's CloakRefrationPS) gets its relief map from each part of the model: the
  `$bumpmap` of its material, or `cloak_n` when it has none. The palette and the scan lines it reads come from the originals
  (`make_cloak_shader_textures.py`: cloak_palette.vtf and cloak_interlation.vtf).
- Never draw a model from inside its own draw hook without a guard (`drawing` in cl_cloak_fx.lua): the hook runs again for the draw.
- The vertex position a vertex shader hands over for a model drawn with `$softwareskin 1` is in the WORLD (measured with a diagnostic shader that showed
  it as a colour: it changes with the model's place on every axis). A pattern read from it stays put in the world and a walking player slides through
  it: the sparks' pixel shader reads it relative to the entity's origin and angles, which the Lua gives it (`c3.xyz`, `c2.xyz`).
- A `ClientsideModel` moved with `SetPos` / `SetAngles` and drawn at once in the same frame is drawn WHERE IT WAS until `SetupBones()` and
  `InvalidateBoneCache()` are called; a model far from the main view is culled even in a render target of its own. Measurements that move a test
  model (cl_cloak_shader_test.lua) put it in front of the player and refresh its bones.
- A material that reads more than three registers needs `$c3_x`..`$c3_w` too: `screenspace_general` has four constant registers, `c0` to `c3`.
