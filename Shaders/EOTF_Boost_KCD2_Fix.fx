/*
    EOTF Boost V7 special for kcd2 (KCD2 Hue Fix)
    
    Fixes the "Yellow Tint" issue in warm games (Kingdom Come 2, Cyberpunk).
    1. Changed blending mode to Multiplicative (Strict Hue Preservation).
    2. Added "Highlight Desaturation" to turn intense yellow highlights into pure white light.
*/

#include "ReShade.fxh"

// --- UI SETTINGS ---

uniform float BoostStrength <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 2.0;
    ui_label = "Boost Strength";
> = 0.45;

uniform float CompressionStart <
    ui_type = "slider";
    ui_min = 0.5; ui_max = 1.0;
    ui_label = "Compression Start";
> = 0.80;

uniform float HighlightDesat <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0;
    ui_label = "Highlight Desaturation";
    ui_tooltip = "Crucial for KCD2. Turns bright yellow sun/clouds into white light. Increase if image looks too yellow.";
> = 0.50;

uniform float APLTrigger <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0;
    ui_label = "APL Trigger";
> = 0.15;

uniform float TransitionSpeed <
    ui_type = "slider";
    ui_min = 0.1; ui_max = 5.0;
    ui_label = "Transition Speed";
> = 2.0;

uniform float ShadowProtect <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0;
    ui_label = "Shadow Protection";
> = 0.35;

uniform bool ShowOSD <
    ui_label = "Show APL Stats";
> = true;

uniform float OSDBrightness <
    ui_type = "slider";
    ui_min = 0.01; ui_max = 1.0;
    ui_label = "OSD Brightness";
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

float4 PS_UpdateState(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float currentAPL = tex2D(SamplerAPL, float2(0.5, 0.5)).r;
    float previousState = tex2D(SamplerBoostState, float2(0.5, 0.5)).r;
    float targetState = smoothstep(APLTrigger, APLTrigger + 0.05, currentAPL);
    float dt = FrameTime * 0.001; 
    float newState = lerp(previousState, targetState, saturate(dt * TransitionSpeed));
    return float4(newState, newState, newState, 1.0);
}

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
    
    // 1. Calculate Target Luma
    float boostedLuma = pow(max(pixelLuma, 0.0001), 1.0 - activeBoost);
    
    // 2. Compress highlights (Soft Knee)
    float compressedLuma = SoftCompress(boostedLuma, CompressionStart);
    boostedLuma = lerp(boostedLuma, compressedLuma, fader);
    
    // 3. NEW COLOR LOGIC (Multiplicative)
    // Instead of adding Chroma, we multiply by the ratio.
    // This strictly preserves HUE. Yellow stays Yellow.
    float3 finalColor = color;
    if (pixelLuma > 0.0001) {
        float ratio = boostedLuma / pixelLuma;
        finalColor = color * ratio;
    }
    
    // 4. Highlight Desaturation (Fix for KCD2 Yellow Tint)
    // If the pixel is very bright, desaturate it towards white.
    // This prevents the "Deep Fried" yellow look.
    float desatMask = smoothstep(0.6, 1.2, boostedLuma); // Apply only to bright areas
    float3 whitePoint = float3(boostedLuma, boostedLuma, boostedLuma);
    finalColor = lerp(finalColor, whitePoint, desatMask * HighlightDesat * fader);

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
        float3 textColor = baseColor * OSDBrightness;
        
        if (textMask < 0.5 && textMask > 0.1) finalColor = float3(0,0,0); 
        else finalColor = lerp(finalColor, textColor, saturate(textMask));
    }

    return finalColor;
}

technique EOTF_Boost_V7_3_HueFix
{
    pass APL_Calculation { VertexShader = PostProcessVS; PixelShader = PS_CalcAPL; RenderTarget = TexAPL; }
    pass Update_State { VertexShader = PostProcessVS; PixelShader = PS_UpdateState; RenderTarget = TexBoostState; }
    pass Main_Boost { VertexShader = PostProcessVS; PixelShader = PS_MainPass; }
}
