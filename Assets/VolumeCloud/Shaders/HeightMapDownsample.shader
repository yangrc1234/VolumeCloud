// Upgrade NOTE: commented out 'float4x4 _CameraToWorld', a built-in variable
// Upgrade NOTE: replaced '_CameraToWorld' with 'unity_CameraToWorld'

Shader "Yangrc/HeightMapDownsample"
{
	Properties
	{
		
	}

	SubShader
	{

		CGINCLUDE

		ENDCG

		Cull Off ZWrite Off ZTest Always
		Pass	//Pass 1, extract finiest height map from weather tex, using height lut.
		{
		CGPROGRAM
		#pragma vertex vert
		#pragma fragment frag

		sampler2D _WeatherTex;
		sampler2D _HeightLut;

		struct appdata
		{
			float4 vertex : POSITION;
			float2 uv : TEXCOORD0;
		};

		struct Interpolator {
			float4 vertex : SV_POSITION;
			float2 uv : TEXCOORD0;
		};

		Interpolator vert (appdata v)
		{
			Interpolator o;
			o.vertex = UnityObjectToClipPos(v.vertex);
			o.uv = v.uv;
			return o;
		}

		float frag (Interpolator i) : SV_Target
		{
			float3 weatherData = tex2D(_WeatherTex, i.uv);
			float height = tex2D(_HeightLut, float2(weatherData.xz))	/*Index using coverage(x) and heightpercent(z)*/
			return height;
		}

		ENDCG
		}

		Pass	//Pass 2, downsample height map using max operator.
		{
		CGPROGRAM
		#pragma vertex vert
		#pragma fragment frag

		sampler2D _HeightLut;

		struct appdata
		{
			float4 vertex : POSITION;
			float2 uv : TEXCOORD0;
		};

		struct Interpolator {
			float4 vertex : SV_POSITION;
			float2 uv : TEXCOORD0;
		};

		Interpolator vert (appdata v)
		{
			Interpolator o;
			o.vertex = UnityObjectToClipPos(v.vertex);
			o.uv = v.uv;
			return o;
		}

		float frag (Interpolator i) : SV_Target
		{
			float3 weatherData = tex2D(_WeatherTex, i.uv);
			float height = tex2D(_HeightLut, float2(weatherData.xz))	/*Index using coverage(x) and heightpercent(z)*/
			return height;
		}

		ENDCG
		}
	}
}
