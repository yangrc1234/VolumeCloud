#include "UnityCG.cginc"
#define MIN_SAMPLE_COUNT 56
#define MAX_SAMPLE_COUNT 96

#define THICKNESS 6500
#define CENTER 4750
sampler3D _VolumeTex;
float _BaseShapeTile;
sampler3D _DetailTex;
sampler2D _HeightSignal;
sampler2D _CoverageTex;
sampler2D _CurlNoise;
float4 _CoverageTex_ST;
sampler2D _DetailNoiseTex;
float _CloudSize;
float _DetailTile;
float _DetailSize;
float _CurlTile;
float _CurlSize;
float _CloudDentisy;
float _BeerLaw;
half4 _WindDirection;
float _SilverIntensity;
float _SilverSpread;

float LowresSample(float3 worldPos, int lod);
float FullSample(float3 worldPos, int lod);

float Remap(float original_value, float original_min, float original_max, float new_min, float new_max)
{
	return new_min + (((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
}

float RemapClamped(float original_value, float original_min, float original_max, float new_min, float new_max)
{
	return new_min + (saturate((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
}

float SampleHeight(float heightPercent,float cloudType) {
	float stratos = RemapClamped(heightPercent, 0.0, 0.1, 0.0, 1.0) * RemapClamped(heightPercent, 0.15, 0.4, 1.0, 0.0);
	float cumulus = RemapClamped(heightPercent, 0.0, .15, 0.0, 1.0) * RemapClamped(heightPercent, .3, 0.9, 1.0, 0.0);
	return lerp(stratos, cumulus, cloudType);
}

float3 ApplyWind(float3 worldPos) {
	float heightPercent = saturate((worldPos.y - CENTER + THICKNESS / 2) / THICKNESS);
	
	
	// skew in wind direction
	// worldPos.yz += heightPercent * _WindDirection.xy * cloud_top_offset;

	//animate clouds in wind direction and add a small upward bias to the wind direction
	worldPos.xz += (_WindDirection.xy + float3(0.0, 0.1, 0.0)) * _Time.y * _WindDirection.z;

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
	float secondIntensCurve = 0.5;
	float tmp = max(firstIntes, secondIntens * RemapClamped(cosTheta, 0.7, 1.0, secondIntensCurve, secondIntensCurve * 0.25));
	return tmp;
}

float Inscatter(float3 worldPos,float dl, float cosTheta) {
	float heightPercent = saturate((worldPos.y - CENTER + THICKNESS / 2) / THICKNESS);
	float lodded_density = saturate(FullSample(worldPos, 1));
	float depth_probability = 0.05 + pow(lodded_density, RemapClamped(heightPercent, 0.3, 0.85, 0.5, 2.0));
	depth_probability = lerp(depth_probability, 1.0, saturate(1 - 50 * dl));		//I think the original one in ppt is wrong.(or they use dl as "brigtness" rather than "occlusion"
	float vertical_probability = pow(max(0, Remap(heightPercent, 0.07, 0.14, 0.1, 1.0)), 0.8);
	return saturate(depth_probability * 1);
}

float Energy(float3 worldPos, float d, float cosTheta) {
	float hgImproved = max(HenryGreenstein(0.05, cosTheta), _SilverIntensity * HenryGreenstein(0.99 - _SilverSpread, cosTheta));
	return hgImproved * BeerLaw(d, cosTheta) *3.0 * Inscatter(worldPos, d, cosTheta);	// waiting for fix.
}

float LowresSample(float3 worldPos,int lod, bool cheap) {

	float heightPercent = saturate((worldPos.y - CENTER + THICKNESS / 2) / THICKNESS);
	fixed4 tempResult;
	float3 unwindWorldPos = worldPos;
	worldPos = ApplyWind(worldPos);
	tempResult = tex3Dlod(_VolumeTex, half4(worldPos / _CloudSize * _BaseShapeTile, lod)).rgba;
	float low_freq_fBm = (tempResult.g * 0.625) + (tempResult.b * 0.25) + (tempResult.a * 0.125);

	// define the base cloud shape by dilating it with the low frequency fBm made of Worley noise.
	float sampleResult = Remap(tempResult.r, -(1.0 - low_freq_fBm), 1.0, 0.0, 1.0);

	half4 coverageSampleUV = half4(TRANSFORM_TEX((unwindWorldPos.xz / _CloudSize), _CoverageTex), 0, 0);
	float3 weatherData = tex2Dlod(_CoverageTex, coverageSampleUV);
	float coverage = weatherData.r;
	sampleResult *= SampleHeight(heightPercent, weatherData.b);
	//Anvil style.
	//coverage = pow(coverage, RemapClamped(heightPercent, 0.7, 0.8, 1.0, lerp(1.0, 0.5, 0.5)));

	sampleResult = RemapClamped(sampleResult, 1 - coverage, 1.0, 0.0, 1.0);
	 
	sampleResult *= coverage;
	
	if (!cheap) {
		float2 curl_noise = tex2Dlod(_CurlNoise, float4(worldPos.xz / (_CloudSize * _CurlTile), 0.0, 1.0)).rg;
		worldPos.xz += curl_noise.rg * (1.0 - heightPercent) * _CloudSize * _CurlSize;

		float3 tempResult2;
		tempResult2 = tex3Dlod(_DetailTex, half4(worldPos / _CloudSize * _DetailTile, lod)).rgb;
		float detailsampleResult = (tempResult2.r * 0.625) + (tempResult2.g * 0.25) + (tempResult2.b * 0.125);

		float high_freq_noise_modifier = lerp(detailsampleResult, 1.0 - detailsampleResult, saturate(heightPercent * 10.0));

		sampleResult = Remap(sampleResult, high_freq_noise_modifier * _DetailSize, 1.0, 0.0, 1.0);
	} 
	
	return saturate(sampleResult);
}

float FullSample(float3 worldPos, int lod) {
	float sampleResult = LowresSample(worldPos, lod, false);
	return max(sampleResult,0);
}

half rand(half3 co)
{
	return frac(sin(dot(co.xyz, half3(12.9898, 78.233, 45.5432))) * 43758.5453) - 0.5f;
}

float SampleEnergy(float3 worldPos, float3 viewDir) {
#define DETAIL_ENERGY_SAMPLE_COUNT 6

	float totalSample = 0;
	int mipmapOffset = 0.5;
	for (float i = 1; i <= DETAIL_ENERGY_SAMPLE_COUNT; i++) {
		half3 rand3 = half3(rand(half3(0, i, 0)), rand(half3(1, i, 0)), rand(half3(0, i, 1)));
		half3 direction = _WorldSpaceLightPos0 * 2 + normalize(rand3);
		direction = normalize(direction);
		float3 samplePoint = worldPos 
			+ (direction * i / DETAIL_ENERGY_SAMPLE_COUNT) * 1024;
		totalSample += FullSample(samplePoint, mipmapOffset);
		mipmapOffset += 0.5;
	}
	float energy = Energy(worldPos ,totalSample / DETAIL_ENERGY_SAMPLE_COUNT * _CloudDentisy, dot(viewDir, _WorldSpaceLightPos0));
	return energy;
}

float GetDentisy(float3 startPos, float3 dir,float maxSampleDistance, float raymarchOffset, out float intensity,out float depth) {

	/* Atmosphere shape correction 
	*  by 
	*  1. Extend ray to atmosphere.
	*  2. Calculate corrected dir.
	*  3. moving raypos up to where cloud begin.
	*/

	float earthRadius = 6500000;
	float3 earthCenter = float3(0, -earthRadius, 0);
	float3 ominusc = startPos - earthCenter;
	float toAtmosphereDistance;
	if (startPos.y > CENTER - THICKNESS / 2) {
		toAtmosphereDistance = 1.0;
	}
	else {
		toAtmosphereDistance = -dot(dir, ominusc) + pow(pow(dot(dir, ominusc), 2) - dot(ominusc, ominusc) + pow(CENTER - THICKNESS / 2 + earthRadius, 2), 0.5);
	}

	depth = toAtmosphereDistance;
	startPos += dir * toAtmosphereDistance ;		//step 1

	int sample_count = lerp(MAX_SAMPLE_COUNT, MIN_SAMPLE_COUNT, dir.y);	//dir.y ==0 means horizontal, use maximum sample count.(actually doesn't happen after dir is corrected.)

	float3 edge1 = float3(startPos.x, 0, startPos.z);						//edge1 is a vector from (0,0,0) to startPos but y-component is zero.
	float3 edge2 = float3(startPos.x, startPos.y + earthRadius, startPos.z);	//edge2 is from earth center to startPos.
	float sinTheta = dot(normalize(edge1), normalize(edge2));				//these edges form exactly the same angle with the angle from (0,1,0) to corrected dir
	dir = normalize(lerp(dir, float3(0,4,0), sinTheta));		//step 2, this is just a approximation, i'm poor at math, if u have better idea tell me plz.
	float sample_step = lerp(6, 1, saturate(min(dir.y, .075) / .075)) * 100;
	
	float distanceToCenter = length(startPos.xz);
	float fakeHeightOffset = earthRadius - pow(earthRadius * earthRadius - 4 * distanceToCenter, 0.5);
	fakeHeightOffset /= 2;
	if (startPos.y < -5000) {
		intensity = 0;
		depth = 0;
		return 0;
	}

	startPos.y = max(startPos.y,CENTER - THICKNESS / 2);

	float alpha = 0;
	intensity = 0;
	bool detailedSample = false;
	int missedStepCount = 0;

	float raymarchDistance = raymarchOffset * sample_step;
	[loop]
	for (int j = 0; j < sample_count; j++) {
		float3 rayPos = startPos + dir * raymarchDistance;
		if (!detailedSample) {
			float sampleResult = LowresSample(rayPos, 0, true);
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
			float sampleResult = LowresSample(rayPos, 0, false);
			if (sampleResult <= 0) {
				missedStepCount++;
				if (missedStepCount > 10) {
					detailedSample = false;
				}
			}
			else {
				float sampledAlpha = sampleResult * sample_step * _CloudDentisy;	//换算成alpha值
				float sampledEnergy;				//能量在rayPos向eyePos的辐射率。
				sampledEnergy = SampleEnergy(rayPos, dir);
				intensity += (1 - alpha) * sampledEnergy * sampledAlpha;
				if (alpha < .5) {
					//record depth.
				//	depth = raymarchDistance;
				}
				alpha += (1 - alpha) * sampledAlpha;
				if (alpha > 1) {
					return 1;
				}
			}
			raymarchDistance += sample_step;
		}
	}
	return alpha;
}
