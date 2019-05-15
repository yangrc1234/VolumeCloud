#include "UnityCG.cginc"
// Upgrade NOTE: excluded shader from DX11, OpenGL ES 2.0 because it uses unsized arrays
#pragma exclude_renderers d3d11 gles

#define THICKNESS 8000.0
#define CENTER 5500.0

#define EARTH_RADIUS 5000000.0
#define EARTH_CENTER float3(0, -EARTH_RADIUS, 0)

#define CLOUDS_START (CENTER - THICKNESS/2)
#define CLOUDS_END (CENTER + THICKNESS/2)

#define TRANSMITTANCE_SAMPLE_STEP 256.0f

static const float bayerOffsets[3][3] = {
	{0, 7, 3},
	{6, 5, 2},
	{4, 1, 8}
};

//Base shape
sampler3D _BaseTex;
float _BaseTile;
sampler2D _HeightDensity;
//Detal shape
sampler3D _DetailTex;
float _DetailTile;
float _DetailStrength;
//Curl distortion
sampler2D _CurlNoise;
float _CurlTile;
float _CurlStrength;
//Top offset
float _CloudTopOffset;

//Overall cloud size.
float _CloudSize;
//Overall Density
float _CloudDensity;
float _CloudCoverageModifier;
float _CloudTypeModifier;

half4 _WindDirection;
sampler2D _WeatherTex;
float _WeatherTexSize;

//Lighting
float _ScatteringCoefficient;
float _ExtinctionCoefficient;
float _SilverIntensity;
float _SilverSpread;

float SampleDensity(float3 worldPos, int lod, bool cheap, out float wetness);

float Remap(float original_value, float original_min, float original_max, float new_min, float new_max)
{
	return new_min + (((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
}

float RemapClamped(float original_value, float original_min, float original_max, float new_min, float new_max)
{
	return new_min + (saturate((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
}

float HeightPercent(float3 worldPos) {
	float sqrMag = worldPos.x * worldPos.x + worldPos.z * worldPos.z;

	float heightOffset = EARTH_RADIUS - sqrt(max(0.0, EARTH_RADIUS * EARTH_RADIUS - sqrMag));

	return saturate((worldPos.y + heightOffset - CENTER + THICKNESS / 2) / THICKNESS);
}

static float4 cloudGradients[] = {
	float4(0, 0.07, 0.08, 0.15),
	float4(0, 0.2, 0.42, 0.6),
	float4(0, 0.08, 0.75, 1)
};

float SampleHeight(float heightPercent,float cloudType) {
	float4 gradient;
	float cloudTypeVal;
	if (cloudType < 0.5) {
		gradient = lerp(cloudGradients[0], cloudGradients[1], cloudType*2.0);
	}
	else {
		gradient = lerp(cloudGradients[1], cloudGradients[2], (cloudType - 0.5)*2.0);
	} 

	return RemapClamped(heightPercent, gradient.x, gradient.y, 0.0, 1.0)
			* RemapClamped(heightPercent, gradient.z, gradient.w, 1.0, 0.0);
}

float3 ApplyWind(float3 worldPos) {
	float heightPercent = HeightPercent(worldPos);
	
	// skew in wind direction
	worldPos.xz -= (heightPercent) * _WindDirection.xy * _CloudTopOffset;

	//animate clouds in wind direction and add a small upward bias to the wind direction
	worldPos.xz -= (_WindDirection.xy + float3(0.0, 0.1, 0.0)) * _Time.y * _WindDirection.z;
	worldPos.y -= _WindDirection.z * 0.4 * _Time.y;
	return worldPos;
}

float HenryGreenstein(float g, float cosTheta) {

	float k = 3.0 / (8.0 * 3.1415926f) * (1.0 - g * g) / (2.0 + g * g);
	return k * (1.0 + cosTheta * cosTheta) / pow(abs(1.0 + g * g - 2.0 * g * cosTheta), 1.5);
}

float SampleDensity(float3 worldPos,int lod, bool cheap, out float wetness) {
	//Store the pos without wind applied.
	float3 unwindWorldPos = worldPos;
	
	//Sample the weather map.
	half4 coverageSampleUV = half4((unwindWorldPos.xz / _WeatherTexSize), 0, 2.5);
	coverageSampleUV.xy = (coverageSampleUV.xy + 0.5);
	float3 weatherData = tex2Dlod(_WeatherTex, coverageSampleUV);
	weatherData *= float3(_CloudCoverageModifier, 1.0, _CloudTypeModifier);
	float cloudCoverage = RemapClamped(weatherData.r, 0.0 ,1.0, 0.3, 1.0);
	float cloudType = weatherData.b;
	wetness = 1.0f;

	//Calculate the normalized height between[0,1]
	float heightPercent = HeightPercent(worldPos);
	if (heightPercent <= 0.0f || heightPercent >= 1.0f)
		return 0.0;

	//Sample base noise.
	fixed4 tempResult;
	worldPos = ApplyWind(worldPos);
	tempResult = tex3Dlod(_BaseTex, half4(worldPos / _CloudSize * _BaseTile, lod)).rgba;
	float low_freq_fBm = (tempResult.g * .625) + (tempResult.b * 0.25) + (tempResult.a * 0.125);
	float sampleResult = RemapClamped(tempResult.r, 0.0, .1, .0, 1.0);	//perlin-worley
	sampleResult = RemapClamped(low_freq_fBm, -0.5 * sampleResult, 1.0, 0.0, 1.0);

	//Sample Height-Density map.
	float2 densityAndErodeness = tex2D(_HeightDensity, float2(cloudType, heightPercent)).rg;

	sampleResult *= densityAndErodeness.x;
	//Clip the result using coverage map.
	sampleResult = RemapClamped(sampleResult, 1.0 - cloudCoverage.x, 1.0, 0.0, 1.0);
	sampleResult *= cloudCoverage.x;

	if (!cheap) {
		float2 curl_noise = tex2Dlod(_CurlNoise, float4(unwindWorldPos.xz / _CloudSize * _CurlTile, 0.0, 1.0)).rg;
		worldPos.xz += curl_noise.rg * (1.0 - heightPercent) * _CloudSize * _CurlStrength;

		float3 tempResult2;
		tempResult2 = tex3Dlod(_DetailTex, half4(worldPos / _CloudSize * _DetailTile, lod)).rgb;
		float detailsampleResult = (tempResult2.r * 0.625) + (tempResult2.g * 0.25) + (tempResult2.b * 0.125);
		//Detail sample result here is worley-perlin fbm.

		//On cloud marked with low erodness, we see cauliflower style, so when doing erodness, we use 1.0f - detail.
		//On cloud marked with high erodness, we see thin line style, so when doing erodness we use detail.
		float detail_modifier = lerp(1.0f - detailsampleResult, detailsampleResult, densityAndErodeness.y);
		sampleResult = RemapClamped(sampleResult, min(0.8, detail_modifier * _DetailStrength), 1.0, 0.0, 1.0);
	}

	//sampleResult = pow(sampleResult, 1.2);
	return max(0, sampleResult) * _CloudDensity;
}

half rand(half3 co)
{
	return frac(sin(dot(co.xyz, half3(12.9898, 78.233, 45.5432))) * 43758.5453) - 0.5f;
}

float _MultiScatteringA;
float _MultiScatteringB;
float _MultiScatteringC;

float fastAcos(float x) {
	return (-0.69813170079773212f * x * x - 0.87266462599716477f) * x + 1.5707963267948966f;
}

//We raymarch to sun using length of pattern 1,2,4,8, corresponding to step value.
//First sample(length 1) should sample at length 0.5, meaning an average inside length 1.
//Second sample should sample at 1.5, meaning an average inside [1, 2],
//Third should sample at 3.0, which is [2, 4]
//Forth at 6.0, meaning [4, 8]
static const float shadowSampleDistance[] = {
	0.5, 1.5, 3.0, 6.0, 12.0
};

static const float shadowSampleContribution[] = {
	1.0f, 1.0f, 2.0f, 4.0f, 8.0f
};

float SampleOpticsDistanceToSun(float3 worldPos) {
	int mipmapOffset = 0.5;
	float opticsDistance = 0.0f;
	[unroll]
	for (int i = 0; i < 5; i++) {
		half3 direction = _WorldSpaceLightPos0;
		float3 samplePoint = worldPos + direction * shadowSampleDistance[i] * TRANSMITTANCE_SAMPLE_STEP;
		float wetness;
		float sampleResult = SampleDensity(samplePoint, mipmapOffset, true, wetness);
		opticsDistance += shadowSampleContribution[i] * TRANSMITTANCE_SAMPLE_STEP * sampleResult;
		mipmapOffset += 0.5;
	}
	return opticsDistance;
}

float SampleEnergy(float3 worldPos, float3 viewDir) {
	float opticsDistance = SampleOpticsDistanceToSun(worldPos);
	float result = 0.0f;
	[unroll]
	for (int octaveIndex = 0; octaveIndex < 2; octaveIndex++) {
		float transmittance = exp(-_ExtinctionCoefficient * pow(_MultiScatteringB, octaveIndex) * opticsDistance);
		float cosTheta = dot(viewDir, _WorldSpaceLightPos0);
		float ecMult = pow(_MultiScatteringC, octaveIndex);
		float phase = lerp(HenryGreenstein(.1f * ecMult, cosTheta), HenryGreenstein((0.99 - _SilverSpread) * ecMult, cosTheta), 0.5f);
		result += phase * transmittance * _ScatteringCoefficient * pow(_MultiScatteringA, octaveIndex);
	}
	return result;
}

//Code from https://area.autodesk.com/blogs/game-dev-blog/volumetric-clouds/.
bool ray_trace_sphere(float3 center, float3 rd, float3 offset, float radius, out float t1, out float t2) {
	float3 p = center - offset;
	float b = dot(p, rd);
	float c = dot(p, p) - (radius * radius);

	float f = b * b - c;
	if (f >= 0.0) {
		t1 = -b - sqrt(f);
		t2 = -b + sqrt(f);
		return true;
	}
	return false;
}

bool resolve_ray_start_end(float3 ws_origin, float3 ws_ray, out float3 start, out float3 end) {
	//case includes on ground, inside atm, above atm.
	float ot1, ot2, it1, it2;
	bool outIntersected = ray_trace_sphere(ws_origin, ws_ray, EARTH_CENTER, EARTH_RADIUS + CLOUDS_END, ot1, ot2);
	if (!outIntersected)
		return false;	//you see nothing.

	bool inIntersected = ray_trace_sphere(ws_origin, ws_ray, EARTH_CENTER, EARTH_RADIUS + CLOUDS_START, it1, it2);
	
	if (inIntersected) {
		if (it1 < 0) {
			//we're on ground.
			start = ws_origin + max(it2, 0) * ws_ray;
			end = ws_origin + ot2 * ws_ray;
		}
		else {
			//we're inside atm, or above atm.
			end = ws_origin + it1 * ws_ray;
			if (ot1 < 0) {
				//inside atm.
				start = ws_origin;
			}
			else {
				//above atm.
				start = ws_origin + ot1 * ws_ray;
			}
		}
	}
	else {
		end = ws_origin + ot2 * ws_ray;
		start = ws_origin + max(ot1, 0) * ws_ray;
	}
	return true;
}
 
float GetDentisy(float3 startPos, float3 dir,float maxSampleDistance, int sample_count, float raymarchOffset, out float intensity,out float depth) {
	float3 sampleStart, sampleEnd;

	if (!resolve_ray_start_end(startPos, dir, sampleStart, sampleEnd)) {
		intensity = 0.0;
		depth = 1e6;
		return 0;
	}

	float sample_step = min(length(sampleEnd - sampleStart) / sample_count, 500);

	depth = 0.0f;

	if (sampleStart.y < -200) {
		intensity = 0.0;
		return 0.0;
	}

	float intTransmittance = 1.0f;
	float alpha = 0;
	intensity = 0;
	bool detailedSample = false;
	int missedStepCount = 0;

	float depthweightsum = 0.00001f;

	float raymarchDistance = raymarchOffset * sample_step;
	[loop]
	for (int j = 0; j < sample_count; j++) {
		float wetness;
		float3 rayPos = sampleStart + dir * raymarchDistance;
		if (raymarchDistance > maxSampleDistance) {
			break;
		}
		float cheapResult = SampleDensity(rayPos, 0, true, wetness);
		detailedSample = cheapResult > 0.0f;
		if (detailedSample) {
			float density = SampleDensity(rayPos, 0, false, wetness);
			float extinction = _ExtinctionCoefficient * density;

			float clampedExtinction = max(extinction, 1e-7);
			float transmittance = exp(-extinction * sample_step);
				
			float luminance = SampleEnergy(rayPos, dir) * lerp(1.0f, 0.3f, wetness);
			float integScatt = (luminance - luminance * transmittance) / clampedExtinction;

			intensity += intTransmittance * integScatt;
			intTransmittance *= transmittance;
			depth += intTransmittance * length(rayPos - startPos);
			depthweightsum += intTransmittance;
			raymarchDistance += sample_step;
		}
		else
		{
			raymarchDistance += sample_step * 2;
		}
	}
	depth /= depthweightsum;
	if (depth == 0.0f) {
		depth = 1e10f;
	}
	//The calculation above will never make intTransmittance to acutally 0.0f(mathematically)
	//and we will never have cloud alpha == 1.0f then. (e.g., the direct sun will shine through cloud even when the transmittance is near 0)
	//To make it simpler, just make sure when transmittance is very close to 0.0f, just treat alpha as 1.0f.
	return saturate(1.001f - intTransmittance);	
}
