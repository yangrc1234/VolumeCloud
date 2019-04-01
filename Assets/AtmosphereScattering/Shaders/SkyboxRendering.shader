// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

Shader "Skybox/AtmosphereScatteringPrecomputed"
{
	Properties
	{
	}
	SubShader
	{
		// No culling or depth
		Cull Off 
		ZWrite Off 
		Tags{
			"PreviewType" = "Skybox"
		}
		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"
			#include "Lighting.cginc"
			#include "MultipleScatteringHelper.cginc"
			#include "AerialPerspectiveHelper.cginc"
			
			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
				float4 worldPos : TEXCOORD1;
			};

			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				o.worldPos = mul(unity_ObjectToWorld, v.vertex);
				return o;
			}
			
			float _LightScale; 

			RadianceSpectrum GetScattering(
				IN(AtmosphereParameters) atmosphere,
				IN(ScatteringTexture) scattering_texture,
				uint3 texture_size,
				Length r, Number mu, Number mu_s, bool ray_r_mu_intersects_ground
			);

			void ComputeSingleScattering(
				IN(AtmosphereParameters) atmosphere,
				IN(TransmittanceTexture) transmittance_texture,
				uint2 texture_size,
				Length r, Number mu, Number mu_s, Number nu,
				bool ray_r_mu_intersects_ground,
				OUT(IrradianceSpectrum) rayleigh, OUT(IrradianceSpectrum) mie);

			float3 _SunRadianceOnAtm;
			half4 frag (v2f i) : SV_Target
			{ 
				i.worldPos /= i.worldPos.w;
				float3 view_ray = normalize(i.worldPos.xyz - _WorldSpaceCameraPos);
				float3 sun_direction = normalize(_WorldSpaceLightPos0.xyz);
				AtmosphereParameters atm = GetAtmParameters();
				float3 camera = _WorldSpaceCameraPos + float3(0, atm.bottom_radius, 0);
				float r = length(camera);
				r = max(r, atm.bottom_radius + 1.0f);	//r below bottom_radius causes glitch.
				Length rmu = dot(camera, view_ray);

				Length distance_to_top_atmosphere_boundary = -rmu -
					sqrt(rmu * rmu - r * r + atm.top_radius * atm.top_radius);

				if (distance_to_top_atmosphere_boundary > 0.0 ) {
					camera = camera + view_ray * distance_to_top_atmosphere_boundary;
					r = atm.top_radius;
					rmu += distance_to_top_atmosphere_boundary;
				}
				else if (r > atm.top_radius) {
					// If the view ray does not intersect the atmosphere, simply return 0.
					return 0.0f;
				}

				// Compute the r, mu, mu_s and nu parameters needed for the texture lookups.
				Number mu = rmu / r;
				Number mu_s = dot(camera, sun_direction) / r;
				Number nu = dot(view_ray, sun_direction);
				bool ray_r_mu_intersects_ground = RayIntersectsGround(atm, r, mu);

				float3 transmittance = GetTransmittanceToTopAtmosphereBoundaryLerped(r, mu) * (ray_r_mu_intersects_ground ? 0.0f : 1.0f);

				float3 direct_sun_strength = 0.0f;
				if (!ray_r_mu_intersects_ground)
				{
					direct_sun_strength = EvaluateSunDiskRadianceOfUnitRadiance(atm, r, mu, nu) * transmittance;
				}
				return half4(_SunRadianceOnAtm * (direct_sun_strength + GetTotalScatteringLerped(r, mu, mu_s, nu, ray_r_mu_intersects_ground)), 0.0f);
			}
			ENDCG
		}
	}
}
