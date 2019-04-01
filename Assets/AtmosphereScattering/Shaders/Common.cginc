#ifndef __COMMON_HELPER__
#define __COMMON_HELPER__

#define Length float
#define Wavelength float
#define Angle float
#define SolidAngle float
#define Power float
#define LuminousPower float

#define Number float
#define InverseLength float
#define Area float
#define Volume float
#define NumberDensity float
#define Irradiance float
#define Radiance float
#define SpectralPower float
#define SpectralIrradiance float
#define SpectralRadiance float
#define SpectralRadianceDensity float
#define ScatteringCoefficient float
#define InverseSolidAngle float
#define LuminousIntensity float
#define Luminance float
#define Illuminance float

// A generic function from Wavelength to some other type.
#define AbstractSpectrum vec3
// A function from Wavelength to Number.
#define DimensionlessSpectrum vec3
// A function from Wavelength to SpectralPower.
#define PowerSpectrum vec3
// A function from Wavelength to SpectralIrradiance.
#define IrradianceSpectrum vec3
// A function from Wavelength to SpectralRadiance.
#define RadianceSpectrum vec3
// A function from Wavelength to SpectralRadianceDensity.
#define RadianceDensitySpectrum vec3
// A function from Wavelength to ScaterringCoefficient.
#define ScatteringSpectrum vec3

// A position in 3D (3 length values).
#define Position vec3
// A unit direction vector in 3D (3 unitless values).
#define Direction vec3
// A vector of 3 luminance values.
#define Luminance3 half3
// A vector of 3 illuminance values.
#define Illuminance3 half3

#define TransmittanceTexture sampler2D
#define IrradianceTexture sampler2D
#define ScatteringTexture sampler3D
#define ScatteringDensityTexture sampler3D
#define ReducedScatteringTexture sampler3D
#define vec2 float2
#define vec3 float3
#define vec4 float4
#define IN(x) x
#define OUT(x) out x
#define assert(x) ;

static const Length m = 1.0f;
static const Wavelength nm = 1.0f;
static const Angle rad = 1.0f;
static const SolidAngle sr = 1.0;
static const Power watt = 1.0;
static const LuminousPower lm = 1.0;

static const float PI = 3.14159265358979323846;

static const Length km = 1000.0 * m;
static const Area m2 = m * m;
static const Volume m3 = m * m * m;
static const Angle pi = PI * rad;
static const Angle deg = pi / 180.0;
static const Irradiance watt_per_square_meter = watt / m2;
static const Radiance watt_per_square_meter_per_sr = watt / (m2 * sr);
static const SpectralIrradiance watt_per_square_meter_per_nm = watt / (m2 * nm);
static const SpectralRadiance watt_per_square_meter_per_sr_per_nm =
watt / (m2 * sr * nm);
static const SpectralRadianceDensity watt_per_cubic_meter_per_sr_per_nm =
watt / (m3 * sr * nm);
static const LuminousIntensity cd = lm / sr;
static const LuminousIntensity kcd = 1000.0 * cd;
static const Luminance cd_per_square_meter = cd / m2;
static const Luminance kcd_per_square_meter = kcd / m2;

struct AtmosphereParameters {
	Length top_radius;
	Length bottom_radius;
	Number sun_angular_radius;
	DimensionlessSpectrum rayleigh_scattering;
	IrradianceSpectrum ground_albedo;
	Number rayleigh_scale_height;
	Number mie_scattering;
	Number mie_extinction;
	Number mie_scale_height;
	DimensionlessSpectrum absorption_extinction;
	Number absorption_extinction_scale_height;
	Number solar_irradiance;
	Number mu_s_min;
	Number mie_phase_function_g;
};

AtmosphereParameters GetAtmosphereStruct(
	float atmosphere_top_radius,
	float atmosphere_bot_radius,
	float atmosphere_sun_angular_radius,
	DimensionlessSpectrum rayleigh_scattering,
	Number rayleigh_scale_height,
	Number mie_scattering,
	Number mie_extinction,
	Number mie_scale_height,
	Number mie_phase_function_g,
	DimensionlessSpectrum absorption_extinction,
	Number absorption_extinction_scale_height
) {
	AtmosphereParameters result;
	result.top_radius = atmosphere_top_radius;
	result.bottom_radius = atmosphere_bot_radius;
	result.sun_angular_radius = atmosphere_sun_angular_radius;


	result.rayleigh_scattering = rayleigh_scattering;
	result.rayleigh_scale_height = rayleigh_scale_height;
	result.mie_scattering = mie_scattering;
	result.mie_extinction = mie_extinction;
	result.mie_scale_height = mie_scale_height;
	result.mie_phase_function_g = mie_phase_function_g;
	result.absorption_extinction = absorption_extinction;
	result.absorption_extinction_scale_height = absorption_extinction_scale_height;

	result.solar_irradiance = 1.0f;
	result.mu_s_min = -0.2f;
	result.ground_albedo = float3(0.1, 0.1, 0.1);
	return result;
}


Number ClampCosine(Number mu) {
	return clamp(mu, Number(-1.0), Number(1.0));
}

Length ClampDistance(Length d) {
	return max(d, 0.0);
}

Length ClampRadius(IN(AtmosphereParameters) atmosphere, Length r) {
	return clamp(r, atmosphere.bottom_radius, atmosphere.top_radius);
}

Length SafeSqrt(Area a) {
	return sqrt(max(a, 0.0));
}

Length DistanceToTopAtmosphereBoundary(IN(AtmosphereParameters) atmosphere,
	Length r, Number mu) {
	assert(r <= atmosphere.top_radius);
	assert(mu >= -1.0 && mu <= 1.0);
	Area discriminant = r * r * (mu * mu - 1.0) +
		atmosphere.top_radius * atmosphere.top_radius;
	return ClampDistance(-r * mu + SafeSqrt(discriminant));
}

Length DistanceToBottomAtmosphereBoundary(IN(AtmosphereParameters) atmosphere,
	Length r, Number mu) {
	assert(r >= atmosphere.bottom_radius);
	assert(mu >= -1.0 && mu <= 1.0);
	Area discriminant = r * r * (mu * mu - 1.0) +
		atmosphere.bottom_radius * atmosphere.bottom_radius;
	return ClampDistance(-r * mu - SafeSqrt(discriminant));
}

bool RayIntersectsGround(IN(AtmosphereParameters) atmosphere,
	Length r, Number mu, OUT(Length) d_1, OUT(Length) d_2) {
	assert(r >= atmosphere.bottom_radius);
	assert(mu >= -1.0 && mu <= 1.0);
	d_1 = 0.0;
	d_2 = 0.0;
	float discriminant = 4 * r * r * (mu * mu - 1.0) +
		4 * atmosphere.bottom_radius * atmosphere.bottom_radius;
	if (discriminant >= 0.0f) {
		float sqDis = sqrt(discriminant);
		d_1 = (-2.0f * r * mu - sqDis) / 2.0f;
		d_2 = (-2.0f * r * mu + sqDis) / 2.0f;
	}
	return mu < 0.0 && discriminant >= 0.0;
}

bool RayIntersectsGround(IN(AtmosphereParameters) atmosphere,
	Length r, Number mu) {
	assert(r >= atmosphere.bottom_radius);
	assert(mu >= -1.0 && mu <= 1.0);
	return mu < 0.0 && r * r * (mu * mu - 1.0) +
		atmosphere.bottom_radius * atmosphere.bottom_radius >= 0.0;
}

Number GetTextureCoordFromUnitRange(Number x, int texture_size) {
	return 0.5 / Number(texture_size) + x * (1.0 - 1.0 / Number(texture_size));
}

Number GetUnitRangeFromTextureCoord(Number u, int texture_size) {
	return (u - 0.5 / Number(texture_size)) / (1.0 - 1.0 / Number(texture_size));
}

Number GetScaleHeight(Length altitude, Length scale_height) {
	return exp(-altitude / scale_height);
}

vec2 GetScaleHeight(Length altitude, vec2 scale_height_rayleigh_mie) {
	return exp(-vec2(altitude, altitude) / scale_height_rayleigh_mie);
}

Length DistanceToNearestAtmosphereBoundary(IN(AtmosphereParameters) atmosphere,
	Length r, Number mu, bool ray_r_mu_intersects_ground) {
	if (ray_r_mu_intersects_ground) {
		return DistanceToBottomAtmosphereBoundary(atmosphere, r, mu);
	}
	else {
		return DistanceToTopAtmosphereBoundary(atmosphere, r, mu);
	}
}

Number GetNuFromMuMus(float mu, float mu_s) {
	return /*cos(a-b), where cos(a) == mu, cos(b) == mu_s*/ mu * mu_s + (1 - mu * mu) * (1 - mu_s * mu_s);
}

/*
Pass in variables.
*/
float atmosphere_top_radius;
float atmosphere_bot_radius;
float atmosphere_sun_angular_radius;
float3 rayleigh_scattering;
float rayleigh_scale_height;
float mie_scattering;
float mie_extinction;
float mie_scale_height;
float mie_phase_function_g;
float3 absorption_extinction;
float absorption_extinction_scale_height;

AtmosphereParameters GetAtmParameters() {
	return GetAtmosphereStruct(
		atmosphere_top_radius,
		atmosphere_bot_radius,
		atmosphere_sun_angular_radius,
		rayleigh_scattering,
		rayleigh_scale_height,
		mie_scattering,
		mie_extinction,
		mie_scale_height,
		mie_phase_function_g,
		absorption_extinction,
		absorption_extinction_scale_height
	);
}

InverseSolidAngle RayleighPhaseFunction(Number nu) {
	InverseSolidAngle k = 3.0 / (16.0 * PI * sr);
	return k * (1.0 + nu * nu);
	//return 0.8f * (1.4f + 0.5f * nu) / (4.0 * PI);
}

InverseSolidAngle AdhocRayleighPhaseFunction(Number nu) {
	return 0.8f * (1.4f + 0.5f * nu) / (4.0 * PI * sr);
}

InverseSolidAngle MiePhaseFunction(Number g, Number nu) {
	InverseSolidAngle k = 3.0 / (8.0 * PI * sr) * (1.0 - g * g) / (2.0 + g * g);
	return k * (1.0 + nu * nu) / pow(abs(1.0 + g * g - 2.0 * g * nu), 1.5);
}

#endif 