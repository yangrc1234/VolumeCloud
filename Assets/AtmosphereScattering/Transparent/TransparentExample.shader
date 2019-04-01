Shader "Ap/TransparentExample" {
	Properties {
		_Color ("Color", Color) = (1,1,1,1)
		_MainTex ("Albedo (RGB)", 2D) = "white" {}
		_Glossiness ("Smoothness", Range(0,1)) = 0.5
		_Metallic ("Metallic", Range(0,1)) = 0.0
	}
	SubShader {
		Tags { 
			"RenderType"="Transparent"
			"Queue" = "Transparent"
		}
		LOD 200

		CGPROGRAM
		//We enable alpha to use transparent
		//Use finalcolor modifier to add ap to final result.
	    //And we need custom vs to calculate ap info on every vertex.
		#pragma surface surf Standard fullforwardshadows alpha finalcolor:aerialPerspective vertex:vert

		// Use shader model 3.0 target, to get nicer looking lighting
		#pragma target 3.0


		//Declare these values to use later.
		float3 _SunRadianceOnAtm;
		sampler3D _CameraVolumeTransmittance;
		sampler3D _CameraVolumeScattering;

		float3 GetTransmittanceWithCameraVolume(float3 uvw) {
			return tex3Dlod(_CameraVolumeTransmittance, float4(uvw, 0.0f)).rgb;
		}

		float3 GetScatteringWithCameraVolume(float3 uvw) {
			return tex3Dlod(_CameraVolumeScattering, float4(uvw, 0.0f)).rgb;
		}

		struct Input {
			float2 uv_MainTex;

			//Add these two to interpolate. Sample them from 3d volume in vertex shader.
			float3 ap_transmittance;
			float3 ap_scattering;
		};

		void vert(inout appdata_full v, out Input o) {
			UNITY_INITIALIZE_OUTPUT(Input, o);

			//Get uv using clip pos.
			float4 hpos = UnityObjectToClipPos(v.vertex);
			float3 ap_volume_uvw = float3(hpos.xy / hpos.w, 0.0f);
			ap_volume_uvw.xy = (ap_volume_uvw + 1.0f) / 2.0f;

			//Get w using view pos.
			float3 view_pos = UnityObjectToViewPos(v.vertex);
			view_pos.z *= -1;
			ap_volume_uvw.z = (view_pos.z - _ProjectionParams.y) / (_ProjectionParams.z - _ProjectionParams.y);

			//Set them to output.
			o.ap_transmittance = GetTransmittanceWithCameraVolume(ap_volume_uvw);
			o.ap_scattering = GetScatteringWithCameraVolume(ap_volume_uvw);
		}

		void aerialPerspective(Input IN, SurfaceOutputStandard o, inout fixed4 color)
		{
			//Edit final color using following formular.
			color.xyz = color.xyz * IN.ap_transmittance + color.a * IN.ap_scattering * _SunRadianceOnAtm;

			//I'm not pretty familiar with how Unity deal with Transparent and alpha, but it seems to be correct to mult scattering with color.a
		}

		//========================================================================
		//Following are default standard shader setup. Nothing changed.
		//========================================================================

		sampler2D _MainTex;
		half _Glossiness;
		half _Metallic;
		fixed4 _Color;

		// Add instancing support for this shader. You need to check 'Enable Instancing' on materials that use the shader.
		// See https://docs.unity3d.com/Manual/GPUInstancing.html for more information about instancing.
		// #pragma instancing_options assumeuniformscaling
		UNITY_INSTANCING_BUFFER_START(Props)
			// put more per-instance properties here
		UNITY_INSTANCING_BUFFER_END(Props)

		void surf (Input IN, inout SurfaceOutputStandard o) {
			// Albedo comes from a texture tinted by color
			fixed4 c = tex2D (_MainTex, IN.uv_MainTex) * _Color;
			o.Albedo = c.rgb;
			// Metallic and smoothness come from slider variables
			o.Metallic = _Metallic;
			o.Smoothness = _Glossiness;
			o.Alpha = c.a;
		}
		ENDCG
	}
	FallBack "Diffuse"
}
