//The code here is from https://github.com/SlightlyMad/VolumetricLights/blob/master/Assets/Shaders/BilateralBlur.shader
//With sligtly modified.
//Below is the copyright info.

//  Copyright(c) 2016, Michal Skalsky
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without modification,
//  are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//
//  2. Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//
//  3. Neither the name of the copyright holder nor the names of its contributors
//     may be used to endorse or promote products derived from this software without
//     specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
//  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
//  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.IN NO EVENT
//  SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
//  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
//  OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
//  HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
//  TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
//  EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


float4 Upsample(v2f i, Texture2D _CloudTex, Texture2D _CameraDepthTexture, Texture2D _DownsampledDepth, SamplerState sampler_CameraDepthTexture, SamplerState sampler_CloudTex) {

	float4 lowResDepth = 0.0f;
	float highResDepth = LinearEyeDepth(_CameraDepthTexture.Sample(sampler_CameraDepthTexture, i.uv));

	lowResDepth.x = LinearEyeDepth(_DownsampledDepth.Sample(sampler_CameraDepthTexture, i.uv00));
	lowResDepth.y = LinearEyeDepth(_DownsampledDepth.Sample(sampler_CameraDepthTexture, i.uv10));
	lowResDepth.z = LinearEyeDepth(_DownsampledDepth.Sample(sampler_CameraDepthTexture, i.uv01));
	lowResDepth.w = LinearEyeDepth(_DownsampledDepth.Sample(sampler_CameraDepthTexture, i.uv11));

	float4 depthDiff = abs(lowResDepth - highResDepth);
	float accumDiff = dot(depthDiff, float4(1, 1, 1, 1));

	[branch]
	if (accumDiff < 1.5f) // small error, not an edge -> use bilinear filter
	{
		return _CloudTex.Sample(sampler_CloudTex, i.uv);		//just linear sample.
	}
	else
	{
		float minDepthDiff = depthDiff[0];
		float2 nearestUv = i.uv00;

		if (depthDiff[1] < minDepthDiff)
		{
			nearestUv = i.uv10;
			minDepthDiff = depthDiff[1];
		}

		if (depthDiff[2] < minDepthDiff)
		{
			nearestUv = i.uv01;
			minDepthDiff = depthDiff[2];
		}

		if (depthDiff[3] < minDepthDiff)
		{
			nearestUv = i.uv11;
			minDepthDiff = depthDiff[3];
		}

		return _CloudTex.Sample(sampler_CameraDepthTexture, nearestUv);
	}
}