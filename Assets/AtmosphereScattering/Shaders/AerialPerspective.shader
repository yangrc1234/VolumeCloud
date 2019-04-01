Shader "Hidden/Yangrc/AerialPerspective"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}
	SubShader
	{
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"
			#include "AerialPerspectiveHelper.cginc"
			#include "Lighting.cginc"
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
				float4 scrPos: TEXCOORD1;
				float2 vsray : TEXCOORD2;
			};

			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				o.scrPos = ComputeScreenPos(o.vertex);
				o.vsray = (2.0 * v.uv - 1.0) * _ProjectionExtents.xy + _ProjectionExtents.zw;
				return o;
			}
			
			sampler2D _MainTex;
			sampler2D _CameraDepthTexture;
			float _LightScale;
			float3 _SunRadianceOnAtm;

			void CalculateRMuMusForDistancePoint(Length r, Number mu, Number mu_s, Number nu, Number d, OUT(Length) r_d, OUT(Number) mu_d, OUT(Number) mu_s_d);
			void CalculateRMuMusFromPosViewdir(AtmosphereParameters atm, float3 pos, float3 view_ray, float3 sun_direction, OUT(float) mu, OUT(float) mu_s, OUT(float) nu);
			float3 GetTransmittanceToTopAtmosphereBoundaryLerped(float r, float mu);

			half4 frag (v2f i) : SV_Target
			{ 
				float3 vspos = float3(i.vsray, 1.0);
				float4 worldPos = mul(unity_CameraToWorld, float4(vspos, 1.0));
				worldPos /= worldPos.w;

				half4 original = tex2D(_MainTex, i.uv);

				AtmosphereParameters atm = GetAtmParameters();
				float3 view_ray = normalize(worldPos.xyz - _WorldSpaceCameraPos);
				float raw_depth = SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, i.scrPos);
				float distance = LinearEyeDepth(raw_depth);
				if (distance / _ProjectionParams.z > 0.999f) {
					return original;
				}
				float depth = (distance - _ProjectionParams.x) / (_ProjectionParams.z - _ProjectionParams.x);

				float3 pixel_pos = worldPos + distance * view_ray;
#if 1
				float r, mu, mu_s, nu;
				float r_d, mu_d, mu_s_d;	//Current pixel on screen's info
				CalculateRMuMusFromPosViewdir(atm, _WorldSpaceCameraPos, view_ray, _WorldSpaceLightPos0, r, mu, mu_s, nu);
				float d1, d2;
				bool ray_r_mu_intersects_ground = RayIntersectsGround(atm, r, mu, d1, d2);
				CalculateRMuMusForDistancePoint(atm, r, mu, mu_s, nu, distance, r_d, mu_d, mu_s_d);
				
				//Transmittance to target point.
				float3 transmittanceToTarget = GetTransmittanceLerped(r, mu, distance, ray_r_mu_intersects_ground);
				
				//Here the two ray (r, mu) and (r_d, mu_d) is pointing same direction. 
				//so ray_r_mu_intersects_ground should apply to both of them. 
				//If we do intersect calculation later, some precision problems might appear, causing glitches near horizontal view dir.
				float3 scatteringBetween =
					GetTotalScatteringLerped(r, mu, mu_s, nu, ray_r_mu_intersects_ground)		
					- GetTotalScatteringLerped(r_d, mu_d, mu_s_d, nu, ray_r_mu_intersects_ground) * transmittanceToTarget;
#else
				float3 uvw = float3(i.uv, depth);
				float3 transmittanceToTarget = GetTransmittanceWithCameraVolume(uvw);
				float3 scatteringBetween = GetScatteringWithCameraVolume(uvw);
#endif
				return half4(original * transmittanceToTarget + _SunRadianceOnAtm * scatteringBetween, 1.0);
			}
			ENDCG
		}
	}
}
