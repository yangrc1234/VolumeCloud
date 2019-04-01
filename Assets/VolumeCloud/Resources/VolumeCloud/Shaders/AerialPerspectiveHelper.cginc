#ifndef __AERIAL_PERSPECTIVE_HELPER__
#define __AERIAL_PERSPECTIVE_HELPER__

#include "Common.cginc"
#include "TransmittanceHelper.cginc"
#include "GroundHelper.cginc"
#include "MultipleScatteringHelper.cginc"
#include "SingleScatteringHelper.cginc"

#define LERP_TEXTURE(dim, name) \
sampler ## dim ## D name ## _1; \
sampler ## dim ## D name ## _2; 

LERP_TEXTURE(2, _Transmittance)
LERP_TEXTURE(2, _GroundIrradiance)
LERP_TEXTURE(3, _SingleRayleigh)
LERP_TEXTURE(3, _SingleMie)
LERP_TEXTURE(3, _MultipleScattering)

float2 _TransmittanceSize;
float3 _ScatteringSize;
float2 _GroundIrradianceSize;

float _LerpValue;

float3 GetTransmittanceLerped(float r, float mu, float d, bool intersect_ground) {
	AtmosphereParameters atm = GetAtmParameters();
	float3 lerp1 = GetTransmittance(
		atm, _Transmittance_1, _TransmittanceSize, r, mu, d, intersect_ground);
	float3 lerp2 = GetTransmittance(
		atm, _Transmittance_2, _TransmittanceSize, r, mu, d, intersect_ground);

	return lerp(lerp1, lerp2, _LerpValue);
}

float3 GetTransmittanceToTopAtmosphereBoundaryLerped(float r, float mu) {
	AtmosphereParameters atm = GetAtmParameters();
	float3 lerp1 = GetTransmittanceToTopAtmosphereBoundary(
		atm, _Transmittance_1, _TransmittanceSize, r, mu);
	float3 lerp2 = GetTransmittanceToTopAtmosphereBoundary(
		atm, _Transmittance_2, _TransmittanceSize, r, mu);

	return lerp(lerp1, lerp2, _LerpValue);
}

void CalculateRMuMusFromPosViewdir(AtmosphereParameters atm, float3 pos, float3 view_ray, float3 sun_direction, OUT(float) r, OUT(float) mu, OUT(float) mu_s, OUT(float) nu) {
	float3 camera = pos + float3(0, atm.bottom_radius, 0);
	r = max(atm.bottom_radius + 0.5f, length(camera));
	float rmu = dot(camera, view_ray);
	mu = rmu / r;
	mu_s = dot(camera, sun_direction) / r;
	nu = dot(view_ray, sun_direction);
}

void CalculateRMuMusForDistancePoint(AtmosphereParameters atm, Length r, Number mu, Number mu_s, float nu, Number d, OUT(Length) r_d, OUT(Number) mu_d, OUT(Number) mu_s_d) {

	r_d = ClampRadius(atm, sqrt(d * d + 2.0 * r * mu * d + r * r));
	r_d = max(atm.bottom_radius + 0.5f, r_d);
	mu_d = ClampCosine((r * mu + d) / r_d);
	mu_s_d = ClampCosine((r * mu_s + d * nu) / r_d);
}

float3 InternalGetRayleighLerped(AtmosphereParameters atm, float r, float mu, float mu_s, float nu, bool ray_r_mu_intersects_ground) {

	return  SampleScatteringLerped(atm,
			_SingleRayleigh_1,
			_SingleRayleigh_2,
			_LerpValue,
			_ScatteringSize,
			r, mu, mu_s,
			ray_r_mu_intersects_ground) *
		RayleighPhaseFunction(nu);
}

float3 InternalGetMieLerped(AtmosphereParameters atm, float r, float mu, float mu_s, float nu, bool ray_r_mu_intersects_ground) {
	return SampleScatteringLerped(atm,
			_SingleMie_1,
			_SingleMie_2,
			_LerpValue,
			_ScatteringSize,
			r, mu, mu_s,
			ray_r_mu_intersects_ground) *
		MiePhaseFunction(atm.mie_phase_function_g, nu);
}

float3 InternalGetLerpedGroundIrradiance(AtmosphereParameters atm, float r, float mu, float mu_s) {
	return lerp(GetIrradiance(atm, _GroundIrradiance_1, _GroundIrradianceSize, r, mu_s), GetIrradiance(atm, _GroundIrradiance_2, _GroundIrradianceSize, r, mu_s), _LerpValue);
}

float3 InternalGetMultipleLerped(AtmosphereParameters atm, float r, float mu, float mu_s, float nu, bool ray_r_mu_intersects_ground) {
	return
		SampleScatteringLerped(atm,
			_MultipleScattering_1,
			_MultipleScattering_2,
			_LerpValue,
			_ScatteringSize,
			r, mu, mu_s,
			ray_r_mu_intersects_ground);
}

void ComputeSingleScattering(
	IN(AtmosphereParameters) atmosphere,
	IN(TransmittanceTexture) transmittance_texture,
	uint2 texture_size,
	Length r, Number mu, Number mu_s, Number nu,
	bool ray_r_mu_intersects_ground,
	OUT(IrradianceSpectrum) rayleigh, OUT(IrradianceSpectrum) mie);

float3 GetTotalScatteringLerped(float r, float mu, float mu_s, float nu, bool ray_r_mu_intersects_ground) {
	AtmosphereParameters atm = GetAtmParameters();
	return
		InternalGetRayleighLerped(atm, r, mu, mu_s, nu, ray_r_mu_intersects_ground)
		+ InternalGetMieLerped(atm, r, mu, mu_s, nu, ray_r_mu_intersects_ground)
		+ InternalGetMultipleLerped(atm, r, mu, mu_s, nu, ray_r_mu_intersects_ground);
}

float3 GetTotalScatteringLerped(float r, float mu, float mu_s, float nu) {
	AtmosphereParameters atm = GetAtmParameters();
	bool ray_r_mu_intersects_ground = RayIntersectsGround(atm, r, mu);
	return GetTotalScatteringLerped(r, mu, mu_s, nu, ray_r_mu_intersects_ground);
}

float3 EvaluateSunDiskRadianceOfUnitRadiance(AtmosphereParameters atm, float r, float mu, float nu) {
	//Evaluate sun's solid angle by formula omega = 2 * PI * ( 1 - cos(sun_angular_radius)) (https://en.wikipedia.org/wiki/Solid_angle)
	float cos_sun_angular_radius = cos(atm.sun_angular_radius);
	float radianceTransmitted = max(0.0f, (nu - cos_sun_angular_radius) / (1.0f - cos_sun_angular_radius));
	return radianceTransmitted;
}


/*
===============================
Camera volume stuff.
===============================
*/
sampler3D _CameraVolumeTransmittance;
sampler3D _CameraVolumeScattering;

float3 GetTransmittanceWithCameraVolume(float3 uvw) {
	return tex3Dlod(_CameraVolumeTransmittance, float4(uvw, 0.0f)).rgb;
}

float3 GetScatteringWithCameraVolume(float3 uvw) {
	return tex3Dlod(_CameraVolumeScattering, float4(uvw, 0.0f)).rgb;
}

#endif