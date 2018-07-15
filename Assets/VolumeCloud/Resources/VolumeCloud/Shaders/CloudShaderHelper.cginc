#include "UnityCG.cginc"
#define MIN_SAMPLE_COUNT 128
#define MAX_SAMPLE_COUNT 128

#define THICKNESS 5000.0
#define CENTER 4750.0

#define EARTH_RADIUS 5000000.0
#define EARTH_CENTER float3(0, -EARTH_RADIUS, 0)

#define CLOUDS_START (CENTER - THICKNESS/2)
#define CLOUDS_END (CENTER + THICKNESS/2)

//Base shape
sampler3D _BaseTex;
float _BaseTile;
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
float _BeerLaw;
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

float4 LerpGradient(float cloudType)
{
	float4 cloudGradient1 = float4(0, 0.07, 0.08, 0.15);
	float4 cloudGradient2 = float4(0, 0.2, 0.42, 0.6);
	float4 cloudGradient3 = float4(0, 0.08, 0.75, 1);

	float a = 1.0f - saturate(cloudType / 0.5f);
	float b = 1.0f - abs(cloudType - 0.5f) * 2.0f;
	float c = saturate(cloudType - 0.5f) * 2.0f;

	return cloudGradient1 * a + cloudGradient2 * b + cloudGradient3 * c;
}

float CalculateGradient(float a, float4 gradient)
{
	return smoothstep(gradient.x, gradient.y, a) - smoothstep(gradient.z, gradient.w, a); 
}

float HeightPercent(float3 worldPos) {
	float sqrMag = worldPos.x * worldPos.x + worldPos.z * worldPos.z;

	float heightOffset = EARTH_RADIUS - sqrt(max(0.0, EARTH_RADIUS * EARTH_RADIUS - sqrMag));

	return saturate((worldPos.y + heightOffset - CENTER + THICKNESS / 2) / THICKNESS);
}

//from gamedev post
float SampleHeight(float heightPercent,float cloudType) {

	return RemapClamped(heightPercent, 0.0, 1.0, 1.0, 0.2) * CalculateGradient(heightPercent, LerpGradient(cloudType));
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
	float pif = 1.0;// (1.0 / (4.0 * 3.1415926f));
	float numerator = 1 - g * g ;
	float denominator = pow(1 + g * g - 2 * g * cosTheta, 1.5);
	return pif * numerator / denominator;
}

float BeerLaw(float d, float cosTheta) {
	d *= _BeerLaw;
	float firstIntes = exp(-d);
	float secondIntens = exp(-d * 0.25) * 0.7;
	float secondIntensCurve = .5;
	float tmp = max(firstIntes, secondIntens * RemapClamped(cosTheta, 0.7, 1.0, secondIntensCurve, secondIntensCurve * 0.25));
	return tmp;
}
  
float Inscatter(float3 worldPos,float dl, float cosTheta) {
	float heightPercent = HeightPercent(worldPos);
	float lodded_density = saturate(SampleDensity(worldPos, 1, false));
	float depth_probability = 0.05 + pow(lodded_density, RemapClamped(heightPercent, 0.3, 0.85, 0.5, 2.0));
	depth_probability = lerp(depth_probability, 1.0, saturate(dl * 50));
	float vertical_probability = pow(max(0, Remap(heightPercent, 0.0, 0.14, 0.1, 1.0)), 0.8);
	return saturate(depth_probability * vertical_probability);
}

float Energy(float3 worldPos, float d, float cosTheta) {
	float hgImproved = max(HenryGreenstein(.1, cosTheta), _SilverIntensity * HenryGreenstein(0.99 - _SilverSpread, cosTheta));
	return Inscatter(worldPos, d, cosTheta) *hgImproved * BeerLaw(d, cosTheta) * 5.0;
}

float SampleDensity(float3 worldPos,int lod, bool cheap) {

	float heightPercent = HeightPercent(worldPos);
	fixed4 tempResult;
	float3 unwindWorldPos = worldPos;
	worldPos = ApplyWind(worldPos);
	tempResult = tex3Dlod(_BaseTex, half4(worldPos / _CloudSize * _BaseTile, lod)).rgba;
	tempResult = 1 - tempResult;

	float low_freq_fBm = (tempResult.g * 0.5) + (tempResult.b * 0.25) + (tempResult.a * 0.125);
	// define the base cloud shape by dilating it with the low frequency fBm made of Worley noise.
	float sampleResult = Remap(tempResult.r, -2.0 * low_freq_fBm, 1.0, 0.0, 1.0);
	//float sampleResult = tempResult.r * .6 + low_freq_fBm;

	half4 coverageSampleUV = half4((unwindWorldPos.xz / _WeatherTexSize), 0, 2.5);
	coverageSampleUV.xy = (coverageSampleUV.xy + 0.5);	
	float3 weatherData = tex2Dlod(_WeatherTex, coverageSampleUV);
	weatherData *= float3(_CloudCoverageModifier, 1.0, _CloudTypeModifier);
	float coverage = weatherData.r;
	sampleResult *= SampleHeight(heightPercent, weatherData.b);
	//Anvil style.
	//coverage = pow(coverage, RemapClamped(heightPercent, 0.7, 0.8, 1.0, lerp(1.0, 0.5, 1.0)));

	sampleResult = RemapClamped(sampleResult, 1.0 - coverage, 1.0, 0.0, 1.0);	//different from slider.
	 
	sampleResult *= coverage;

	sampleResult *= Remap(weatherData.g,0,1,.5,1.0);
	 
	if (!cheap) {
		float2 curl_noise = tex2Dlod(_CurlNoise, float4(unwindWorldPos.xz / _CloudSize * _CurlTile, 0.0, 1.0)).rg;
		worldPos.xz += curl_noise.rg * (1.0 - heightPercent) * _CloudSize * _CurlStrength;

		float3 tempResult2;
		tempResult2 = tex3Dlod(_DetailTex, half4(worldPos / _CloudSize * _DetailTile, lod)).rgb;
		float detailsampleResult = (tempResult2.r * 0.625) + (tempResult2.g * 0.25) + (tempResult2.b * 0.125);
		detailsampleResult = 1.0 - detailsampleResult;
		float detail_modifier = lerp(detailsampleResult, 1.0 - detailsampleResult, saturate(heightPercent * 1));
		sampleResult = Remap(sampleResult, detail_modifier * _DetailStrength, 1.0, 0.0, 1.0);
	}
	
	return max(0, sampleResult);
}

half rand(half3 co)
{
	return frac(sin(dot(co.xyz, half3(12.9898, 78.233, 45.5432))) * 43758.5453) - 0.5f;
}

float SampleEnergy(float3 worldPos, float3 viewDir) {
#define DETAIL_ENERGY_SAMPLE_COUNT 6

	float totalSample = 0;
	int mipmapOffset = 0.5;
	float step = 1;
	for (float i = 1; i <= DETAIL_ENERGY_SAMPLE_COUNT; i++) {
		half3 rand3 = half3(rand(half3(0, i, 0)), rand(half3(1, i, 0)), rand(half3(0, i, 1)));
		half3 direction = _WorldSpaceLightPos0 * 2 + normalize(rand3);
		direction = normalize(direction);
		float3 samplePoint = worldPos 
			+ (direction * step / DETAIL_ENERGY_SAMPLE_COUNT) * 256;
		totalSample += SampleDensity(samplePoint, mipmapOffset, 0);
		mipmapOffset += 0.5;
		step *= 2;
	}
	float energy = Energy(worldPos ,totalSample / DETAIL_ENERGY_SAMPLE_COUNT * _CloudDensity, dot(viewDir, _WorldSpaceLightPos0));
	return energy;
}

//Code from https://area.autodesk.com/blogs/game-dev-blog/volumetric-clouds/.
float2 ray_trace_sphere(float3 center, float3 rd, float3 offset, float radius) {
	float3 p = center - offset;
	float b = dot(p, rd);
	float c = dot(p, p) - (radius * radius);

	float f = b * b - c;
	if (f >= 0.0) {
		float t1 = -b - sqrt(f);
		float t2 = -b + sqrt(f);
		return float2(t1, t2);
	}
	return -1.0;
}
//same as above
void find_atmosphere_intersections(float3 ws_origin, float3 ws_ray, out float3 start, out float3 end) {
	float2 inner_solutions = ray_trace_sphere(ws_origin, ws_ray, EARTH_CENTER, EARTH_RADIUS + CLOUDS_START);
	float2 outer_solutions = ray_trace_sphere(ws_origin, ws_ray, EARTH_CENTER, EARTH_RADIUS + CLOUDS_END);
	float t_inner_sphere = max(inner_solutions.x, inner_solutions.y);
	float t_outer_sphere = max(outer_solutions.x, outer_solutions.y);

	start = ws_origin + ws_ray * t_inner_sphere;
	end = ws_origin + ws_ray * t_outer_sphere;
}
 
float GetDentisy(float3 startPos, float3 dir,float maxSampleDistance, float raymarchOffset, out float intensity,out float depth) {
	float3 sampleStart, sampleEnd;
	find_atmosphere_intersections(startPos, dir, sampleStart, sampleEnd);

	int sample_count = lerp(MAX_SAMPLE_COUNT, MIN_SAMPLE_COUNT, dir.y);	//dir.y ==0 means horizontal, use maximum sample count
	float sample_step = length(sampleEnd - sampleStart) / sample_count;

	depth = length(sampleStart - startPos);

	if (sampleStart.y < -200) {
		intensity = 0.0;
		return 0.0;
	}

	float alpha = 0;
	intensity = 0;
	bool detailedSample = false;
	int missedStepCount = 0;

	float raymarchDistance = raymarchOffset * sample_step;
	[loop]
	for (int j = 0; j < sample_count; j++) {
		float3 rayPos = sampleStart + dir * raymarchDistance;
		if (!detailedSample) {
			float sampleResult = SampleDensity(rayPos, 0, true);
			if (sampleResult > 0) {
				detailedSample = true;
				raymarchDistance -= sample_step * 3;
				missedStepCount = 0;
				continue;
			}
			else {
				raymarchDistance += sample_step * 3;
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
				float sampledAlpha = sampleResult * sample_step * _CloudDensity;
				float sampledEnergy = SampleEnergy(rayPos, dir);
				intensity += (1 - alpha) * sampledEnergy * sampledAlpha;
				alpha += (1 - alpha) * sampledAlpha;
				if (alpha > 1) {
					intensity /= alpha;
					return 1;
				}
			}
			raymarchDistance += sample_step;
		}
	}
	return alpha;
}
