// GryMod camouflage, the refraction layer: pixel shader (model 3.0).
// Port of CloakRefrationPS (Crysis, CloakLayer.cfx, pass 1). The arithmetic is the original's:
//
//   N     = the normal, bent by the relief map of the model
//   NdotE = saturate(dot(eye, N))
//   inter = interlation(screen row)                        R and G of the scan lines texture
//   point = P + (2 NdotE (-N) + eye) * 0.05 * bump * inter.r      the refracted point, projected back to the screen
//   color = ( screen(point scaled 1.01 about the centre).r, screen(point).gb )      a little chromatic aberration
//   rim   = palette(inter.g * (1 - NdotE)) * light
//   out   = color + clamp(dot(color, 0.33), 0.2, 0.8) * rim * (1 - NdotE),  alpha = the cloak's blend
//
// Blended over the model the engine has drawn (the material has $alphablend): what shows is (1 - alpha) of the model and alpha of the picture
// behind it, bent. What the original's engine gave it comes from the Lua (cl_cloak_refract.lua); the model has no tangents here, so the
// tangent frame is made from the derivatives of the position and the texture coordinates.
#include "common_ps_fxc.h"

sampler2D REFRACT : register(s0);		// the picture behind, copied before the model is drawn (render.UpdateRefractTexture)
sampler2D BUMP : register(s1);			// the relief of the model (a normal map), repeating
sampler2D PALETTE : register(s2);		// the rim colours, 256 x 1
sampler2D INTERLATION : register(s3);	// the scan lines, 256 x 1, repeating

float4 C0 : register(c0);	// x: bump scale, y: alpha (the cloak's blend), z: the rim's light, w: screen rows to a period of the scan lines
float4 C1 : register(c1);	// x: random offset of the scan lines in rows, y, z: half a pixel in screen units (x, y), w: model units to one metre (52.49)
float4 C2 : register(c2);	// x: tiling of the relief map on the texture coordinates, y: strength of the relief

struct PS_INPUT {
	float2 uv : TEXCOORD0;
	float3 worldPos : TEXCOORD1;
	float3 worldNormal : TEXCOORD2;
	float4 clip : TEXCOORD3;
	float3 projX : TEXCOORD4;
	float3 projY : TEXCOORD5;
	float3 projW : TEXCOORD6;
	float3 viewVec : TEXCOORD7;
	float2 vpos : VPOS;
};

float4 main(PS_INPUT frag) : COLOR {
	float3 N = normalize(frag.worldNormal);

	// the tangent frame from the derivatives (no tangents in the vertex data)
	float3 dp1 = ddx(frag.worldPos);
	float3 dp2 = ddy(frag.worldPos);
	float2 duv1 = ddx(frag.uv);
	float2 duv2 = ddy(frag.uv);
	float3 dp2perp = cross(dp2, N);
	float3 dp1perp = cross(N, dp1);
	float3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	float3 B = dp2perp * duv1.y + dp1perp * duv2.y;
	float invmax = rsqrt(max(max(dot(T, T), dot(B, B)), 1e-12));

	float3 bump = tex2D(BUMP, frag.uv * C2.x).xyz * 2.0 - 1.0;
	bump.xy *= C2.y;
	float3 normal = normalize(T * invmax * bump.x + B * invmax * bump.y + N * bump.z);

	float3 eye = normalize(-frag.viewVec);
	float NdotE = saturate(dot(eye, normal));

	float2 inter = tex2D(INTERLATION, float2((frag.vpos.y + C1.x) / C0.w, 0.5)).xy;

	// the refracted point, in world units, then on the screen
	float3 refr = -2.0 * NdotE * normal + eye;
	float3 move = refr * 0.05 * C0.x * inter.x * C1.w;
	float3 clipMove = float3(dot(move, frag.projX), dot(move, frag.projY), dot(move, frag.projW));
	float4 refrPos = frag.clip + float4(clipMove.xy, 0.0, clipMove.z);
	float2 refrVS = 0.5 + C1.yz + (refrPos.xy * float2(0.5, -0.5) / refrPos.w);

	float3 refrColor;
	refrColor.x = tex2D(REFRACT, (refrVS - 0.5) * 1.01 + 0.5).x;
	refrColor.yz = tex2D(REFRACT, refrVS).yz;

	float lookup = inter.y * saturate(1.0 - NdotE);
	float3 rim = tex2D(PALETTE, float2(lookup, 0.5)).xyz * C0.z;

	float3 color = refrColor + clamp(dot(refrColor, float3(0.33, 0.33, 0.33)), 0.2, 0.8) * rim * saturate(1.0 - NdotE);

	return float4(color, C0.y);
};
