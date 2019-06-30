#include "UnityCG.cginc"
#include "./CloudNormalRaymarch.cginc"
UNITY_DECLARE_TEX2D(_CameraDepthTexture);
float4 _ProjectionExtents;

struct appdata
{
	float4 vertex : POSITION;
	float2 uv : TEXCOORD0;
};

struct v2f
{
	float2 uv : TEXCOORD0;
	float4 vertex : SV_POSITION;
};

v2f VertCloudShadow(appdata v)
{
	v2f o;
	o.vertex = UnityObjectToClipPos(v.vertex);
	o.uv = v.uv;
	return o;
}

// Get a raw depth from the depth buffer.
float SampleRawDepth(float2 uv)
{
	float z = _CameraDepthTexture.Sample(sampler_CameraDepthTexture, float4(uv, 0, 0));
#if defined(UNITY_REVERSED_Z)
	z = 1 - z;
#endif
	return z;
}


// Inverse project UV + raw depth into the view space.
float3 InverseProjectUVZ(float2 uv, float z)
{
	float4 cp = float4(float3(uv, z) * 2 - 1, 1);
	float4 vp = mul(unity_CameraInvProjection, cp);
	return float3(vp.xy, -vp.z) / vp.w;
}

float FragCloudShadow(v2f i) : SV_Target
{
	float depth = SampleRawDepth(i.uv);
	float3 vp = InverseProjectUVZ(i.uv, depth);

	float4 worldPos = mul(unity_CameraToWorld, float4(vp, 1.0f));
	worldPos /= worldPos.w;
	float3 viewDir = worldPos.xyz - _WorldSpaceCameraPos;
	if (depth == 1.0f)
		return 1.0f;

	float intensity, distance;
	float density = GetDensity(worldPos, -_WorldSpaceLightPos0, 1e6, 16, 0.0f, /*out*/intensity, /*out*/distance);

	return density;
}