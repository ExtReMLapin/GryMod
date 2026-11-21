// GryMod camouflage, the refraction layer: vertex shader (model 3.0).
// Port of CloakVS (Crysis, CloakLayer.cfx, pass 1) for Source. It hands the pixel shader what the original's pixel shader got from its engine:
// the model's texture coordinates, the world position and normal, the view vector, and the part of the view-projection matrix that moves a
// world position to the screen (a column for x, y and w), so that the pixel shader can project the refracted point itself, as the original does.
#include "common_vs_fxc.h"

struct VS_INPUT {
	float4 vPos : POSITION;
	float3 vNormal : NORMAL0;
	float4 vTexCoord : TEXCOORD0;
};

struct VS_OUTPUT {
	float4 proj_pos : POSITION;
	float2 uv : TEXCOORD0;
	float3 worldPos : TEXCOORD1;
	float3 worldNormal : TEXCOORD2;
	float4 clip : TEXCOORD3;	// the position in clip space
	float3 projX : TEXCOORD4;	// how a move of the world position moves the clip x, y and w
	float3 projY : TEXCOORD5;
	float3 projW : TEXCOORD6;
	float3 viewVec : TEXCOORD7;	// from the eye to the position
};

VS_OUTPUT main(VS_INPUT vert) {
	float3 world_normal;
	float3 world_pos;
	SkinPositionAndNormal(0, vert.vPos, vert.vNormal, 0, 0, world_pos, world_normal);

	VS_OUTPUT output = (VS_OUTPUT)0;
	output.clip = mul(float4(world_pos, 1), cViewProj);
	output.proj_pos = output.clip;
	output.uv = vert.vTexCoord.xy;
	output.worldPos = world_pos;
	output.worldNormal = normalize(world_normal);
	output.projX = float3(cViewProj[0][0], cViewProj[1][0], cViewProj[2][0]);
	output.projY = float3(cViewProj[0][1], cViewProj[1][1], cViewProj[2][1]);
	output.projW = float3(cViewProj[0][3], cViewProj[1][3], cViewProj[2][3]);
	output.viewVec = world_pos - cEyePos;

	return output;
};
