#include "UnityCG.cginc"
#define MAX_SAMPLE_COUNT 96
#define CHEAP_SAMPLE_STEP_SIZE (THICKNESS * 6 / MAX_SAMPLE_COUNT)
#define DETAIL_SAMPLE_STEP_SIZE (CHEAP_SAMPLE_STEP_SIZE / 3)

#define THICKNESS 6500
#define CENTER 4750
sampler3D _VolumeTex;
sampler3D _DetailTex;
sampler2D _HeightSignal;
sampler2D _CoverageTex;
float4 _CoverageTex_ST;
sampler2D _DetailNoiseTex;
float _CloudSize;
float _Cutoff;
float _Detail;
half4 _DetailCutoff;
float _DetailTile;
float _Transcluency;
float _Occlude;
float _HgG;
float _DetailMask;
float _CloudDentisy;
float _BeerLaw;
half4 _WindDirection;

float Remap(float original_value, float original_min, float original_max, float new_min, float new_max)
{
	return new_min + (((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
}

float RemapClamped(float original_value, float original_min, float original_max, float new_min, float new_max)
{
	return new_min + (saturate((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
}

float HenryGreenstein(float g, float cosTheta) {
	float pif = 1.0;// (1.0 / (4.0 * 3.1415926f));
	float numerator = 1 - g * g ;
	float denominator = pow(1 + g * g - 2 * g * cosTheta, 1.5);
	return pif * numerator / denominator;
}
//TODO: add "powder" effect.
float Energy(float d, float cosTheta) {
	return exp(-d * _BeerLaw) * HenryGreenstein(_HgG, cosTheta);// *(1.0 - (1 - cosTheta) / 2 * exp(-_Powder * d));
}

float LowresSample(float3 worldPos) {

	float heightPercent = saturate((worldPos.y - CENTER + THICKNESS / 2) / THICKNESS);
	fixed4 tempResult;
	half3 uvw = worldPos;
	uvw.xz += _WindDirection.xy * _WindDirection.z * _Time.y;
//	uvw.xz += _WindDirection.xy * heightPercent * 500;
	uvw = uvw / _CloudSize;
	tempResult = tex3Dlod(_VolumeTex, half4(uvw, 0)).rgba;
	float low_freq_fBm = (tempResult.g * 0.625) + (tempResult.b * 0.25) + (tempResult.a * 0.125);

	// define the base cloud shape by dilating it with the low frequency fBm made of Worley noise.
	float sampleResult = Remap(tempResult.r, -(1.0 - low_freq_fBm), 1.0, 0.0, 1.0);

	//If you don't want to bother a coverage tex, use this.

	float heightSample = tex2Dlod(_HeightSignal, half4(0, heightPercent, 0, 0)).a;
	sampleResult *= heightSample;

	half4 coverageSampleUV = half4(TRANSFORM_TEX((worldPos.xz / _CloudSize), _CoverageTex), 0, 0);
	float coverage = tex2Dlod(_CoverageTex, coverageSampleUV).r;
	//Anvil style.
	//coverage = pow(coverage, RemapClamped(heightPercent, 0.7, 0.8, 1.0, lerp(1.0, 0.5, 0.5)));

	//This doesn't work at all! 
	//sampleResult = RemapClamped(sampleResult, 1 - coverage, 1.0, 0.0, 1.0);
	
	//Just use the old fashion way.
	sampleResult *= coverage;

	sampleResult = saturate(sampleResult);
	return sampleResult;
}

float DetailErode(float3 worldPos, float lowresSample) {
	//return lowresSample;
	float3 tempResult;
	half3 uvw = worldPos / (_DetailTile * _CloudSize);
	//tex2Dlod(_DetailNoiseTex, half4(uvw.x, 0));
	tempResult = tex3Dlod(_DetailTex, half4(uvw, 0)).rgb;
	// build High frequency Worley noise fBm
	float sampleResult = (tempResult.r * 0.625) + (tempResult.g * 0.25) + (tempResult.b * 0.125);

	float heightPercent = saturate((worldPos.y - CENTER + THICKNESS / 2) / THICKNESS);
	float high_freq_noise_modifier = lerp(sampleResult, 1.0 - sampleResult, saturate(heightPercent * 10.0));

	float edge = saturate(_DetailMask - lowresSample ) / _DetailMask;
	//return saturate(lowresSample - _DetailMask * edge * sampleResult );

	return Remap(lowresSample, high_freq_noise_modifier * 0.2, 1.0, 0.0, 1.0);
}

float FullSample(float3 worldPos) {
	float sampleResult = LowresSample(worldPos);
	sampleResult = DetailErode(worldPos, sampleResult);
	return max(sampleResult,0);
}

half rand(half3 co)
{
	return frac(sin(dot(co.xyz, half3(12.9898, 78.233, 45.5432))) * 43758.5453) - 0.5f;
}

float SampleEnergy(float3 worldPos, float3 viewDir) {
	return 0.01;
#define DETAIL_ENERGY_SAMPLE_COUNT 6
	float totalSample = 0;
	//return 0.001;
	for (float i = 1; i <= DETAIL_ENERGY_SAMPLE_COUNT; i++) {
		half3 rand3 = half3(rand(half3(0, i, 0)), rand(half3(1, i, 0)), rand(half3(0, i, 1)));
		half3 direction = _WorldSpaceLightPos0 * 2 + normalize(rand3);
		direction = normalize(direction);
		float3 samplePoint = worldPos 
			+ (direction * i / DETAIL_ENERGY_SAMPLE_COUNT) * _Transcluency;
		totalSample += FullSample(samplePoint);
	}
	float energy = Energy(totalSample / DETAIL_ENERGY_SAMPLE_COUNT * _Occlude, dot(viewDir, _WorldSpaceLightPos0));	//TODO: figure out how HG works.
	return energy;
}

half SampleEnergyCheap(float3 worldPos, float3 viewDir) {
#define CHEAP_ENERGY_SAMPLE_COUNT 2
	float totalSample = 0;
	for (float i = 1; i <= CHEAP_ENERGY_SAMPLE_COUNT; i++) {
		half3 rand3 = half3(rand(half3(0, i, 0)), rand(half3(1, i, 0)), rand(half3(0, i, 1)));
		half3 direction = _WorldSpaceLightPos0 * 2 + normalize(rand3);
		direction = normalize(direction);
		float3 samplePoint = worldPos
			+ (direction * i / CHEAP_ENERGY_SAMPLE_COUNT) * _Transcluency;
		totalSample += FullSample(samplePoint);
	}
	float energy = Energy(totalSample / CHEAP_ENERGY_SAMPLE_COUNT * _Occlude, dot(viewDir, _WorldSpaceLightPos0));	//TODO: figure out how HG works.
	return energy;
}

float GetDentisy(float3 startPos, float3 dir,float maxSampleDistance, float raymarchOffset, out float intensity) {
	float alpha = 0;
	intensity = 0;
	float raymarchDistance = raymarchOffset * (DETAIL_SAMPLE_STEP_SIZE + CHEAP_SAMPLE_STEP_SIZE);
	float sampleStep = CHEAP_SAMPLE_STEP_SIZE;
	bool detailedSample = false;
	int missedStepCount = 0;
	[loop]
	for (int j = 0; j < MAX_SAMPLE_COUNT; j++) {
		float3 rayPos = startPos + dir * raymarchDistance;
		float sampleResult = LowresSample(rayPos);
		if (!detailedSample) {
			if (sampleResult > 0) {
				detailedSample = true;
				raymarchDistance -= sampleStep;
				sampleStep = DETAIL_SAMPLE_STEP_SIZE;
				missedStepCount = 0;
				continue;
			}
		}
		else {
			if (sampleResult <= 0) {
				missedStepCount++;
				if (missedStepCount > 4) {
					detailedSample = false;
					sampleStep = CHEAP_SAMPLE_STEP_SIZE;
					continue;
				}
			}
			sampleResult = DetailErode(rayPos, sampleResult);
			if (sampleResult > 0) {
				float sampledAlpha = sampleResult * DETAIL_SAMPLE_STEP_SIZE * _CloudDentisy;	//换算成alpha值
				float sampledEnergy;				//能量在rayPos向eyePos的辐射率。
				if (alpha > 0.3) {
					sampledEnergy = SampleEnergyCheap(rayPos, dir);				//能量在rayPos向eyePos的辐射率。
					sampledEnergy = SampleEnergy(rayPos, dir);
				}
				else {
					sampledEnergy = SampleEnergy(rayPos, dir);				//能量在rayPos向eyePos的辐射率。
				}
				intensity += (1 - alpha) * sampledEnergy * sampledAlpha;
				alpha += (1 - alpha) * sampledAlpha;
				if (alpha > 1) {
					intensity;
					return 1;
				}
			}
		}
		raymarchDistance += sampleStep;
		if (raymarchDistance > maxSampleDistance)
			break;
	}
	return alpha;
}
