# Volume Cloud for Unity3D
This is an volume cloud rendering implementation for Unity3D using methods from Horizon:Zero Dawn.
![](./Screenshots/1.png)

## Implementation details.
Most of the techniques are the same from the slides.  
1. The rendering is a post-processing effect.  
2. First a quarter-res buffer is rendered which is the main part, including building the cloud shape and sample for light etc.(The result contains intensity, density and depth).  
3. A history buffer is maintained, by blending history buffer(reprojected so to sample correctly) and the quarter-res buffer together to make new one.(quarter-res buffer is firstly shaded then blended with history buffer.)  
4. Blit the cloud image with final image.  

## Known issues 
Rendering is weird when above cloud layer.  

## References
[The Real-time Volumetric Cloudscapes of Horizon: Zero Dawn](http://www.advances.realtimerendering.com/s2015/index.html)  
[Nubis: Authoring Real-Time Volumetric Cloudscapes with the Decima Engine](http://www.advances.realtimerendering.com/s2017/index.html)  
[TAA from playdead for reprojection](https://github.com/playdeadgames/temporal)