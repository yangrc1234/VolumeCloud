// Upgrade NOTE: commented out 'float4x4 _CameraToWorld', a built-in variable
// Upgrade NOTE: replaced '_CameraToWorld' with 'unity_CameraToWorld'

Shader "Unlit/CloudShader"
{
	Properties
	{
		_MainTex("MainTex",2D) = "white"{}
		_HeightDensity("HeightDensity", 2D) = "white"{}
		_BaseTex("BaseTex", 3D) = "white" {}
		_BaseTile("BaseTile", float) = 3.0
		_DetailTex("Detail", 3D) = "white" {}
		_DetailTile("DetailTile", float) = 10.0
		_DetailStrength("DetailStrength", float) = 0.2
		_CurlNoise("CurlNoise", 2D) = "white"{}
		_CurlTile("CurlTile", float) = .2
		_CurlStrength("CurlStrength", float) = 1
		_CloudTopOffset("TopOffset",float) = 100
		_CloudDensity("CloudDensity",float) = .1
		_CloudSize("CloudSize", float) = 50000
		_CloudCoverageModifier("CloudCoverageModifier", float) = 1.0
		_CloudTypeModifier("CloudTypeModifier", float) = 1.0
		_WeatherTex("WeatherTex", 2D) = "white" {}
		_WeatherTexSize("WeatherTexSize", float) = 25000
		_WindDirection("WindDirection",Vector) = (1,1,0,0)
		_SilverIntensity("SilverIntensity",float) = .8
		_ScatteringCoefficient("ScatteringCoefficient",float) = .04
		_ExtinctionCoefficient("ExtinctionCoefficient",float) = .04
		_MultiScatteringA("MultiScatteringA",float) = 0.5
		_MultiScatteringB("MultiScatteringB",float) = 0.5
		_MultiScatteringC("MultiScatteringC",float) = 0.5
		_SilverSpread("SilverSpread",float) = .75
		_BlueNoise("BlueNoise",2D) = "gray" {}
		_RaymarchOffset("RaymarchOffset", float) = 0.0
		_AmbientColor("AmbientColor", Color) = (1,1,1,1)
		_AtmosphereColor("AtmosphereColor" , Color) = (1,1,1,1)
		_AtmosphereColorSaturateDistance("AtmosphereColorSaturateDistance", float) = 80000
	}
		SubShader
		{
			Cull Off ZWrite Off ZTest Always
			Tags {
				"RenderType" = "Transparent"
				"Queue" = "Transparent"
				"LightMode" = "ForwardBase"
			}
			Lighting On
			LOD 100
			//Render to low-res buffer.
			Pass
			{

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			// make fog work
			#pragma multi_compile_fog
			#include "./CloudShaderHelper.cginc"
			#include "UnityCG.cginc"
			#include "Lighting.cginc"

			#define MIN_SAMPLE_COUNT 64
			#define MAX_SAMPLE_COUNT 96
			sampler2D _BlueNoise;
			sampler2D _CameraDepthTexture;
			float _RaymarchOffset;
			float4 _ProjectionExtents;

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct Interpolator {
				float4 vertex : SV_POSITION;
				float3 localPos : TEXCOORD0;
				float4 screenPos : TEXCOORD2;
				float2 vsray : TEXCOORD1;
			};

			Interpolator vert (appdata v)
			{
				Interpolator o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.localPos = v.vertex;
				v.vertex.z = 0.5;
				o.screenPos = ComputeScreenPos(o.vertex);
				o.vsray = (2.0 * v.uv - 1.0) * _ProjectionExtents.xy + _ProjectionExtents.zw;
				return o;
			}

			float4 frag (Interpolator i) : SV_Target
			{
				return 1.0f;
				float3 vspos = float3(i.vsray, 1.0);
				float4 worldPos = mul(unity_CameraToWorld,float4(vspos,1.0));
				worldPos /= worldPos.w;
				float depthValue = LinearEyeDepth(tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPos)).r); 
				//return depthValue;
				if (depthValue > _ProjectionParams.z - 1) {	//it's far plane.
					depthValue += 100000;		//makes it work even with very low far plane value.
				}
				float2 screenPos = i.screenPos.xy / i.screenPos.w;
				//float noiseSample = (tex2D(_BlueNoise, screenPos * _ScreenParams.xy / 64 + _Time.y * 20).a) ;
				float noiseSample = fmod(_Time.y, 1.0);
				float3 viewDir = normalize(worldPos.xyz - _WorldSpaceCameraPos);
				float intensity;
				float depth;
				int sample_count = lerp(MAX_SAMPLE_COUNT, MIN_SAMPLE_COUNT, viewDir.y);	//dir.y ==0 means horizontal, use maximum sample count
				float density = GetDentisy(worldPos, viewDir, depthValue, sample_count, fmod(_RaymarchOffset, 1.0), intensity, depth);

				/*RGBA: direct intensity, depth(this is differenct from the slide), ambient, alpha*/
				//return depth / 10000.0f;
				return float4(intensity, depth, /*ambient haven't implemented yet */1, density);
			}

			ENDCG
		}

			//Blend low-res buffer with previmage to make final cloud image.
			Pass{
				CGPROGRAM
				#pragma vertex vert
				#pragma fragment frag

				#include "./CloudShaderHelper.cginc"
				#include "UnityCG.cginc"
				#include "Lighting.cginc"

				sampler2D _MainTex;	//this is previous full-resolution tex.
				sampler2D _LowresCloudTex;	//current low-resolution tex.
				float4 _MainTex_TexelSize;
				float2 _Jitter;		//jitter when rendering _LowresCloudTex in texel count.
				float4x4 _PrevVP;	//View projection matrix of last frame.
				sampler2D _CameraDepthTexture;
				float4 _ProjectionExtents;
				half3 _AtmosphereColor;
				float _AtmosphereColorSaturateDistance;
				half3 _AmbientColor;
				float _RaymarchOffset;

				float4 debug;

				struct appdata
				{
					float4 vertex : POSITION;
					float2 uv : TEXCOORD0;
				};

				struct v2f
				{
					float4 vertex : SV_POSITION;
					float2 uv : TEXCOORD0;
					float2 vsray : TEXCOORD1;
					float4 screenPos : TEXCOORD2;
				};

				v2f vert(appdata v)
				{
					v2f o;
					o.vertex = UnityObjectToClipPos(v.vertex);
					o.uv = v.uv;
					o.vsray = (2.0 * v.uv - 1.0) * _ProjectionExtents.xy + _ProjectionExtents.zw;
					o.screenPos = ComputeScreenPos(o.vertex);
					return o;
				}


				half4 SamplePrev(float3 vspos,out half outOfBound) {
					float4 wspos = mul(unity_CameraToWorld,float4(vspos,1.0));
					float4 prevUV = mul(_PrevVP, wspos);
					prevUV.xy = 0.5 * (prevUV.xy / prevUV.w) + 0.5;
					half oobmax = max(0.0 - prevUV.x,0.0 - prevUV.y);
					half oobmin = max(prevUV.x - 1.0, prevUV.y - 1.0);
					outOfBound = step(0,max(oobmin, oobmax));
					half4 prevSample = tex2Dlod(_MainTex, float4(prevUV.xy, 0, 0));
					return prevSample;
				}

				float4 SampleCurrent(float2 uv) {
					uv = uv - (_Jitter - 1.5) * _MainTex_TexelSize.xy;
					float4 currSample = tex2Dlod(_LowresCloudTex, float4(uv, 0, 0));
					return currSample;
				}

				half CurrentCorrect(float2 uv,float2 jitter) {
					float2 texelRelativePos = fmod(uv * _MainTex_TexelSize.zw, 4);//between (0, 4.0)
					texelRelativePos -= jitter;
					float2 valid = saturate(2 * (0.5 - abs(texelRelativePos - 0.5)));
					return valid.x * valid.y;
				}
				
				#define MIN_SAMPLE_COUNT 16
				#define MAX_SAMPLE_COUNT 32
				#define OOB_SAMPLE_COUNT 128
				half4 frag(v2f i) : SV_Target
				{
					float depthValue = LinearEyeDepth(tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPos)).r);
					//return depthValue;
					if (depthValue > _ProjectionParams.z - 1) {	//it's far plane.
						depthValue += 100000;		//makes it work even with very low far plane value.
					}

					float3 vspos = float3(i.vsray, 1.0);

					float4 worldPos = mul(unity_CameraToWorld, float4(vspos, 1.0));
					worldPos /= worldPos.w;
					float3 viewDir = normalize(worldPos.xyz - _WorldSpaceCameraPos);
					int sample_count = lerp(MAX_SAMPLE_COUNT, MIN_SAMPLE_COUNT, viewDir.y);	//dir.y ==0 means horizontal, use maximum sample count
					float intensity, depth;
					float density = GetDentisy(worldPos, viewDir, depthValue, sample_count, 2.0f * _RaymarchOffset, intensity, depth);
					float4 raymarchResult = float4(intensity, depth, 1, density);

					half outOfBound;
					half4 prevSample = SamplePrev(vspos * depth, outOfBound);
					if (outOfBound > 0.5f) {
						float density = GetDentisy(worldPos, viewDir, depthValue, OOB_SAMPLE_COUNT, 0.0f, intensity, depth);
						raymarchResult = float4(intensity, depth, 1, density);
					}

					return lerp(prevSample, raymarchResult, max(0.05f, outOfBound));
				}
				ENDCG
		}

			//Blend final cloud image with final image.
			Pass{
					Cull Off ZWrite Off ZTest Always
					CGPROGRAM
#pragma vertex vert
#pragma fragment frag

#include "UnityCG.cginc"
#include "Lighting.cginc"

#define USE_YANGRC_AP	//Do we use atmosphere perspective? turn off this if ap is not needed.

				sampler2D _MainTex;	//Final image without cloud.
				sampler2D _CloudTex;	//The full resolution cloud tex we generated.
				sampler2D _CameraDepthTexture;
				float4 _ProjectionExtents;

				struct appdata
				{
					float4 vertex : POSITION;
					float2 uv : TEXCOORD0;
				};

				struct v2f
				{
					float2 uv : TEXCOORD0;
					float4 screenPos : TEXCOORD1;
					float4 vertex : SV_POSITION;
					float2 vsray : TEXCOORD2;
				};

				v2f vert(appdata v)
				{
					v2f o;
					o.vertex = UnityObjectToClipPos(v.vertex);
					o.uv = v.uv;
					o.screenPos = ComputeScreenPos(o.vertex);
					o.vsray = (2.0 * v.uv - 1.0) * _ProjectionExtents.xy + _ProjectionExtents.zw;
					return o;
				}
				half3 _AmbientColor;
				half3 _AtmosphereColor;
				float _AtmosphereColorSaturateDistance;
#ifdef USE_YANGRC_AP
#include "Assets/AtmosphereScattering/Shaders/AerialPerspectiveHelper.cginc"
#endif	
				half4 frag(v2f i) : SV_Target
				{
					float3 vspos = float3(i.vsray, 1.0);
					float4 worldPos = mul(unity_CameraToWorld,float4(vspos,1.0));
					float3 viewDir = normalize(worldPos.xyz - _WorldSpaceCameraPos);

					half4 mcol = tex2D(_MainTex,i.uv);
					half4 currSample = tex2D(_CloudTex, i.uv);

					float depth = currSample.g;
					
					float3 sunColor;
#ifdef USE_YANGRC_AP
					{
						//Calculate color using depth estimated "position", and transmittance from ap system.
						float3 estimatedCloudCenter = _WorldSpaceCameraPos + depth * viewDir;
						float r, mu, mu_s, nu;
						CalculateRMuMusFromPosViewdir(GetAtmParameters(), estimatedCloudCenter, viewDir, _WorldSpaceLightPos0, r, mu, mu_s, nu);
						float3 transmittance = GetTransmittanceToTopAtmosphereBoundaryLerped(r, mu_s);
						sunColor = transmittance * _SunRadianceOnAtm;
					}
#else
					sunColor = _LightColor0.rgb;
#endif
					half4 result;
					result.rgb = currSample.r * sunColor + currSample.b *_AmbientColor * currSample.a;
					result.a = currSample.a;

#ifdef USE_YANGRC_AP
					///* Calculate ap */
					float r, mu, mu_s, nu;
					float r_d, mu_d, mu_s_d;	//Current pixel on screen's info
					AtmosphereParameters atm = GetAtmParameters();
					CalculateRMuMusFromPosViewdir(atm, _WorldSpaceCameraPos, viewDir, _WorldSpaceLightPos0, r, mu, mu_s, nu);
					float d1, d2;
					bool ray_r_mu_intersects_ground = RayIntersectsGround(atm, r, mu, d1, d2);
					CalculateRMuMusForDistancePoint(atm, r, mu, mu_s, nu, depth, r_d, mu_d, mu_s_d);

					//Transmittance to target point.
					float3 transmittanceToTarget = GetTransmittanceLerped(r, mu, depth, ray_r_mu_intersects_ground);

					//Here the two ray (r, mu) and (r_d, mu_d) is pointing same direction. 
					//so ray_r_mu_intersects_ground should apply to both of them. 
					//If we do intersect calculation later, some precision problems might appear, causing glitches near horizontal view dir.
					float3 scatteringBetween =
						GetTotalScatteringLerped(r, mu, mu_s, nu, ray_r_mu_intersects_ground)
						- GetTotalScatteringLerped(r_d, mu_d, mu_s_d, nu, ray_r_mu_intersects_ground) * transmittanceToTarget;

					result.rgb = result.rgb * transmittanceToTarget + scatteringBetween;
#else
					float atmosphericBlendFactor = saturate(pow(depth / _AtmosphereColorSaturateDistance, 0.6));
					result.rgb = lerp(result.rgb, _AtmosphereColor * currSample.a, saturate(atmosphericBlendFactor));
#endif

					float originalDepthValue = LinearEyeDepth(tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPos)).r);
					//only if depthValue is nearly at the far clip plane, we use cloud.
					if (originalDepthValue > _ProjectionParams.z - 100) {
						return half4(mcol.rgb * (1 - result.a) + result.rgb * result.a, 1);
					}
					return mcol;
				}
					ENDCG
				}
	}
}
