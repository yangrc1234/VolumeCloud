Shader "Unlit/CloudShader"
{
	Properties
	{
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
			Blend SrcAlpha OneMinusSrcAlpha
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

			struct appdata
			{
				float4 vertex : POSITION;
			};

			struct Interpolator {
				float4 vertex : SV_POSITION;
				float3 localPos : TEXCOORD0;
				float3 worldPos : TEXCOORD1;
				float4 screenPos : TEXCOORD2;
			};


			Interpolator vert (appdata v)
			{
				Interpolator o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.localPos = v.vertex;
				o.worldPos = mul(unity_ObjectToWorld, v.vertex);
				o.screenPos = ComputeScreenPos(o.vertex);
				return o;
			}
			
			half4 frag (Interpolator i) : SV_Target
			{
				float2 screenPos = i.screenPos.xy / i.screenPos.w;
				float noiseSample = (tex2D(_BlueNoise, screenPos * _ScreenParams.xy / 64 + _Time.y * 20).a) - 0.5;
				float3 worldPos = i.worldPos;
				float4 localPos = float4(i.localPos,1);
				float3 viewDir = normalize(lerp(worldPos - _WorldSpaceCameraPos, -UNITY_MATRIX_V[2].xyz, UNITY_MATRIX_P[3][3]));
				float3 objViewDir = normalize(UnityWorldToObjectDir(viewDir));
				float3 startPosition = localPos;
				//float dentisy = GetDentisy(_VolumeTex, startPosition, objViewDir);
				float intensity;
				float dentisy = GetDentisy(worldPos, viewDir, noiseSample,intensity);
				half3 col = (intensity * _LightColor0);
				float3 shColor = ShadeSH9(float4(0,1,0, 1));
				col += shColor;
			//	return float4(_WorldSpaceLightPos0.xyz, 1);
				return half4(col, dentisy);
			}
			ENDCG
		}
	}
}
