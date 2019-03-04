#include "UnityCG.cginc"
// Upgrade NOTE: excluded shader from DX11, OpenGL ES 2.0 because it uses unsized arrays
#pragma exclude_renderers d3d11 gles
#define MIN_SAMPLE_COUNT 64
#define MAX_SAMPLE_COUNT 96

#define THICKNESS 6000.0
#define CENTER 4500.0

#define EARTH_RADIUS 5000000.0
#define EARTH_CENTER float3(0, -EARTH_RADIUS, 0)

#define CLOUDS_START (CENTER - THICKNESS/2)
#define CLOUDS_END (CENTER + THICKNESS/2)

#define TRANSMITTANCE_SAMPLE_STEP 512.0
#define TRANSMITTANCE_SAMPLE_STEP_COUNT 6
#define TRANSMITTANCE_SAMPLE_LENGTH (TRANSMITTANCE_SAMPLE_STEP_COUNT * TRANSMITTANCE_SAMPLE_STEP)

#define _ScatteringCoefficient 4e-2
#define _ExtinctionCoefficient 4e-2

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
float _SilverIntensity;
float _SilverSpread;

float SampleDensity(float3 worldPos, int lod, bool cheap);

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
	float pif = (1.0 / (4.0 * 3.1415926f));
	float numerator = 1 - g * g ;
	float denominator = pow(1 + g * g - 2 * g * cosTheta, 1.5);
	return pif * numerator / denominator;
}

//float BeerLaw(float d, float cosTheta) {
//	d *= TRANSMITTANCE_SAMPLE_LENGTH;
//	float firstIntes = exp(-d);
//	float secondIntens = exp(-d * 0.25) * 0.7;
//	float secondIntensCurve = .5;
//	float tmp = max(firstIntes, secondIntens * RemapClamped(cosTheta, 0.7, 1.0, secondIntensCurve, secondIntensCurve * 0.25));
//	return tmp;
//}
//  
//float Inscatter(float3 worldPos,float dl, float cosTheta) {
//	float heightPercent = HeightPercent(worldPos);
//	float lodded_density = saturate(SampleDensity(worldPos, 1, false));
//
//	float depth_probability = lerp(0.05 + pow(lodded_density, RemapClamped(heightPercent, 0.3, 0.95, 0.5, 1.3)), 1.0, saturate(dl));
//	float vertical_probability = pow(max(0, Remap(heightPercent, 0.14, 0.28, 0.1, 1.0)), 0.8);
//	return saturate(depth_probability * vertical_probability);
//}

//float Energy(float3 worldPos, float d, float cosTheta) {
//	float hgImproved = max(HenryGreenstein(.1, cosTheta), _SilverIntensity * HenryGreenstein(0.99 - _SilverSpread, cosTheta));
//	return hgImproved * (Inscatter(worldPos, d, cosTheta) + BeerLaw(d, cosTheta));
//}

float SampleDensity(float3 worldPos,int lod, bool cheap) {
	//Store the pos without wind applied.
	float3 unwindWorldPos = worldPos;
	
	//Sample the weather map.
	half4 coverageSampleUV = half4((unwindWorldPos.xz / _WeatherTexSize), 0, 2.5);
	coverageSampleUV.xy = (coverageSampleUV.xy + 0.5);
	float3 weatherData = tex2Dlod(_WeatherTex, coverageSampleUV);
	weatherData *= float3(_CloudCoverageModifier, 1.0, _CloudTypeModifier);
	float coverage = weatherData.r;
	float cloudType = weatherData.b;

	//Calculate the normalized height between[0,1]
	float heightPercent = HeightPercent(worldPos);
	heightPercent = saturate(heightPercent - weatherData.g / 5);	//Don't lift cloud too much, it looks silly.
	if (heightPercent < 0.0001)
		return 0.0;

	//Sample base noise.
	fixed4 tempResult;
	worldPos = ApplyWind(worldPos);
	tempResult = tex3Dlod(_BaseTex, half4(worldPos / _CloudSize * _BaseTile, lod)).rgba;
	float low_freq_fBm = (tempResult.g * .625) + (tempResult.b * 0.25) + (tempResult.a * 0.125);
	float sampleResult = RemapClamped(tempResult.r, 0.0, .8, .0, 1.0);
	sampleResult = RemapClamped(sampleResult, -low_freq_fBm, 1.0, 0.0, 1.0);

	//Sample Height-Density map.
	float2 densityAndErodeness = tex2D(_HeightDensity, float2(cloudType, heightPercent)).rg;

	//Multiply the result to density.
	sampleResult *= densityAndErodeness.x;

	//Clip the result using coverage map.
	sampleResult = RemapClamped(sampleResult, 1.0 - coverage, 1.0, 0.0, 1.0);
	sampleResult *= coverage;
	//sampleResult = pow(sampleResult, .8);
	if (!cheap) {
		float2 curl_noise = tex2Dlod(_CurlNoise, float4(unwindWorldPos.xz / _CloudSize * _CurlTile, 0.0, 1.0)).rg;
		worldPos.xz += curl_noise.rg * (1.0 - heightPercent) * _CloudSize * _CurlStrength;

		float3 tempResult2;
		tempResult2 = tex3Dlod(_DetailTex, half4(worldPos / _CloudSize * _DetailTile, lod)).rgb;
		float detailsampleResult = (tempResult2.r * 0.625) + (tempResult2.g * 0.25) + (tempResult2.b * 0.125);
		float detail_modifier = lerp(detailsampleResult, 1.0 - detailsampleResult, saturate(heightPercent));
		sampleResult = RemapClamped(sampleResult, detail_modifier * _DetailStrength * (1.0 - densityAndErodeness.y), 1.0, 0.0, 1.0);
	}

	//sampleResult = pow(sampleResult, 1.2);
	return max(0, sampleResult) * _CloudDensity;
}

half rand(half3 co)
{
	return frac(sin(dot(co.xyz, half3(12.9898, 78.233, 45.5432))) * 43758.5453) - 0.5f;
}

float SampleEnergy(float3 worldPos, float3 viewDir) {

	float totalSample = 0;
	int mipmapOffset = 0.5;
	float step = 0.5;
	//float transmittance = 1.0f;
	float opticsDistance = 0.0f;
	for (float i = 1; i <= TRANSMITTANCE_SAMPLE_STEP_COUNT; i++) {
		half3 rand3 = half3(rand(half3(0, i, 0)), rand(half3(1, i, 0)), rand(half3(0, i, 1)));
		half3 direction = _WorldSpaceLightPos0 * 2 + normalize(rand3);
		direction = normalize(direction);
		float3 samplePoint = worldPos 
			+ (direction * step * TRANSMITTANCE_SAMPLE_STEP);
		float sampleResult = SampleDensity(samplePoint, mipmapOffset, 0);;
		//transmittance *= exp(-sampleResult * TRANSMITTANCE_SAMPLE_STEP) ;
		opticsDistance += TRANSMITTANCE_SAMPLE_STEP * sampleResult;
		//totalSample += SampleDensity(samplePoint, mipmapOffset, 0);
		mipmapOffset += 0.5;
		step += 1;
	}

	float transmittance = exp(-_ExtinctionCoefficient * opticsDistance);
	float cosTheta = dot(viewDir, _WorldSpaceLightPos0);
	float phase = max(HenryGreenstein(.1, cosTheta), _SilverIntensity * HenryGreenstein(0.99 - _SilverSpread, cosTheta));
	return phase * transmittance * _ScatteringCoefficient;
	//float energy = Energy(worldPos , _Transmittance * totalSample / TRANSMITTANCE_SAMPLE_STEP_COUNT * _CloudDensity, dot(viewDir, _WorldSpaceLightPos0));
	//return energy;
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
 
float GetDentisy(float3 startPos, float3 dir,float maxSampleDistance, float raymarchOffset, out float intensity,out float depth) {
	float3 sampleStart, sampleEnd;

	if (!resolve_ray_start_end(startPos, dir, sampleStart, sampleEnd)) {
		intensity = 0.0;
		depth = 1e6;
		return 0;
	}

	int sample_count = lerp(MAX_SAMPLE_COUNT, MIN_SAMPLE_COUNT, dir.y);	//dir.y ==0 means horizontal, use maximum sample count
	float sample_step = min(length(sampleEnd - sampleStart) / sample_count, 500);

	//depth = length(sampleStart - startPos);
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

	float transmittanceSum = 0.00001f;

	float raymarchDistance = raymarchOffset * sample_step;
	[loop]
	for (int j = 0; j < sample_count; j++) {
		float3 rayPos = sampleStart + dir * raymarchDistance;
		if (!detailedSample) {
			float sampleResult = SampleDensity(rayPos, 0, true);
			if (sampleResult > 0) {
				detailedSample = true;
				raymarchDistance -= sample_step * 2;
				missedStepCount = 0;
				continue;
			}
			else {
				raymarchDistance += sample_step * 2;
			}
		}
		else {
			float sampleResult = SampleDensity(rayPos, 0, false);
			if (sampleResult <= 0) {
				missedStepCount++;
				if (missedStepCount > 10) {
					detailedSample = false;
				}
			}
			else {
				float density = sampleResult;
				float extinction = _ExtinctionCoefficient * density;
				float sampledEnergy = SampleEnergy(rayPos, dir);	//Phase function included.

				float clampedExtinction = max(extinction, 1e-7);
				float transmittance = exp(-extinction * sample_step);
				
				float3 luminance = sampledEnergy;
				float3 integScatt = (luminance - luminance * transmittance) / clampedExtinction;

				intensity += intTransmittance * integScatt;
				intTransmittance *= transmittance;

				//intensity += (1 - alpha) * sampledEnergy * sampledAlpha;
				depth += transmittance * length(rayPos - startPos);
				transmittanceSum += transmittance;
				//alpha += (1 - alpha) * sampledAlpha;

				//if (alpha > 1) {
				//	intensity /= alpha;
				//	depth /= alpha;
				//	return 1;
				//}
			}
			raymarchDistance += sample_step;
		}
	}
	depth /= transmittanceSum;
	if (depth == 0.0f) {
		depth = length(sampleStart - startPos);
	}
	return 1.0f - intTransmittance;
}
