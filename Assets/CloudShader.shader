Shader "Unlit/CloudShader"
{
	Properties
	{
		_MainTex("MainTex",2D) = "white"{}
		_CloudTex("CloudTex",2D) = "white"{}
		_VolumeTex("Texture", 3D) = "white" {}
		_DetailTex("Detail", 3D) = "white" {}
		_CoverageTex("CoverageTex", 2D) = "white" {}
		_Cutoff("Cutoff", float) = 0.5
		_CloudDentisy("CloudDentisy",float) = 0.02
		_CloudSize("CloudSize", float) = 16000
		_DetailTile("DetailTile", float) = 16000
		_DetailMask("DetailMask", float) = 0.1
		_Detail("Detail", float) = 0.5
		_HeightSignal("HeightSignal",2D) = "white"
		_Transcluency("Transcluency",float) = 2048
		_Occlude("Occlude",float) = 128
		_HgG("HgG",float) = 0.1
		_BeerLaw("BeerLaw",float) = 1
		_WindDirection("WindDirection",vector) = (1,1,0,0)
		_BlueNoise("BlueNoise",2D) = "gray"
	}
		SubShader
		{
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

			sampler2D _BlueNoise;
			float4x4 _ProjectionToWorld;
			sampler2D _CameraDepthTexture;
			struct appdata
			{
				float4 vertex : POSITION;
			};

			struct Interpolator {
				float4 vertex : SV_POSITION;
				float3 localPos : TEXCOORD0;
				float4 worldPos : TEXCOORD1;
				float4 screenPos : TEXCOORD2;
			};

			Interpolator vert (appdata v)
			{
				Interpolator o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.localPos = v.vertex;
				v.vertex.z = 0.5;
				o.worldPos = mul(_ProjectionToWorld, (v.vertex - 0.5) * 2);
				o.screenPos = ComputeScreenPos(o.vertex);
				return o;
			}
			
			half4 frag (Interpolator i) : SV_Target
			{
				float depthValue = LinearEyeDepth(tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPos)).r); 
				//return depthValue;
				if (depthValue > _ProjectionParams.z - 1) {	//it's far plane.
					depthValue += 100000;		//makes it work even with very low far plane value.
				}
				float2 screenPos = i.screenPos.xy / i.screenPos.w;
				float noiseSample = (tex2D(_BlueNoise, screenPos * _ScreenParams.xy / 64 + _Time.y * 20).a) ;
				float3 worldPos = i.worldPos / i.worldPos.w;
				float3 viewDir = normalize(worldPos - _WorldSpaceCameraPos);
			//	return float4(worldPos,1);
				float intensity;
				float dentisy = GetDentisy(worldPos, viewDir, depthValue, noiseSample,intensity);
				half3 col = (intensity * _LightColor0);
				float3 shColor = UNITY_LIGHTMODEL_AMBIENT.xyz;
				col += shColor * dentisy;
				return half4(col, dentisy);
			}
			ENDCG
		}

			//Blend low-res buffer with previmage to make final image.
			Pass{
				Cull Off ZWrite Off ZTest Always
				CGPROGRAM
				#pragma vertex vert
				#pragma fragment frag

				#include "UnityCG.cginc"

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

				v2f vert(appdata v)
				{
					v2f o;
					o.vertex = UnityObjectToClipPos(v.vertex);
					o.uv = v.uv;
					return o;
				}

				sampler2D _MainTex;	//this is previous full-resolution tex.
				float4 _MainTex_TexelSize;
				sampler2D _LowresCloudTex;	//current low-resolution tex.
				float2 _Jitter;		//jitter when rendering _LowresCloudTex in texel count.

				half4 frag(v2f i) : SV_Target
				{
					float2 texelPos = i.uv * _MainTex_TexelSize.zw;
					half4 prevSample = tex2D(_MainTex, i.uv);
					half2 currSampleTexel = texelPos - _Jitter;
					half2 currSamplePos = currSampleTexel * _MainTex_TexelSize.xy;
					half4 currSample = tex2D(_LowresCloudTex, currSamplePos);
					float2 currSampleValid = 0;	//Only if currsample is really the one in lowres buffer, then we use it.
					currSampleValid = step(frac(currSampleTexel / 4), 0.2);
				//	currSample.a *= currSampleValid.x * currSampleValid.y;
					return lerp(prevSample, currSample, currSampleValid.x * currSampleValid.y);
					//return half4(prevSample.rgb * (1 - currSample.a) + currSample.rgb * currSample.a,1);	//col.rgb includes intensity itself. don't need to multiply alpha.
				}
				ENDCG
		}
	}
}
