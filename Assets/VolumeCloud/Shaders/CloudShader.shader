// Upgrade NOTE: commented out 'float4x4 _CameraToWorld', a built-in variable
// Upgrade NOTE: replaced '_CameraToWorld' with 'unity_CameraToWorld'

Shader "Yangrc/CloudShader"
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
		_CloudSize("CloudSize", float) = 50000

		_CloudOverallDensity("CloudOverallDensity",float) = .1
		_CloudCoverageModifier("CloudCoverageModifier", float) = 1.0
		_CloudTypeModifier("CloudTypeModifier", float) = 1.0

		_WeatherTex("WeatherTex", 2D) = "white" {}
		_WeatherTexSize("WeatherTexSize", float) = 50000
		_WindDirection("WindDirection",Vector) = (1,1,0,0)
		_SilverIntensity("SilverIntensity",float) = .8
		_ScatteringCoefficient("ScatteringCoefficient",float) = .04
		_ExtinctionCoefficient("ExtinctionCoefficient",float) = .04
		_MultiScatteringA("MultiScatteringA",float) = 0.5
		_MultiScatteringB("MultiScatteringB",float) = 0.5
		_MultiScatteringC("MultiScatteringC",float) = 0.5
		_SilverSpread("SilverSpread",float) = .75
		_RaymarchOffset("RaymarchOffset", float) = 0.0
		_AmbientColor("AmbientColor", Color) = (1,1,1,1)
		_AtmosphereColor("AtmosphereColor" , Color) = (1,1,1,1)
		_AtmosphereColorSaturateDistance("AtmosphereColorSaturateDistance", float) = 80000
	}

		SubShader
		{

			CGINCLUDE

			float GetRaymarchEndFromSceneDepth(float sceneDepth) {
				float raymarchEnd = 0.0f;
	#if ALLOW_CLOUD_FRONT_OBJECT
				if (sceneDepth == 1.0f) {	//it's far plane.
					raymarchEnd = 1e7;
				}
				else {
					raymarchEnd = sceneDepth * _ProjectionParams.z;	//raymarch to scene depth.
				}
	#else
				raymarchEnd = 1e8;	//Always raymarch. 
				//Note: In horizon:zero dawn, they clip some part using lod(use max operator) z-buffer. 
				//I don't implement here cause that's exactly what hi-z buffer does, and any production rendering pipeline should share a hi-z buffer by their own.
	#endif
				return raymarchEnd;
			}
			ENDCG

			Cull Off ZWrite Off ZTest Always
			//Pass1, Render a undersampled buffer. The buffer is dithered using bayer matrix(every 3x3 pixel) and halton sequence.
			//Why does it need a bayer matrix as offset? See technical overview on github page.
			Pass
			{
			CGPROGRAM
			#pragma multi_compile _ ALLOW_CLOUD_FRONT_OBJECT		//When enabled, raymarch is marched until scene depth. This will bring some artifacts when objects move in front of cloud.
																//Or disable, cloud is always behind object, and raymarch is ended if any z is detected.
			#pragma multi_compile LOW_QUALITY MEDIUM_QUALITY HIGH_QUALITY	//High quality uses more samples.
			#pragma vertex vert
			#pragma fragment frag
			//#include "./CloudShaderHelper.cginc"
			#include "./CloudNormalRaymarch.cginc"
			#include "UnityCG.cginc"

#if defined(HIGH_QUALITY)
			#define MIN_SAMPLE_COUNT 32
			#define MAX_SAMPLE_COUNT 32
#endif	
#if defined(MEDIUM_QUALITY)
			#define MIN_SAMPLE_COUNT 24
			#define MAX_SAMPLE_COUNT 24
#endif	
#if defined(LOW_QUALITY)
			#define MIN_SAMPLE_COUNT 16
			#define MAX_SAMPLE_COUNT 16
#endif
			sampler2D _CameraDepthTexture;
			float _RaymarchOffset;	//raymarch offset by halton sequence, [0,1]
			float4 _ProjectionExtents;
			float2 _TexelSize;	//Texelsize used to decide offset by bayer matrix.

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct Interpolator {
				float4 vertex : SV_POSITION;
				float4 screenPos : TEXCOORD0;
				float2 vsray : TEXCOORD1;
			};

			Interpolator vert (appdata v)
			{
				Interpolator o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				v.vertex.z = 0.5;
				o.screenPos = ComputeScreenPos(o.vertex);
				o.vsray = (2.0 * v.uv - 1.0) * _ProjectionExtents.xy + _ProjectionExtents.zw;
				return o;
			}

			float4 frag (Interpolator i) : SV_Target
			{
				float3 vspos = float3(i.vsray, 1.0);
				float4 worldPos = mul(unity_CameraToWorld,float4(vspos,1.0));
				worldPos /= worldPos.w;
				
				float sceneDepth = Linear01Depth(tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPos)).r);
				float raymarchEnd = GetRaymarchEndFromSceneDepth(sceneDepth);
				float3 viewDir = normalize(worldPos.xyz - _WorldSpaceCameraPos);
				int sample_count = lerp(MAX_SAMPLE_COUNT, MIN_SAMPLE_COUNT, abs(viewDir.y));	//dir.y ==0 means horizontal, use maximum sample count

				float2 screenPos = i.screenPos.xy / i.screenPos.w;
				int2 texelID = int2(fmod(screenPos/ _TexelSize , 3.0));	//Calculate a texel id to index bayer matrix.
										
				float bayerOffset = (bayerOffsets[texelID.x][texelID.y]) / 9.0f;	//bayeroffset between[0,1)
				float offset = -fmod(_RaymarchOffset + bayerOffset, 1.0f);			//final offset combined. The value will be multiplied by sample step in GetDensity.

				float intensity, distance;
				//TODO: sceneDepth here is distance in camera z-axis, but the parameter should be radial distance.
				float density = GetDensity(worldPos, viewDir, raymarchEnd, sample_count, offset, /*out*/intensity, /*out*/distance);

				return float4(intensity, distance, 1.0f, density);
			}

			ENDCG
		}

			//Pass 2, blend undersampled image with history buffer to new buffer.
			Pass{
				CGPROGRAM
				#pragma vertex vert
				#pragma fragment frag
				#pragma multi_compile _ ALLOW_CLOUD_FRONT_OBJECT
				#pragma multi_compile LOW_QUALITY MEDIUM_QUALITY HIGH_QUALITY	

				#include "./CloudShaderHelper.cginc"
				#include "UnityCG.cginc"
				
				sampler2D _MainTex;						//history buffer.
				float4 _MainTex_TexelSize;
				sampler2D _UndersampleCloudTex;			//current undersampled tex.
				float4 _UndersampleCloudTex_TexelSize;

				float4x4 _PrevVP;	//View projection matrix of last frame. Used to temporal reprojection.

				//These values are needed for doing extra raymarch when out of bound.
				sampler2D _CameraDepthTexture;
				float4 _ProjectionExtents;
				float2 _TexelSize;

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

				//Get uv of wspos in history buffer.
				float2 PrevUV(float4 wspos, out half outOfBound) {
					float4 prevUV = mul(_PrevVP, wspos);
					prevUV.xy = 0.5 * (prevUV.xy / prevUV.w) + 0.5;
					half oobmax = max(0.0 - prevUV.x, 0.0 - prevUV.y);
					half oobmin = max(prevUV.x - 1.0, prevUV.y - 1.0);
					outOfBound = step(0, max(oobmin, oobmax));
					return prevUV;
				}

				//Code from https://zhuanlan.zhihu.com/p/64993622. Do AABB clip in TAA(clip to center).
				float4 ClipAABB(float4 aabbMin, float4 aabbMax, float4 prevSample)
				{
					// note: only clips towards aabb center (but fast!)
					float4 p_clip = 0.5 * (aabbMax + aabbMin);
					float4 e_clip = 0.5 * (aabbMax - aabbMin);

					float4 v_clip = prevSample - p_clip;
					float4 v_unit = v_clip / e_clip;
					float4 a_unit = abs(v_unit);
					float ma_unit = max(max(a_unit.x, max(a_unit.y, a_unit.z)), a_unit.w);

					if (ma_unit > 1.0)
						return p_clip + v_clip / ma_unit;
					else
						return prevSample;// point inside aabb
				}
				
				float4 frag(v2f i) : SV_Target
				{
					float3 vspos = float3(i.vsray, 1.0);
					float4 worldPos = mul(unity_CameraToWorld, float4(vspos, 1.0f));
					worldPos /= worldPos.w;
					float4 raymarchResult = tex2D(_UndersampleCloudTex, i.uv);
					float distance = raymarchResult.y;		
					float intensity = raymarchResult.x;
					half outOfBound;
					float2 prevUV = PrevUV(mul(unity_CameraToWorld, float4(normalize(vspos) * distance, 1.0)), outOfBound);	//find uv in history buffer.
					
					{	//Do temporal reprojection and clip things.
						float4 prevSample = tex2D(_MainTex, prevUV);
						float2 xoffset = float2(_UndersampleCloudTex_TexelSize.x, 0.0f);
						float2 yoffset = float2(0.0f, _UndersampleCloudTex_TexelSize.y);

						float4 m1 = 0.0f, m2 = 0.0f;
						//The loop below calculates mean and variance used to calculate AABB.
						[unroll]
						for (int x = -1; x <= 1; x ++) {
							[unroll]
							for (int y = -1; y <= 1; y ++ ) {
								float4 val;
								if (x == 0 && y == 0) {
									val = raymarchResult;
								}
								else {
									val = tex2Dlod(_UndersampleCloudTex, float4(i.uv + xoffset * x + yoffset * y, 0.0, 0.0));
								}
								m1 += val;
								m2 += val * val;
							}
						}
						//Code from https://zhuanlan.zhihu.com/p/64993622.
						float gamma = 1.0f;
						float4 mu = m1 / 9;
						float4 sigma = sqrt(abs(m2 / 9 - mu * mu));
						float4 minc = mu - gamma * sigma;
						float4 maxc = mu + gamma * sigma;
						prevSample = ClipAABB(minc, maxc, prevSample);	

						//Blend.
						raymarchResult = lerp(prevSample, raymarchResult, max(0.05f, outOfBound));
					}
					return 	raymarchResult;
				}
				ENDCG
			}

			//Pass3, Calculate lighting, blend final cloud image with final image.
			Pass{
				Cull Off ZWrite Off ZTest Always
				CGPROGRAM
				#pragma vertex vert
				#pragma fragment frag
				#pragma multi_compile _ ALLOW_CLOUD_FRONT_OBJECT
				#pragma multi_compile _ USE_YANGRC_AP

				#include "UnityCG.cginc"
				#include "Lighting.cginc"

				//#define USE_YANGRC_AP	//Do we use atmosphere perspective? turn off this if ap is not needed.

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
#ifdef USE_YANGRC_AP	//Use value from AP system.
				#include "Assets/AtmosphereScattering/Shaders/AerialPerspectiveHelper.cginc"
#else
				float _AtmosphereColorSaturateDistance;
#endif	

				half4 frag(v2f i) : SV_Target
				{
					float3 vspos = float3(i.vsray, 1.0);
					float4 worldPos = mul(unity_CameraToWorld,float4(vspos,1.0));
					float3 viewDir = normalize(worldPos.xyz - _WorldSpaceCameraPos);

					half4 mcol = tex2D(_MainTex,i.uv);
					float4 currSample = tex2D(_CloudTex, i.uv);

					float depth = currSample.g;
					
					float3 sunColor;
#ifdef USE_YANGRC_AP
					{
						//Calculate color using depth estimated "position", and transmittance from ap system.
						float3 estimatedCloudCenter = _WorldSpaceCameraPos + depth * viewDir;
						float r, mu, mu_s, nu;
						CalculateRMuMusFromPosViewdir(GetAtmParameters(), estimatedCloudCenter, viewDir, _WorldSpaceLightPos0, r, mu, mu_s, nu);
						float3 transmittance = GetTransmittanceToTopAtmosphereBoundaryLerped(r, mu_s);
						sunColor = transmittance * _SunIrradianceOnAtm;
					}
#else
					sunColor = _LightColor0.rgb;
#endif
					float4 result;
					result.rgb = currSample.r * sunColor + currSample.b *_AmbientColor * currSample.a;
					result.a = currSample.a;
#ifdef USE_YANGRC_AP
					{
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
					}
#else
					float atmosphericBlendFactor = exp(-saturate(depth / _AtmosphereColorSaturateDistance));
					result.a *= atmosphericBlendFactor;
#endif

#if ALLOW_CLOUD_FRONT_OBJECT	//The result calculated from previous pass is already the part in front of object.
					return half4(mcol.rgb * (1 - result.a) + result.rgb * result.a, 1);
#else
					//Only use cloud if no object detected in z-buffer.
					float sceneDepth = Linear01Depth(tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPos)).r);
					if (sceneDepth == 1.0f) {
						return half4(mcol.rgb * (1 - result.a) + result.rgb * result.a, 1);
					}
					else {
						return mcol;
					}
#endif
				}
					ENDCG
				}
	}
}
