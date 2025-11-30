/*
    EOTF Boost V7.2 (Smart Compression + OSD Fix)
    
    Changes in V7.2:
    - Added "OSD Brightness" slider. Text no longer renders at max peak HDR brightness.
    - Fixed Saturation Compensation applying when boost is inactive.
    - Fixed Compression applying when boost is inactive.
*/

#include "ReShade.fxh"

// --- UI SETTINGS ---

uniform float BoostStrength <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 2.0;
    ui_label = "Boost Strength";
    ui_tooltip = "How much to lift the mid-tones. Higher = brighter image.";
> = 0.45;

uniform float CompressionStart <
    ui_type = "slider";
    ui_min = 0.5; ui_max = 1.0;
    ui_label = "Compression Start (Soft Knee)";
    ui_tooltip = "At what brightness level to start saving details. 0.8 = balanced. 1.0 = no protection.";
> = 0.80;

uniform float SaturationComp <
    ui_type = "slider";
    ui_min = 0.5; ui_max = 1.5;
    ui_label = "Saturation Compensation";
    ui_tooltip = "Boosting gamma can wash out colors. Use this to bring them back. 1.0 = default.";
> = 1.15;

uniform float APLTrigger <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0;
    ui_label = "APL Trigger";
    ui_tooltip = "The effect only kicks in when average screen brightness exceeds this value (0.15 = 15%).";
> = 0.25;

uniform float TransitionSpeed <
    ui_type = "slider";
    ui_min = 0.1; ui_max = 5.0;
    ui_label = "Transition Speed";
    ui_tooltip = "How fast the boost fades in/out. Lower = smoother/slower.";
> = 2.0;

uniform float ShadowProtect <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0;
    ui_label = "Shadow Protection";
    ui_tooltip = "Prevents the boost from lifting deep blacks, keeping contrast intact.";
> = 1;

uniform bool ShowOSD <
    ui_label = "Show APL Stats";
    ui_tooltip = "Displays current APL percentage in the corner.";
> = true;

uniform float OSDBrightness <
    ui_type = "slider";
    ui_min = 0.01; ui_max = 1.0;
    ui_label = "OSD Brightness";
    ui_tooltip = "Controls the text brightness. 1.0 = Max HDR Brightness (Blinding). 0.25 = Paper White (Recommended).";
> = 0.25;

uniform float FrameTime < source = "frametime"; >;

// --- TEXTURES ---

texture TexAPL { Width = 1; Height = 1; Format = R32F; }; 
sampler SamplerAPL { Texture = TexAPL; };

texture TexBoostState { Width = 1; Height = 1; Format = R32F; };
sampler SamplerBoostState { Texture = TexBoostState; };

// --- FUNCTIONS ---

float GetLuma(float3 color) {
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

float GetDigit(int digit, float2 uv) {
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.0;
    int patterns[10] = { 31599, 9362, 29671, 29391, 23497, 31183, 31215, 29257, 31727, 31695 };
    int num = patterns[clamp(digit, 0, 9)];
    int x = int(uv.x * 3.0);
    int y = int((1.0 - uv.y) * 5.0);
    return (num >> (x + y * 3)) & 1;
}

float GetPercent(float2 uv) {
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.0;
    bool slash = abs(uv.x - (1.0 - uv.y)) < 0.15;
    bool circles = (distance(uv, float2(0.3, 0.25)) < 0.2) || (distance(uv, float2(0.7, 0.75)) < 0.2);
    return (slash || circles) ? 1.0 : 0.0;
}

float SoftCompress(float x, float t)
{
    if (x <= t) return x; 
    float overshoot = x - t;
    float compressed = overshoot / (1.0 + overshoot * 1.5); 
    return t + compressed;
}

// --- SHADERS ---

// PASS 1: Calculate APL (Grid Sampling)
float4 PS_CalcAPL(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float totalLuma = 0.0;
    const int STEPS = 16; 
    for (int x = 0; x < STEPS; x++) {
        for (int y = 0; y < STEPS; y++) {
            float2 sampleUV = float2(float(x) / float(STEPS), float(y) / float(STEPS));
            sampleUV += (0.5 / float(STEPS)); 
            float3 color = tex2Dlod(ReShade::BackBuffer, float4(sampleUV, 0, 0)).rgb;
            totalLuma += GetLuma(color);
        }
    }
    float apl = totalLuma / (float(STEPS * STEPS));
    return float4(apl, apl, apl, 1.0);
}

// PASS 2: Update State (Smoothness)
float4 PS_UpdateState(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float currentAPL = tex2D(SamplerAPL, float2(0.5, 0.5)).r;
    float previousState = tex2D(SamplerBoostState, float2(0.5, 0.5)).r;
    
    float targetState = smoothstep(APLTrigger, APLTrigger + 0.05, currentAPL);
    float dt = FrameTime * 0.001; 
    float newState = lerp(previousState, targetState, saturate(dt * TransitionSpeed));
    return float4(newState, newState, newState, 1.0);
}

// PASS 3: Main Rendering
float3 PS_MainPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    float pixelLuma = GetLuma(color);

    float currentAPL = tex2D(SamplerAPL, float2(0.5, 0.5)).r;
    float fader = tex2D(SamplerBoostState, float2(0.5, 0.5)).r; 
    
    // Mask out shadows
    float shadowFactor = smoothstep(0.0, ShadowProtect * 0.5 + 0.05, pixelLuma);
    
    // Calculate boost amount
    float activeBoost = BoostStrength * 0.5 * fader * shadowFactor;
    
    // 1. Apply boost
    float boostedLuma = pow(max(pixelLuma, 0.0001), 1.0 - activeBoost);
    
    // 2. Compress highlights
    float compressedLuma = SoftCompress(boostedLuma, CompressionStart);
    boostedLuma = lerp(boostedLuma, compressedLuma, fader);
    
    // 3. Recombine Color
    float3 chroma = color - pixelLuma;
    float satMult = lerp(1.0, SaturationComp, fader);
    chroma *= satMult;
    
    float3 finalColor = boostedLuma + chroma;

    if (pixelLuma < 0.01) {
       finalColor = color * (boostedLuma / max(pixelLuma, 0.0001));
    }
    
    // --- OSD RENDER ---
    if (ShowOSD) 
    {
        float2 posStart = float2(0.90, 0.05);
        float scale = 0.04; 
        float aspect = ReShade::ScreenSize.x / ReShade::ScreenSize.y;
        
        int val = clamp(int(currentAPL * 100.0), 0, 99); 
        int d1 = val / 10;
        int d2 = val % 10;
        
        float textMask = 0.0;
        float2 uvDigits = texcoord - posStart;
        uvDigits.x *= aspect;
        
        textMask += GetDigit(d1, uvDigits / scale);
        textMask += GetDigit(d2, (uvDigits - float2(scale * 0.7, 0.0)) / scale);
        textMask += GetPercent((uvDigits - float2(scale * 1.5, 0.0)) / scale);

        float3 baseColor = lerp(float3(1,1,1), float3(0,1,0), fader);
        float3 textColor = baseColor * OSDBrightness; // Clamp OSD brightness
        
        if (textMask < 0.5 && textMask > 0.1) finalColor = float3(0,0,0); 
        else finalColor = lerp(finalColor, textColor, saturate(textMask));
    }

    return finalColor;
}

technique EOTF_Boost_V7_2
{
    pass APL_Calculation { VertexShader = PostProcessVS; PixelShader = PS_CalcAPL; RenderTarget = TexAPL; }
    pass Update_State { VertexShader = PostProcessVS; PixelShader = PS_UpdateState; RenderTarget = TexBoostState; }
    pass Main_Boost { VertexShader = PostProcessVS; PixelShader = PS_MainPass; }
}
