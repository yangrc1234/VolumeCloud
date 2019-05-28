sampler2D HiHeightMap;    //Includes hierarchical height map. Every mip level stores max height of sub pixels.

static const HI_HEIGHT_LOWEST_LEVEL = 0;
static const HI_HEIGHT_HIGHEST_LEVEL = 9;

int2 GetCellIndex(float2 pos);
float2 GetCellUV(float2 pos);
float2 GetCellUV(int2 cellIndex);

void HierarchicalRaymarch(float3 startpos, float3 dir, float stepSize, float stepEnd) {
    ClampToCloudLayer(raypos, dir);
    int currentZLevel = 0;
    float currentStep = 0;

    while(currentZLevel < HI_HEIGHT_HIGHEST_LEVEL && currentStep < end) {
        float3 raypos = startpos + currentStep * stepSize;
        float2 uv = GetCellUV(raypos);
        float height = tex2Dlod(HiHeightMap, float4(uv, currentZLevel));
        int2 oldCellIndex = GetCellIndex(raypos.xz);

        float rayhitStepSize;
        bool intersected = false;
        if (raypos.y < height) {
            rayhitStepSize = currentStep;
            intersected = true;
        } else {
            rayhitStepSize = IntersectWithHeightPlane(startpos, dir, stepSize, height);
            //tmpRay is the intersection point of the height plane and ray.
            float3 tmpRay = startpos + dir * rayhitStepSize;
            int2 newCellIndex = GetCellIndex(tmpRay.xz);
            intersected = newCellIndex == oldCellIndex;
        }
         
        if (intersected) { //Current raypos is inside cloud of current level.
            currentStep = ceil(rayhitStepSize);
            if (currentZLevel == HI_HEIGHT_LOWEST_LEVEL) { //We can do raymarch now.
                IntegrateRaymarch(startpos + currentStep * stepSize, tempResult /*TODO: Replace actual raymarch here.*/);
                currentStep += 1.0f;
            } else { //Move raypos to just beyond rayhitStepSize, also go one level deeper.
                currentZLevel -= 1;
            }
        } else {    //Reached bound of current cell.
            rayhitStepSize = IntersectWithCellBoundary(startpos, dir, stepSize, currentZLevel, oldCellIndex);
            currentStep = ceil(rayhitStepSize);
        }
    }
}