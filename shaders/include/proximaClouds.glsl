#ifndef INCLUDE_PROXIMA_CLOUDS
    #define INCLUDE_PROXIMA_CLOUDS

    // ===== Settings (default = Proxima) =====
    #define CLOUD_CUMULUS
    #define CLOUD_LOW_SAMPLES 48            // [16 24 32 40 48 56 64 80 96 128]
    #define CLOUD_LOW_SUNLIGHT_SAMPLES 5    // [2 3 4 5 6 7 8 10]
    #define CLOUD_LOW_WIND_SPEED 10.0       // [0.0 5.0 10.0 15.0 20.0 30.0 40.0 50.0]
    #define CLOUD_CU_ALTITUDE 1000.0        // [500.0 750.0 1000.0 1250.0 1500.0 2000.0 2500.0 3000.0]
    #define CLOUD_CU_THICKNESS 1500.0       // [500.0 1000.0 1500.0 2000.0 2500.0 3000.0]
    #define CLOUD_CU_COVERAGE 0.5           // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
    #define CLOUD_MS_COUNT 4                // [1 2 3 4 5 6 8]
    #define CLOUD_MS_FALLOFF_S 0.5
    #define CLOUD_MS_FALLOFF_E 0.5
    #define CLOUD_MS_FALLOFF_P 0.5
    #define CLOUD_AP_DISTANCE 40000.0       // [10000.0 20000.0 40000.0 80000.0 160000.0]

    uniform sampler3D baseNoiseTex;
    uniform sampler3D detailNoiseTex;
    uniform sampler2D cloudMapTex;
    uniform float worldTimeCounter;
    uniform float wetness;

    // ===== Konstanta (dari Proxima) =====
    const float pcPlanetRadius        = 6371e3;
    const float pcGroundRadius        = pcPlanetRadius - 1000.0; // ATMOSPHERE_BOTTOM_ALTITUDE
    const float pcViewerBaseAltitude  = 64.0;                    // VIEWER_BASE_ALTITUDE
    const float pc_rLOG2              = 1.44269504089;
    const float pc_rPI                = 0.31830988618;
    const float pc_uniformPhase       = 0.25 * pc_rPI;

    const uint  cloudMsCount          = CLOUD_MS_COUNT;
    const float cloudMsFalloffA       = CLOUD_MS_FALLOFF_S;
    const float cloudMsFalloffB       = CLOUD_MS_FALLOFF_E;
    const float cloudMsFalloffC       = CLOUD_MS_FALLOFF_P;
    const float cloudMapExtend        = 128e3;

    const float cumulusThickness      = CLOUD_CU_THICKNESS;
    const float cumulusBottomAltitude = CLOUD_CU_ALTITUDE;
    const float cumulusTopAltitude    = cumulusBottomAltitude + cumulusThickness;
    const float cumulusTopOffset      = 200.0;
    const float cumulusBottomRadius   = pcPlanetRadius + cumulusBottomAltitude;
    const float cumulusTopRadius      = pcPlanetRadius + cumulusTopAltitude;

    const float cumulusExtinction     = 0.06;
    const float cumulusAlbedo         = 1.0;
    const float cloudEpsilon          = 0.001;
    const float cloudMinTransmittance = 0.05;

    // ===== Helper =====
    float pc_sqr(float x)   { return x * x; }
    float pc_curve(float x) { return x * x * (3.0 - 2.0 * x); }
    float pc_pow1d5(float x){ return x * x * inversesqrt(x); }
    float pc_remap(float e0, float e1, float x) { return saturate((x - e0) / (e1 - e0)); }
    float pc_approxSqrt(float x) { return uintBitsToFloat((floatBitsToUint(x) >> 1) + 0x1FC00000u); }

    // ===== Phase function: HgDrainePhase(mu, 5.0) Proxima =====
    float pc_HG(float mu, float g) {
        float gg = g * g;
        return pc_uniformPhase * (1.0 - gg) / pc_pow1d5(1.0 + gg - 2.0 * g * mu);
    }
    float pc_Draine(float mu, float g, float a) {
        float gg = g * g;
        float p1 = (1.0 - gg) / pc_pow1d5(1.0 + gg - 2.0 * g * mu);
        float p2 = (1.0 + a * mu * mu) / (1.0 + a * (1.0 + 2.0 * gg) / 3.0);
        return pc_uniformPhase * p1 * p2;
    }
    float pc_CloudPhase(float mu) {
        const float d = 5.0; // cabang 5 µm <= d <= 50 µm
        float gHG = exp(-0.0990567 / (d - 1.67154));
        float gD  = exp(-2.20679 / (d + 3.91029) - 0.428934);
        float a   = exp(3.62489 - 8.29288 / (d + 5.52825));
        float wD  = exp(-0.599085 / (d - 0.641583) - 0.665888);
        return mix(pc_HG(mu, gHG), pc_Draine(mu, gD, a), wD);
    }

    // ===== Intersection =====
    vec2 pc_RaySphereIntersection(float r, float mu, float rad) {
        float delta = pc_sqr(r) * (pc_sqr(mu) - 1.0) + pc_sqr(rad);
        if (delta >= 0.0) {
            delta *= inversesqrt(delta);
            return vec2(-delta, delta) - r * mu;
        }
        return vec2(-1.0);
    }
    vec2 pc_RaySphericalShellIntersection(float r, float mu, float bottomRad, float topRad) {
        vec2 b = pc_RaySphereIntersection(r, mu, bottomRad);
        vec2 t = pc_RaySphereIntersection(r, mu, topRad);
        if (t.y >= 0.0) {
            vec2 i;
            if (b.y < 0.0)      { i.x = max(t.x, 0.0); i.y = t.y; }
            else if (b.x < 0.0) { i.x = b.y;           i.y = t.y; }
            else                { i.x = max(t.x, 0.0); i.y = b.x; }
            return i;
        }
        return vec2(-1.0);
    }
    bool pc_RayIntersectsGround(float r, float mu) {
        return mu < 0.0 && r * r * (mu * mu - 1.0) + pcGroundRadius * pcGroundRadius >= 0.0;
    }

    // ===== Shape (salinan Shape.glsl Proxima) =====
    float pc_GetVerticalProfile(float heightFraction, float cloudType) {
        float stratus       = pc_remap(0.25, 0.05, heightFraction);
        float stratocumulus = saturate(heightFraction * 6.0) * pc_remap(0.7, 0.2, heightFraction);
        float cumulus       = saturate(heightFraction * 8.0) * pc_remap(1.0, 0.6, heightFraction);
        float verticalProfile = mix(stratus, stratocumulus, saturate(cloudType * 2.0));
        return mix(verticalProfile, cumulus, saturate(cloudType * 2.0 - 1.0));
    }

    float pc_CloudVolumeDensity(vec3 rayPos, out float heightFraction, out float dimensionalProfile, bool detail) {
        dimensionalProfile = 0.0;
        float rayRadius = length(rayPos);
        heightFraction = saturate((rayRadius - cumulusBottomRadius) / cumulusThickness);

        const float windAngle = radians(45.0);
        const vec3 windDir = vec3(cos(windAngle), 0.5, sin(windAngle));
        const vec3 windVelocity = windDir * CLOUD_LOW_WIND_SPEED;
        vec3 windOffset = windVelocity * worldTimeCounter;

        rayPos -= windOffset;
        rayPos -= windDir * cumulusTopOffset * heightFraction;
        rayPos.xz += cameraPosition.xz;

        vec2 cloudMap = texture(cloudMapTex, rayPos.xz / cloudMapExtend).xy;

        float coverage = saturate(mix(cloudMap.x, cloudMap.y + 0.2, pc_sqr(wetness) * 0.75) * (4.0 * CLOUD_CU_COVERAGE));
        if (coverage < 0.25) return 0.0;

        float cloudType = cloudMap.y * pc_sqr(coverage);
        float verticalProfile = pc_GetVerticalProfile(heightFraction, cloudType);
        dimensionalProfile = saturate(verticalProfile * coverage);

        vec3 position = rayPos * 3e-4;
        float baseNoise = pc_curve(texture(baseNoiseTex, position).x);

        // ValueErosion [Schneider 2023]
        float oldMin = 1.0 - baseNoise;
        float cloudDensity = saturate((dimensionalProfile - oldMin) / (1.0 - oldMin));
        if (cloudDensity < cloudEpsilon) return 0.0;

        float detailNoise = 0.5;
        if (detail) {
            position += windOffset * 1e-4;
            detailNoise = texture(detailNoiseTex, position * 8.0).x;
        }
        cloudDensity = pc_remap(pc_sqr(detailNoise) * pc_sqr(0.7 - heightFraction * 0.5), 1.0, cloudDensity);

        float densityProfile = pc_sqr(saturate(heightFraction * 4.0));
        densityProfile *= saturate(5.0 - heightFraction * 5.0);
        return pc_approxSqrt(cloudDensity) * densityProfile;
    }

    // ===== Lighting (salinan Render.glsl Proxima) =====
    float pc_CloudVolumeOpticalDepth(vec3 rayPos, vec3 rayDir, float noise, uint steps) {
        float rSteps = 1.0 / float(steps);
        float stepLength = cumulusThickness * rSteps * rSteps;
        vec3 rayStep = rayDir * stepLength;

        float sumDensity = 0.0;
        for (uint i = 0u; i < steps; ++i) {
            float fi = float(i) + noise;
            vec3 samplePos = rayPos + rayStep * pc_sqr(fi);
            float t0, t1;
            sumDensity += pc_CloudVolumeDensity(samplePos, t0, t1, i < 2u) * fi;
        }
        return cumulusExtinction * 2.0 * stepLength * sumDensity;
    }

    float pc_CloudMultiScattering(float opticalDepth, float phase, float msVolume) {
        float scatteringFalloff = cloudMsFalloffA;
        float extinctionFalloff = cloudMsFalloffB;

        float scattering = exp2(-pc_rLOG2 * opticalDepth) * phase;
        float energyEstimate = 1.0 + msVolume * 0.5;

        for (uint ms = 1u; ms < cloudMsCount; ++ms) {
            phase = mix(msVolume * pc_rPI, phase, cloudMsFalloffC) * energyEstimate;
            scattering += exp2(-pc_rLOG2 * extinctionFalloff * opticalDepth) * phase * scatteringFalloff;
            scatteringFalloff *= scatteringFalloff;
            extinctionFalloff *= extinctionFalloff;
        }
        return scattering;
    }

    // Return: x = sun scattering, y = sky scattering, z = transmittance
    vec3 RenderProximaCumulus(vec3 rayDir, vec3 lightDir, vec2 noise, out float cloudDepth) {
        cloudDepth = 128e3;

        float viewerHeight = pcPlanetRadius + max(1.0, eyeAltitude + pcViewerBaseAltitude);
        vec3 camera = vec3(0.0, viewerHeight, 0.0);
        float r  = viewerHeight;
        float mu = rayDir.y;

        bool planetIntersection = pc_RayIntersectsGround(r, mu);
        if ((planetIntersection && r < cumulusBottomRadius) || (mu > 0.0 && r > cumulusTopRadius)) return vec3(0.0, 0.0, 1.0);

        vec2 intersection = pc_RaySphericalShellIntersection(r, mu, cumulusBottomRadius, cumulusTopRadius);
        if (intersection.y <= 0.0) return vec3(0.0, 0.0, 1.0);

        float phase = pc_CloudPhase(dot(lightDir, rayDir));

        float withinVolumeSmooth = pc_remap(cumulusThickness + 32.0, cumulusThickness - 64.0, abs(r * 2.0 - (cumulusBottomRadius + cumulusTopRadius)));
        float rayLength = clamp(intersection.y - intersection.x, 0.0, 1e5 - withinVolumeSmooth * 6e4);

        uint raySteps = uint(CLOUD_LOW_SAMPLES);
        raySteps = uint(float(raySteps) * mix(1.0 - abs(mu) * 0.5, 4.0, withinVolumeSmooth));

        float stepSize = rayLength / float(raySteps);
        float rayT = intersection.x + stepSize * noise.x;

        float rayLengthWeighted = 0.0, raySumWeight = 0.0;
        vec2 stepScattering = vec2(0.0);
        float transmittance = 1.0;

        for (uint i = 0u; i < raySteps; ++i, rayT += stepSize) {
            vec3 rayPos = camera + rayDir * rayT;

            rayLengthWeighted += rayT * transmittance;
            raySumWeight += transmittance;

            float heightFraction, dimensionalProfile;
            float stepDensity = pc_CloudVolumeDensity(rayPos, heightFraction, dimensionalProfile, rayT < 12e3);

            if (stepDensity > cloudEpsilon) {
                float opticalDepthSun = pc_CloudVolumeOpticalDepth(rayPos, lightDir, noise.y, uint(CLOUD_LOW_SUNLIGHT_SAMPLES));

                float msVolume = pc_sqr(saturate(stepDensity * 2.0 + dimensionalProfile * 0.5));
                float scatteringSun = pc_CloudMultiScattering(opticalDepthSun, phase, msVolume);

                float scatteringSky = pc_approxSqrt(1.0 - dimensionalProfile); // Nubis ambient approx

                float opticalDepthGround = stepDensity * heightFraction * (cumulusThickness * cumulusExtinction * -pc_rLOG2);
                float scatteringGround = exp2(max(opticalDepthGround, opticalDepthGround * 0.25 - 0.5)) * pc_rPI;

                vec2 scattering = vec2(scatteringSun + scatteringGround * pc_uniformPhase * lightDir.y,
                                       scatteringSky + scatteringGround);

                float stepTransmittance = exp2(-pc_rLOG2 * cumulusExtinction * stepDensity * stepSize);
                stepScattering += scattering * transmittance * (1.0 - stepTransmittance);
                transmittance *= stepTransmittance;

                if (transmittance < cloudMinTransmittance) break;
            }
        }

        transmittance = pc_remap(cloudMinTransmittance, 1.0, transmittance);

        if (transmittance < 1.0 - cloudEpsilon) {
            cloudDepth = rayLengthWeighted / raySumWeight;
            return vec3(stepScattering * cumulusAlbedo, transmittance);
        }
        return vec3(0.0, 0.0, 1.0);
    }

    // Irradiance langit dari sky-view LUT Zephyr (cosine-weighted)
    vec3 pc_SkyIrradiance() {
        vec3 sum = vec3(0.0);
        for (int i = 0; i < 16; i++) {
            float u = (float(i) + 0.5) / 16.0;
            float phi = float(i) * 2.39996323;
            float sinT = sqrt(u), cosT = sqrt(1.0 - u);
            sum += sampleSkyView(vec3(cos(phi) * sinT, cosT, sin(phi) * sinT));
        }
        return sum * (PI / 16.0);
    }

#endif
