// GryMod binoculars hologram: pixel shader (model 2.0b, drawn on a full-screen quad with the engine's own vertex shader).
// Port of the binoculars' highlight of Crysis Remastered (PostEffectsGame.cfx: DeferredSilhouettesOptimisedPS and BinocularViewSilhouettes),
// written again here in our own words. The arithmetic is the original's:
//
//   c      = the vision buffer at the pixel: rgb the colour of the entity drawn there (black elsewhere), a = 1 where an entity is, else 0
//   edge   = 1 when the alpha of one of three neighbours (a few pixels up, down-left and down-right) differs from the pixel's alpha
//   sil    = c.rgb * (FILL + edge * BOOST)                  the whole body is filled, its boundary is brighter
//   lines  = 1.2 on one pixel row, 0.8 on the next          (the scan lines, counted in screen pixels)
//   vign   = saturate(1 - distance from the screen's centre)
//   final  = (glow * GLOW_GAIN + sil) * STRENGTH * lines * vign
//
// Two modes (C1.z): 0 draws `sil` alone (no lines, no vignette) into a small buffer that the Lua blurs: that is the glow; 1 draws the final
// result over the screen (the material adds it to the picture).
// What the original's engine gave it comes from the Lua (cl_hud_binoculars_holo.lua): the numbers of the registers below.
// Compile: python dev_resources/shaders/build_shaders.py (the file name tells the model: ps20b).

sampler2D VISION : register(s0);	// the vision buffer, full size, not filtered
sampler2D GLOW : register(s1);		// the blurred `sil`, a fraction of the size

float4 C0 : register(c0);	// x: STRENGTH, y: BOOST, z: FILL, w: the neighbours' distance in pixels
float4 C1 : register(c1);	// x, y: one pixel of the vision buffer in uv units, z: mode (0: sil alone, 1: final), w: GLOW_GAIN
float4 C2 : register(c2);	// x: the screen's height in pixels, y: pixels to one period of the lines, z: the bright rows' level, w: the dim rows' level
float4 C3 : register(c3);	// x: the vignette's strength (1 = the original's), yzw: unused

struct PS_INPUT {
	float2 uv : TEXCOORD0;
};

float4 main(PS_INPUT frag) : COLOR {
	float2 reach = C1.xy * C0.w;

	float4 c = tex2D(VISION, frag.uv);
	float3 around;
	around.x = tex2D(VISION, frag.uv + reach * float2(0.0, -1.0)).a;
	around.y = tex2D(VISION, frag.uv + reach * float2(-1.0, 1.0)).a;
	around.z = tex2D(VISION, frag.uv + reach * float2(1.0, 1.0)).a;

	// an alpha is 0 or 1 (8 bits): any difference is at least 1/255, so a threshold of half of that is enough
	float edge = step(0.002, dot(abs(around - c.a), float3(1.0, 1.0, 1.0)));

	float3 sil = c.rgb * (C0.z + edge * C0.y);

	float3 glow = tex2D(GLOW, frag.uv).rgb * C1.w;

	// the original's scan lines: the bright level on the rows of the second half of a period, the dim one on the first
	float lines = (frac(frag.uv.y * C2.x / C2.y) > 0.5) ? C2.z : C2.w;
	float vignette = saturate(1.0 - length(frag.uv - 0.5) * C3.x);
	float3 final = (glow + sil) * (C0.x * lines * vignette);

	// no branch (model 2.0b has none): mode 0 gives `sil` alone, mode 1 the final result
	return float4((C1.z < 0.5) ? sil : final, 1.0);
}
