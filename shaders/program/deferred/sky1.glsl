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
        return;
    }

    vec2 uv = internalTexelSize * gl_FragCoord.xy;
    color = texture(colortex11, uv);

    // Bulan (+ matahari vanilla jika PROXIMA_SUN dimatikan)
    vec3 celestial = EXPONENT_BIAS * pow(texelFetch(colortex10, texel, 0).rgb, vec3(2.2));

    #ifdef DIMENSION_OVERWORLD
        vec3 rayDir = normalize(screenToPlayerPos(vec3(uv, 1.0)).xyz - screenToPlayerPos(vec3(uv, 0.0)).xyz);

        #ifdef PROXIMA_SUN
            celestial += EXPONENT_BIAS * pc_RenderSun(rayDir, sunDir) * lightTransmittance(sunDir);
        #endif

        #ifdef CLOUD_CUMULUS
            // Arah cahaya persis seperti Proxima (RenderClouds)
            float moonlightFactor = smoothstep(-0.03, -0.05, sunDir.y);
            vec3 lightDir = sunDir * (1.0 - 2.0 * moonlightFactor);

            vec2 noise = blueNoise(gl_FragCoord.xy).xy;

            float cloudDepth;
            vec3 cloud = RenderProximaCumulus(rayDir, lightDir, shadowDir, noise, cloudDepth);

            if (cloud.z < 1.0 - cloudEpsilon) {
                vec3 directIrr = shadowLightBrightness * lightTransmittance(shadowDir);
                vec3 skyIrr    = pc_SkyIrradiance();

                // Direct + Indirect (rumus Proxima)
                vec3 cloudRadiance  = cloud.x * (1.0 - wetness * 0.5) * directIrr;
                     cloudRadiance += cloud.y * pc_uniformPhase * skyIrr;
                     cloudRadiance *= PI * EXPONENT_BIAS;

                #ifdef CLOUD_AERIAL_PERSPECTIVE
                    float transmitAP = exp(-cloudDepth / CLOUD_AP_DISTANCE);
                    cloudRadiance = cloudRadiance * transmitAP + color.rgb * (1.0 - transmitAP) * (1.0 - cloud.z);
                #endif

                color.rgb = color.rgb * cloud.z + cloudRadiance;
                celestial *= cloud.z; // matahari/bulan tertutup awan
            }
        #endif
    #endif

    color.rgb += celestial;
}
