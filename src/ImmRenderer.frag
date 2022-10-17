#version 330 core

in vec2 fTex;
in vec4 fColor;

uniform sampler2D uSampler;

out vec4 FragColor;

void main() {
    vec2 invTexCoord = vec2(fTex.x, fTex.y);
    FragColor = texture(uSampler, invTexCoord) * fColor.rgba;
}
