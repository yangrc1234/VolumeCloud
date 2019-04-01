#ifndef __GROUND_HELPER__
#define __GROUND_HELPER__

#include "Common.cginc"
#include "TransmittanceHelper.cginc"
#include "MultipleScatteringHelper.cginc"

IrradianceSpectrum ComputeDirectIrradiance(
	IN(AtmosphereParameters) atmosphere,
	IN(TransmittanceTexture) transmittance_texture,
	uint2 transmittance_size,
	Length r, Number mu_s) {
	assert(r >= atmosphere.bottom_radius && r <= atmosphere.top_radius);
	assert(mu_s >= -1.0 && mu_s <= 1.0);

	Number alpha_s = atmosphere.sun_angular_radius / rad;
	// Approximate average of the cosine factor mu_s over the visible fraction of
	// the Sun disc.
	Number average_cosine_factor =
		mu_s < -alpha_s ? 0.0 : (mu_s > alpha_s ? mu_s :
		(mu_s + alpha_s) * (mu_s + alpha_s) / (4.0 * alpha_s));

	return atmosphere.solar_irradiance *
		GetTransmittanceToTopAtmosphereBoundary(
			atmosphere, transmittance_texture, transmittance_size, r, mu_s) * average_cosine_factor;
}

IrradianceSpectrum ComputeIndirectIrradiance(
	IN(AtmosphereParameters) atmosphere,
	IN(ReducedScatteringTexture) single_rayleigh_scattering_texture,
	IN(ReducedScatteringTexture) single_mie_scattering_texture,
	IN(ScatteringTexture) multiple_scattering_texture,
	uint3 scattering_size,
	Length r, Number mu_s, int scattering_order) {
	assert(r >= atmosphere.bottom_radius && r <= atmosphere.top_radius);
	assert(mu_s >= -1.0 && mu_s <= 1.0);
	assert(scattering_order >= 1);

	const int SAMPLE_COUNT = 32;
	const Angle dphi = pi / Number(SAMPLE_COUNT);
	const Angle dtheta = pi / Number(SAMPLE_COUNT);

	IrradianceSpectrum result =
		IrradianceSpectrum(0.0, 0.0, 0.0);
	vec3 omega_s = vec3(sqrt(1.0 - mu_s * mu_s), 0.0, mu_s);
	for (int j = 0; j < SAMPLE_COUNT / 2; ++j) {
		Angle theta = (Number(j) + 0.5) * dtheta;
		for (int i = 0; i < 2 * SAMPLE_COUNT; ++i) {
			Angle phi = (Number(i) + 0.5) * dphi;
			vec3 omega =
				vec3(cos(phi) * sin(theta), sin(phi) * sin(theta), cos(theta));
			SolidAngle domega = (dtheta / rad) * (dphi / rad) * sin(theta) ;

			Number nu = dot(omega, omega_s);
			result += GetScattering(atmosphere, single_rayleigh_scattering_texture,
				single_mie_scattering_texture, multiple_scattering_texture, scattering_size,
				r, omega.z, mu_s, nu, false /* ray_r_theta_intersects_ground */,
				scattering_order) *
				omega.z * domega;
		}
	}
	return result;
}

vec2 GetIrradianceTextureUvFromRMuS(IN(AtmosphereParameters) atmosphere,
	Length r, Number mu_s, uint2 irradiance_size) {
	assert(r >= atmosphere.bottom_radius && r <= atmosphere.top_radius);
	assert(mu_s >= -1.0 && mu_s <= 1.0);
	Number x_r = (r - atmosphere.bottom_radius) /
		(atmosphere.top_radius - atmosphere.bottom_radius);
	Number x_mu_s = mu_s * 0.5 + 0.5;
	return vec2(GetTextureCoordFromUnitRange(x_mu_s, irradiance_size.x),
		GetTextureCoordFromUnitRange(x_r, irradiance_size.y));
}

void GetRMuSFromIrradianceTextureUv(IN(AtmosphereParameters) atmosphere,
	IN(vec2) uv, OUT(Length) r, OUT(Number) mu_s, uint2 irradiance_size) {
	assert(uv.x >= 0.0 && uv.x <= 1.0);
	assert(uv.y >= 0.0 && uv.y <= 1.0);
	Number x_mu_s = GetUnitRangeFromTextureCoord(uv.x, irradiance_size.x);
	Number x_r = GetUnitRangeFromTextureCoord(uv.y, irradiance_size.y);
	r = atmosphere.bottom_radius +
		x_r * (atmosphere.top_radius - atmosphere.bottom_radius);
	mu_s = ClampCosine(2.0 * x_mu_s - 1.0);
}

IrradianceSpectrum GetIrradiance(
	IN(AtmosphereParameters) atmosphere,
	IN(IrradianceTexture) irradiance_texture,
	uint2 irradiance_size,
	Length r, Number mu_s) {
	vec2 uv = GetIrradianceTextureUvFromRMuS(atmosphere, r, mu_s, irradiance_size);
	return IrradianceSpectrum(tex2Dlod(irradiance_texture, float4(uv,0.0, 0.0)).rgb);
}


IrradianceSpectrum ComputeDirectIrradianceTexture(
	IN(AtmosphereParameters) atmosphere,
	IN(TransmittanceTexture) transmittance_texture,
	uint2 transmittance_size,
	IN(vec2) uv,
	uint2 irrdiance_size) {
	Length r;
	Number mu_s;
	GetRMuSFromIrradianceTextureUv(
		atmosphere, uv, r, mu_s, irrdiance_size);
	return ComputeDirectIrradiance(atmosphere, transmittance_texture, transmittance_size, r, mu_s);
}

IrradianceSpectrum ComputeIndirectIrradianceTexture(
	IN(AtmosphereParameters) atmosphere,
	IN(ReducedScatteringTexture) single_rayleigh_scattering_texture,
	IN(ReducedScatteringTexture) single_mie_scattering_texture,
	IN(ScatteringTexture) multiple_scattering_texture,
	uint3 scattering_size,
	IN(vec2) uv, int scattering_order, uint2 irrdiance_size) {
	Length r;
	Number mu_s;
	GetRMuSFromIrradianceTextureUv(
		atmosphere, uv, r, mu_s, irrdiance_size);
	return ComputeIndirectIrradiance(atmosphere,
		single_rayleigh_scattering_texture, single_mie_scattering_texture,
		multiple_scattering_texture, scattering_size, r, mu_s, scattering_order);
}
#endif