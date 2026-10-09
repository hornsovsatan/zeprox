#include "/include/uniforms.glsl"
#include "/include/config.glsl"
#include "/include/constants.glsl"
#include "/include/common.glsl"
#include "/include/pbr.glsl"
#include "/include/main.glsl"
#include "/include/textureSampling.glsl"
#include "/include/brdf.glsl"
#include "/include/spaceConversion.glsl"
#include "/include/atmosphere.glsl"
#include "/include/proximaClouds.glsl"

/* RENDERTARGETS: 7 */
layout (location = 0) out vec4 color;

void main ()
{   
    ivec2 texel = ivec2(gl_FragCoord.xy);
    float depth = texelFetch(depthtex1, texel, 0).r;
    
    if (depth != 1.0) {
        color = texelFetch(colortex7, texel, 0);
    } else {
        vec2 uv = internalTexelSize * gl_FragCoord.xy;
        color = texture(colortex11, uv);
        vec3 sunDisc = EXPONENT_BIAS * pow(texelFetch(colortex10, texel, 0).rgb, vec3(2.2));

        #if defined DIMENSION_OVERWORLD && defined CLOUD_CUMULUS
            vec3 rayDir = normalize(screenToPlayerPos(vec3(uv, 1.0)).xyz - screenToPlayerPos(vec3(uv, 0.0)).xyz);
            vec2 noise  = blueNoise(gl_FragCoord.xy).xy;

            float cloudDepth;
            vec3 cloud = RenderProximaCumulus(rayDir, shadowDir, noise, cloudDepth);

            if (cloud.z < 1.0 - cloudEpsilon) {
                vec3 directIrr = shadowLightBrightness * lightTransmittance(shadowDir) * (1.0 - wetness * 0.5);
                vec3 skyIrr    = pc_SkyIrradiance();

                vec3 cloudRadiance = PI * (cloud.x * directIrr + cloud.y * pc_uniformPhase * skyIrr);

                // Pengganti aerial perspective Bruneton milik Proxima
                float apFade = exp(-cloudDepth / CLOUD_AP_DISTANCE);
                cloudRadiance = EXPONENT_BIAS * cloudRadiance * apFade + color.rgb * (1.0 - apFade) * (1.0 - cloud.z);

                color.rgb = color.rgb * cloud.z + cloudRadiance;
                sunDisc *= cloud.z;
            }
        #endif

        color.rgb += sunDisc;
    }
}
