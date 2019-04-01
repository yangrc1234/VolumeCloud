#ifndef __MULTIPLE_SCATTERING_HELPER__
#define __MULTIPLE_SCATTERING_HELPER__

#include "Common.cginc"
#include "TransmittanceHelper.cginc" 
#include "SingleScatteringHelper.cginc"

IrradianceSpectrum GetIrradiance(
	IN(AtmosphereParameters) atmosphere,
	IN(IrradianceTexture) irradiance_texture, uint2 irradiance_size,
	Length r, Number mu_s);

RadianceDensitySpectrum ComputeScatteringDensity(
	IN(AtmosphereParameters) atmosphere,
	IN(TransmittanceTexture) transmittance_texture,
	uint2 transmittance_size,
	IN(ReducedScatteringTexture) single_rayleigh_scattering_texture,
	IN(ReducedScatteringTexture) single_mie_scattering_texture,
	IN(ScatteringTexture) multiple_scattering_texture,
	uint3 scattering_size,
	IN(IrradianceTexture) irradiance_texture,
	uint2 irradiance_size,
	Length r, Number mu, Number mu_s, Number nu, int scattering_order) {
	assert(r >= atmosphere.bottom_radius && r <= atmosphere.top_radius);
	assert(mu >= -1.0 && mu <= 1.0);
	assert(mu_s >= -1.0 && mu_s <= 1.0);
	assert(scattering_order >= 2);


	// Compute unit direction vectors for the zenith, the view direction omega and
	// and the sun direction omega_s, such that the cosine of the view-zenith
	// angle is mu, the cosine of the sun-zenith angle is mu_s, and the cosine of
	// the view-sun angle is nu. The goal is to simplify computations below.
	vec3 zenith_direction = vec3(0.0, 0.0, 1.0);
	vec3 omega = vec3(sqrt(1.0 - mu * mu), 0.0, mu);
	Number sun_dir_x = omega.x == 0.0 ? 0.0 : (nu - mu * mu_s) / omega.x;
	Number sun_dir_y = sqrt(max(1.0 - sun_dir_x * sun_dir_x - mu_s * mu_s, 0.0));
	vec3 omega_s = vec3(sun_dir_x, sun_dir_y, mu_s);

	const int SAMPLE_COUNT = 16;
	const Angle dphi = pi / Number(SAMPLE_COUNT);
	const Angle dtheta = pi / Number(SAMPLE_COUNT);
	RadianceDensitySpectrum rayleigh_mie =
		RadianceDensitySpectrum(0.0, 0.0, 0.0);

	// Nested loops for the integral over all the incident directions omega_i.
	for (int l = 0; l < SAMPLE_COUNT; ++l) {
		Angle theta = (Number(l) + 0.5) * dtheta;
		Number cos_theta = cos(theta);
		Number sin_theta = sin(theta);
		bool ray_r_theta_intersects_ground =
			RayIntersectsGround(atmosphere, r, cos_theta);

		// The distance and transmittance to the ground only depend on theta, so we
		// can compute them in the outer loop for efficiency.
		Length distance_to_ground = 0.0 * m;
		DimensionlessSpectrum transmittance_to_ground = DimensionlessSpectrum(0.0, 0.0, 0.0);
		DimensionlessSpectrum ground_albedo = DimensionlessSpectrum(0.0, 0.0, 0.0);
		if (ray_r_theta_intersects_ground) {
			distance_to_ground =
				DistanceToBottomAtmosphereBoundary(atmosphere, r, cos_theta);
			transmittance_to_ground =
				GetTransmittance(atmosphere, transmittance_texture, transmittance_size, r, cos_theta,
					distance_to_ground, true /* ray_intersects_ground */);
			ground_albedo = atmosphere.ground_albedo;
		}

		for (int m = 0; m < 2 * SAMPLE_COUNT; ++m) {
			Angle phi = (Number(m) + 0.5) * dphi;
			vec3 omega_i =
				vec3(cos(phi) * sin_theta, sin(phi) * sin_theta, cos_theta);
			SolidAngle domega_i = (dtheta / rad) * (dphi / rad) * sin(theta) * sr;

			// The radiance L_i arriving from direction omega_i after n-1 bounces is
			// the sum of a term given by the precomputed scattering texture for the
			// (n-1)-th order:
			Number nu1 = dot(omega_s, omega_i);
			RadianceSpectrum incident_radiance = GetScattering(atmosphere,
				single_rayleigh_scattering_texture, single_mie_scattering_texture,
				multiple_scattering_texture, scattering_size, r, omega_i.z, mu_s, nu1,
				ray_r_theta_intersects_ground, scattering_order - 1);

			// and of the contribution from the light paths with n-1 bounces and whose
			// last bounce is on the ground. This contribution is the product of the
			// transmittance to the ground, the ground albedo, the ground BRDF, and
			// the irradiance received on the ground after n-2 bounces.
			vec3 ground_normal =
				normalize(zenith_direction * r + omega_i * distance_to_ground);
			IrradianceSpectrum ground_irradiance = GetIrradiance(
				atmosphere, irradiance_texture, irradiance_size, atmosphere.bottom_radius,
				dot(ground_normal, omega_s));
			incident_radiance += transmittance_to_ground *
				ground_albedo * (1.0 / (PI * sr)) * ground_irradiance;

			// The radiance finally scattered from direction omega_i towards direction
			// -omega is the product of the incident radiance, the scattering
			// coefficient, and the phase function for directions omega and omega_i
			// (all this summed over all particle types, i.e. Rayleigh and Mie).
			Number nu2 = dot(omega, omega_i);
			Number rayleigh_density = GetScaleHeight(
				r - atmosphere.bottom_radius, atmosphere.rayleigh_scale_height);
			Number mie_density = GetScaleHeight(
				r - atmosphere.bottom_radius, atmosphere.mie_scale_height);

			rayleigh_mie += incident_radiance * (
				atmosphere.rayleigh_scattering * rayleigh_density *
				RayleighPhaseFunction(nu2) +
				atmosphere.mie_scattering * mie_density *
				MiePhaseFunction(atmosphere.mie_phase_function_g, nu2)) *
				domega_i;
		}
	}
	return rayleigh_mie;
}

RadianceSpectrum ComputeMultipleScattering(
	IN(AtmosphereParameters) atmosphere,
	IN(TransmittanceTexture) transmittance_texture,
	uint2 transmittance_size,
	IN(ScatteringDensityTexture) scattering_density_texture,
	uint3 scattering_size,
	Length r, Number mu, Number mu_s, Number nu,
	bool ray_r_mu_intersects_ground) {
	assert(r >= atmosphere.bottom_radius && r <= atmosphere.top_radius);
	assert(mu >= -1.0 && mu <= 1.0);
	assert(mu_s >= -1.0 && mu_s <= 1.0);

	// Number of intervals for the numerical integration.
	const int SAMPLE_COUNT = 50;
	// The integration step, i.e. the length of each integration interval.
	Length dx =
		DistanceToNearestAtmosphereBoundary(
			atmosphere, r, mu, ray_r_mu_intersects_ground) /
		Number(SAMPLE_COUNT);
	// Integration loop.
	RadianceSpectrum rayleigh_mie_sum =
		RadianceSpectrum(0.0, 0.0, 0.0);
	for (int i = 0; i <= SAMPLE_COUNT; ++i) {
		Length d_i = Number(i) * dx;

		// The r, mu and mu_s parameters at the current integration point (see the
		// single scattering section for a detailed explanation).
		Length r_i =
			ClampRadius(atmosphere, sqrt(d_i * d_i + 2.0 * r * mu * d_i + r * r));
		Number mu_i = ClampCosine((r * mu + d_i) / r_i);
		Number mu_s_i = ClampCosine((r * mu_s + d_i * nu) / r_i);

		// The Rayleigh and Mie multiple scattering at the current sample point.
		RadianceSpectrum rayleigh_mie_i =
			SampleScattering(
				atmosphere, scattering_density_texture, scattering_size, r_i, mu_i, mu_s_i,
				ray_r_mu_intersects_ground) *
			GetTransmittance(
				atmosphere, transmittance_texture, transmittance_size, r, mu, d_i,
				ray_r_mu_intersects_ground) *
			dx;
		// Sample weight (from the trapezoidal rule).
		Number weight_i = (i == 0 || i == SAMPLE_COUNT) ? 0.5 : 1.0;
		rayleigh_mie_sum += rayleigh_mie_i * weight_i;
	}
	return rayleigh_mie_sum;
}

RadianceDensitySpectrum ComputeScatteringDensityTexture(
	IN(AtmosphereParameters) atmosphere,
	IN(TransmittanceTexture) transmittance_texture,
	uint2 transmittance_size,
	IN(ReducedScatteringTexture) single_rayleigh_scattering_texture,
	IN(ReducedScatteringTexture) single_mie_scattering_texture,
	IN(ScatteringTexture) multiple_scattering_texture,
	uint3 scattering_size,
	IN(IrradianceTexture) irradiance_texture,
	uint2 irradiance_size,
	IN(vec3) frag_coord, int scattering_order) {
	Length r;
	Number mu;
	Number mu_s;
	Number nu;

	bool ray_r_mu_intersects_ground;
	GetRMuMuSNuFromScatteringTextureUvwz(atmosphere, frag_coord,
		r, mu, mu_s, ray_r_mu_intersects_ground, scattering_size);
	nu = GetNuFromMuMus(mu, mu_s);
	return ComputeScatteringDensity(atmosphere, transmittance_texture, transmittance_size,
		single_rayleigh_scattering_texture, single_mie_scattering_texture,
		multiple_scattering_texture, scattering_size, irradiance_texture, irradiance_size, r, mu, mu_s, nu,
		scattering_order);
}

RadianceSpectrum ComputeMultipleScatteringTexture(
	IN(AtmosphereParameters) atmosphere,
	IN(TransmittanceTexture) transmittance_texture,
	uint2 transmittance_size,
	IN(ScatteringDensityTexture) scattering_density_texture,
	uint3 scattering_size,
	IN(vec3) frag_coord) {
	Length r;
	Number mu;
	Number mu_s;
	Number nu;
	bool ray_r_mu_intersects_ground;
	GetRMuMuSNuFromScatteringTextureUvwz(atmosphere, frag_coord,
		r, mu, mu_s, ray_r_mu_intersects_ground, scattering_size);
	nu = GetNuFromMuMus(mu, mu_s);
	return ComputeMultipleScattering(atmosphere, transmittance_texture, transmittance_size,
		scattering_density_texture, scattering_size, r, mu, mu_s, nu,
		ray_r_mu_intersects_ground);
}
#endif