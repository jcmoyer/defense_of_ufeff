#version 330 core

in vec2 fTex;
in vec4 fColor;

uniform sampler2D uSampler;

out vec4 FragColor;

void main() {
    FragColor = texture(uSampler, vec2(fTex.x, fTex.y)) * fColor;
}
