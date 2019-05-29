
 
float GetDensity(float3 startPos, float3 dir, float maxSampleDistance, int sample_count, float raymarchOffset, out float intensity,out float depth) {
	float sampleStartT, sampleEndT;
	if (!resolve_ray_start_end(startPos, dir, sampleStartT, sampleEndT)) {
		intensity = 0.0;
		depth = 1e6;
		return 0;
	}

	float sample_step = min((sampleEndT - sampleStartT) / sample_count, 1000);

    float3 sampleStart = startPos + dir * sampleStartT;
	if (sampleStart.y < -200) {	//Below horizon.
		intensity = 0.0;
	    depth = 1e6;
		return 0.0;
	}

	float raymarchDistance = sampleStartT + raymarchOffset * sample_step;

	RaymarchStatus result;
	InitRaymarchStatus(result);

	[loop]
	for (int j = 0; j < sample_count; j++, raymarchDistance += sample_step) {
        if (raymarchDistance > maxSampleDistance){
            break;
        }
		float3 rayPos = startPos + dir * raymarchDistance;
		IntegrateRaymarch(rayPos, sample_step, result);
	}

	depth = result.depth / result.depthweightsum;
	if (depth == 0.0f) {
		depth = length(sampleEnd - startPos);
	}
	intensity = result.intensity;
	return (1.0f - result.intTransmittance);	
}
