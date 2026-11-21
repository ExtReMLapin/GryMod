// GryMod camouflage, the electric sparks: vertex shader (model 3.0).
// Port of CloakSparksVS (Crysis, CloakLayer.cfx, pass 2) for Source: no vertex displacement (a vertex shader has no constants of its own here).
// It hands the pixel shader the vertex position in the model's own space (what the noise sticks to, as vPosOS in the original) and its
// distance to the world origin (the original uses it to shift the second spark lookup).
#include "common_vs_fxc.h"

struct VS_INPUT {
	float4 vPos : POSITION;
	float3 vNormal : NORMAL0;
};

struct VS_OUTPUT {
	float4 proj_pos : POSITION;
	float4 objPos : TEXCOORD0;	// xyz: position in the model's space, w: distance to the world origin
};

VS_OUTPUT main(VS_INPUT vert) {
	float3 world_normal;
	float3 world_pos;
	SkinPositionAndNormal(0, vert.vPos, vert.vNormal, 0, 0, world_pos, world_normal);

	VS_OUTPUT output = (VS_OUTPUT)0;
	output.proj_pos = mul(float4(world_pos, 1), cViewProj);
	output.objPos = float4(vert.vPos.xyz, length(world_pos));

	return output;
};
