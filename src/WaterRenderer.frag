#version 330 core

in vec2 fPos;
in vec2 fTex;

uniform sampler2D uSamplerBase;
uniform sampler2D uSamplerBlend;
uniform float     uBlendAmount;
uniform float     uGlobalTime;
uniform vec2      uWaterDirection;
uniform float     uWaterSpeed;
uniform vec2      uWaterDriftRange; // good default is <0.3, 0.2>, set to 0 for waterfalls
uniform vec2      uWaterDriftScale; // default to 32, 16

out vec4 FragColor;

void main() {
    vec2 baseTexCoord = fTex;
    baseTexCoord.x += cos(uGlobalTime + fPos.y / uWaterDriftScale.x) * 1.5 * uWaterDriftRange.x * uWaterSpeed;
    baseTexCoord.y += sin(uGlobalTime + fPos.x / uWaterDriftScale.y) * 1.5 * uWaterDriftRange.y * uWaterSpeed;

    vec2 blendTexCoord = fTex;
    blendTexCoord.x += cos(1.5 * uGlobalTime + fPos.y / uWaterDriftScale.x) * uWaterDriftRange.x * uWaterSpeed;
    blendTexCoord.y += sin(1.5 * uGlobalTime + fPos.x / uWaterDriftScale.y) * uWaterDriftRange.y * uWaterSpeed;

    vec4 base_color  = texture(uSamplerBase, baseTexCoord);
    vec4 blend_color = texture(uSamplerBlend, blendTexCoord);
    FragColor = mix(base_color, blend_color, uBlendAmount);
}
