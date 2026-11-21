// GryMod camouflage, the electric sparks: pixel shader (model 3.0).
// Port of CloakSparksPS (Crysis, CloakLayer.cfx, pass 2). The arithmetic is the original's:
//
//   n  = noise3d(P + v)                      three reads in a chain, each moved by the one before
//   n  = noise3d(P + n * 0.2 + v)
//   n  = noise3d(P + n * 0.4 + v)
//   rgb = ( profile.r(n + t + 0.1), profile.g(n * 1.53 + 2 t + 0.4 + d * 0.1), profile.b(n * 1.7 + 1.4 t + 0.2) )
//   spark = (SparksColor * dot(rgb, 2)) ^ 2
//   result = interlation * spark * amount
//
// The original's inputs that this port gets from the Lua (cl_cloak_shader.lua) instead of from the engine: the time t, the variation v
// (vConstants), the strength `amount` (max(speed, transition ^ 2) times the light), the random offset of the scan lines. The interlation (a
// triangle wave, four screen rows to a period in the original) is calculated here from the pixel row. No bump map: the normal is flat.
#include "common_ps_fxc.h"

sampler3D NOISE : register(s0);		// the 128 cube of noise (one channel), repeating
sampler2D PROFILE : register(s1);	// the spark profile, 256 x 1, repeating along the row

float4 C0 : register(c0);	// x: model units to one volume (the original: 1 metre = 52.49 units), y: time t (the original's AnimGenParams), z: amount, w: screen rows to one period of the scan lines
float4 C1 : register(c1);	// x, y: the variation (vConstants.xy), z: random offset of the scan lines in rows
float4 C2 : register(c2);	// xyz: SparksColor

struct PS_INPUT {
	float4 objPos : TEXCOORD0;
	float2 vpos : VPOS;
};

float4 main(PS_INPUT frag) : COLOR {
	float3 P = frag.objPos.xyz / C0.x;
	float t = C0.y;
	float3 v = C1.x + float3(0.0, 0.0, C1.y);	// the original adds the bump map's normal * vConstants.y: flat, it is (0, 0, 1)

	float n = tex3D(NOISE, P + v).x;
	n = tex3D(NOISE, P + n * 0.2 + v).x;
	n = tex3D(NOISE, P + n * 0.4 + v).x;

	float3 rgb = float3(
		tex2D(PROFILE, float2(n + t + 0.1, 0.5)).x,
		tex2D(PROFILE, float2(n * 1.53 + t * 2.0 + 0.4 + frag.objPos.w * 0.1, 0.5)).y,
		tex2D(PROFILE, float2(n * 1.7 + t * 1.4 + 0.2, 0.5)).z);

	float3 spark = C2.xyz * dot(rgb, float3(2.0, 2.0, 2.0));
	spark *= spark;

	float interlation = abs(frac((frag.vpos.y + C1.z) / C0.w) * 2.0 - 1.0);

	return FinalOutput(float4(spark * (interlation * C0.z), 1.0), 0, PIXEL_FOG_TYPE_NONE, TONEMAP_SCALE_LINEAR);
};
