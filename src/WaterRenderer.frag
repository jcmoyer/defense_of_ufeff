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
    vec2 invTexCoord = vec2(fTex.x, fTex.y);

    invTexCoord.x += cos(uGlobalTime + fPos.y / uWaterDriftScale.x) * uWaterDriftRange.x + uWaterDirection.x * uGlobalTime * uWaterSpeed;
    invTexCoord.y += sin(uGlobalTime + fPos.x / uWaterDriftScale.y) * uWaterDriftRange.y + uWaterDirection.y * uGlobalTime * uWaterSpeed;

    vec4 base_color  = texture(uSamplerBase, invTexCoord);
    vec4 blend_color = texture(uSamplerBlend, invTexCoord);
    FragColor = mix(base_color, blend_color, uBlendAmount);
}
