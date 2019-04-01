#ifndef __SINGLE_SCATTERING_HELPER__
#define __SINGLE_SCATTERING_HELPER__

#include "Common.cginc"
#include "TransmittanceHelper.cginc"

void ComputeSingleScatteringIntegrand(
	IN(AtmosphereParameters) atmosphere,
	IN(TransmittanceTexture) transmittance_texture,
	uint2 texture_size,
	Length r, Number mu, Number mu_s, Number nu, Length d,
	bool ray_r_mu_intersects_ground,
	OUT(DimensionlessSpectrum) rayleigh, OUT(DimensionlessSpectrum) mie) {

	Length r_d = ClampRadius(atmosphere, sqrt(d * d + 2.0 * r * mu * d + r * r));
	Number mu_s_d = ClampCosine((r * mu_s + d * nu) / r_d);
	DimensionlessSpectrum transmittance =
		GetTransmittance(
			atmosphere, transmittance_texture, texture_size, r, mu, d,
			ray_r_mu_intersects_ground) *
		GetTransmittanceToSun(
			atmosphere, transmittance_texture, texture_size, r_d, mu_s_d);
	rayleigh = transmittance * GetScaleHeight(r_d - atmosphere.bottom_radius, atmosphere.rayleigh_scale_height);
	mie = transmittance * GetScaleHeight(r_d - atmosphere.bottom_radius, atmosphere.rayleigh_scale_height);
}

void ComputeSingleScattering(
	IN(AtmosphereParameters) atmosphere,
	IN(TransmittanceTexture) transmittance_texture,
	uint2 texture_size,
	Length r, Number mu, Number mu_s, Number nu,
	bool ray_r_mu_intersects_ground,
	OUT(IrradianceSpectrum) rayleigh, OUT(IrradianceSpectrum) mie) {
	assert(r >= atmosphere.bottom_radius && r <= atmosphere.top_radius);
	assert(mu >= -1.0 && mu <= 1.0);
	assert(mu_s >= -1.0 && mu_s <= 1.0);


	// Number of intervals for the numerical integration.
	const int SAMPLE_COUNT = 50;
	// The integration step, i.e. the length of each integration interval.
	Length dx =
		DistanceToNearestAtmosphereBoundary(atmosphere, r, mu,
			ray_r_mu_intersects_ground) / Number(SAMPLE_COUNT);
	// Integration loop.
	DimensionlessSpectrum rayleigh_sum = DimensionlessSpectrum(0.0, 0.0, 0.0);
	DimensionlessSpectrum mie_sum = DimensionlessSpectrum(0.0, 0.0, 0.0);
	for (int i = 0; i <= SAMPLE_COUNT; ++i) {
		Length d_i = Number(i) * dx;
		// The Rayleigh and Mie single scattering at the current sample point.
		DimensionlessSpectrum rayleigh_i;
		DimensionlessSpectrum mie_i;
		ComputeSingleScatteringIntegrand(atmosphere, transmittance_texture, texture_size,
			r, mu, mu_s, nu, d_i, ray_r_mu_intersects_ground, rayleigh_i, mie_i);
		// Sample weight (from the trapezoidal rule).
		Number weight_i = (i == 0 || i == SAMPLE_COUNT) ? 0.5 : 1.0;
		rayleigh_sum += rayleigh_i * weight_i;
		mie_sum += mie_i * weight_i;
	}
	//Phase function terms are not added yet. See GetScattering.(And also, we need to store rayleigh and mie seprately, since they use different phase functions.)
	rayleigh = rayleigh_sum * dx  * atmosphere.solar_irradiance * atmosphere.rayleigh_scattering;
	mie = mie_sum * dx * atmosphere.solar_irradiance * atmosphere.mie_scattering;
}

vec3 GetScatteringTextureUvwzFromRMuMuSNu(IN(AtmosphereParameters) atmosphere,
	Length r, Number mu, Number mu_s, uint3 texture_size,
	bool ray_r_mu_intersects_ground) {
	assert(r >= atmosphere.bottom_radius && r <= atmosphere.top_radius);
	assert(mu >= -1.0 && mu <= 1.0);
	assert(mu_s >= -1.0 && mu_s <= 1.0);

	// Distance to top atmosphere boundary for a horizontal ray at ground level.
	Length H = sqrt(atmosphere.top_radius * atmosphere.top_radius -
		atmosphere.bottom_radius * atmosphere.bottom_radius);
	// Distance to the horizon.
	Length rho =
		SafeSqrt(r * r - atmosphere.bottom_radius * atmosphere.bottom_radius);
	Number u_r = GetTextureCoordFromUnitRange(rho / H, texture_size.z);

	// Discriminant of the quadratic equation for the intersections of the ray
	// (r,mu) with the ground (see RayIntersectsGround).
	Length r_mu = r * mu;
	Area discriminant =
		r_mu * r_mu - r * r + atmosphere.bottom_radius * atmosphere.bottom_radius;
	Number u_mu;
	if (ray_r_mu_intersects_ground) {
		// Distance to the ground for the ray (r,mu), and its minimum and maximum
		// values over all mu - obtained for (r,-1) and (r,mu_horizon).
		Length d = -r_mu - SafeSqrt(discriminant);
		Length d_min = r - atmosphere.bottom_radius;
		Length d_max = rho;
		u_mu = 0.5 - 0.5 * GetTextureCoordFromUnitRange(d_max == d_min ? 0.0 :
			(d - d_min) / (d_max - d_min), texture_size.y / 2);
	}
	else {
		// Distance to the top atmosphere boundary for the ray (r,mu), and its
		// minimum and maximum values over all mu - obtained for (r,1) and
		// (r,mu_horizon).
		Length d = -r_mu + SafeSqrt(discriminant + H * H);
		Length d_min = atmosphere.top_radius - r;
		Length d_max = rho + H;
		u_mu = 0.5 + 0.5 * GetTextureCoordFromUnitRange(
			(d - d_min) / (d_max - d_min), texture_size.y / 2);
	}

	Length d = DistanceToTopAtmosphereBoundary(
		atmosphere, atmosphere.bottom_radius, mu_s);
	Length d_min = atmosphere.top_radius - atmosphere.bottom_radius;
	Length d_max = H;
	Number a = (d - d_min) / (d_max - d_min);
	Number A =
		-2.0 * atmosphere.mu_s_min * atmosphere.bottom_radius / (d_max - d_min);
	Number u_mu_s = GetTextureCoordFromUnitRange(
		max(1.0 - a / A, 0.0) / (1.0 + a), texture_size.x);

	return vec3(u_mu_s, u_mu, u_r);
}

void GetRMuMuSNuFromScatteringTextureUvwz(IN(AtmosphereParameters) atmosphere,
	IN(vec3) uvwz, OUT(Length) r, OUT(Number) mu, OUT(Number) mu_s, OUT(bool) ray_r_mu_intersects_ground,
	uint3 scattering_size
) {
	assert(uvwz.x >= 0.0 && uvwz.x <= 1.0);
	assert(uvwz.y >= 0.0 && uvwz.y <= 1.0);
	assert(uvwz.z >= 0.0 && uvwz.z <= 1.0);

	// Distance to top atmosphere boundary for a horizontal ray at ground level.
	Length H = sqrt(atmosphere.top_radius * atmosphere.top_radius -
		atmosphere.bottom_radius * atmosphere.bottom_radius);
	// Distance to the horizon.
	Length rho =
		H * GetUnitRangeFromTextureCoord(uvwz.z, scattering_size.z);
	r = sqrt(rho * rho + atmosphere.bottom_radius * atmosphere.bottom_radius);

	if (uvwz.y < 0.5) {
		// Distance to the ground for the ray (r,mu), and its minimum and maximum
		// values over all mu - obtained for (r,-1) and (r,mu_horizon) - from which
		// we can recover mu:
		Length d_min = r - atmosphere.bottom_radius;
		Length d_max = rho;
		Length d = d_min + (d_max - d_min) * GetUnitRangeFromTextureCoord(
			1.0 - 2.0 * uvwz.y, scattering_size.y / 2);
		mu = d == 0.0 * m ? Number(-1.0) :
			ClampCosine(-(rho * rho + d * d) / (2.0 * r * d));
		ray_r_mu_intersects_ground = true;
	}
	else {
		// Distance to the top atmosphere boundary for the ray (r,mu), and its
		// minimum and maximum values over all mu - obtained for (r,1) and
		// (r,mu_horizon) - from which we can recover mu:
		Length d_min = atmosphere.top_radius - r;
		Length d_max = rho + H;
		Length d = d_min + (d_max - d_min) * GetUnitRangeFromTextureCoord(
			2.0 * uvwz.y - 1.0, scattering_size.y / 2);
		mu = d == 0.0 * m ? Number(1.0) :
			ClampCosine((H * H - rho * rho - d * d) / (2.0 * r * d));
		ray_r_mu_intersects_ground = false;
	}

	Number x_mu_s =
		GetUnitRangeFromTextureCoord(uvwz.x, scattering_size.x);
	Length d_min = atmosphere.top_radius - atmosphere.bottom_radius;
	Length d_max = H;
	Number A =
		-2.0 * atmosphere.mu_s_min * atmosphere.bottom_radius / (d_max - d_min);
	Number a = (A - x_mu_s * A) / (1.0 + x_mu_s * A);
	Length d = d_min + min(a, A) * (d_max - d_min);
	mu_s = d == 0.0 * m ? Number(1.0) :
		ClampCosine((H * H - d * d) / (2.0 * atmosphere.bottom_radius * d));
}

void ComputeSingleScatteringTexture(IN(AtmosphereParameters) atmosphere,
	IN(TransmittanceTexture) transmittance_texture,
	uint2 transmittance_size,
	IN(vec3) gl_frag_coord,
	uint3 scattering_size,
	OUT(IrradianceSpectrum) rayleigh, 
	OUT(IrradianceSpectrum) mie) {

	Length r;
	Number mu;
	Number mu_s;
	bool ray_r_mu_intersects_ground;
	GetRMuMuSNuFromScatteringTextureUvwz(atmosphere, gl_frag_coord,
		r, mu, mu_s, ray_r_mu_intersects_ground, scattering_size);
	Number nu = GetNuFromMuMus(mu, mu_s);
	ComputeSingleScattering(atmosphere, transmittance_texture, transmittance_size,
		r, mu, mu_s, nu, ray_r_mu_intersects_ground, rayleigh, mie);
}

RadianceSpectrum SampleScattering(
	IN(AtmosphereParameters) atmosphere,
	IN(ScatteringTexture) scattering_texture,
	uint3 texture_size,
	Length r, Number mu, Number mu_s, bool ray_r_mu_intersects_ground

) {
	vec3 uvwz = GetScatteringTextureUvwzFromRMuMuSNu(
		atmosphere, r, mu, mu_s, texture_size, ray_r_mu_intersects_ground);
	return tex3Dlod(scattering_texture, float4(uvwz, 0.0)).rgb;
}

RadianceSpectrum SampleScatteringLerped(
	IN(AtmosphereParameters) atmosphere,
	IN(ScatteringTexture) scattering_texture,
	IN(ScatteringTexture) scattering_texture_2,
	float lerpValue,
	uint3 texture_size,
	Length r, Number mu, Number mu_s, bool ray_r_mu_intersects_ground

) {
	vec3 uvwz = GetScatteringTextureUvwzFromRMuMuSNu(
		atmosphere, r, mu, mu_s, texture_size, ray_r_mu_intersects_ground);
	return lerp(tex3Dlod(scattering_texture, float4(uvwz, 0.0)).rgb, tex3Dlod(scattering_texture_2, float4(uvwz, 0.0)).rgb, lerpValue);
}

RadianceSpectrum GetScattering(
	IN(AtmosphereParameters) atmosphere,
	IN(ReducedScatteringTexture) single_rayleigh_scattering_texture,
	IN(ReducedScatteringTexture) single_mie_scattering_texture,
	IN(ScatteringTexture) multiple_scattering_texture,
	uint3 texture_size,
	Length r, Number mu, Number mu_s, Number nu,
	bool ray_r_mu_intersects_ground,
	int scattering_order
	) {

	if (scattering_order == 1) {
		IrradianceSpectrum rayleigh = SampleScattering(
			atmosphere, single_rayleigh_scattering_texture, texture_size, r, mu, mu_s,
			ray_r_mu_intersects_ground);
		IrradianceSpectrum mie = SampleScattering(
			atmosphere, single_mie_scattering_texture, texture_size, r, mu, mu_s,
			ray_r_mu_intersects_ground);
		return rayleigh * RayleighPhaseFunction(nu) +
			mie * MiePhaseFunction(atmosphere.mie_phase_function_g, nu);
	}
	else {
		return SampleScattering(
			atmosphere, multiple_scattering_texture, texture_size, r, mu, mu_s,
			ray_r_mu_intersects_ground);
	}
}

#endif