#version 330 core

in vec2 fTex;
in vec3 fColor;

uniform sampler2D uSampler;

out vec4 FragColor;

void main() {
    vec2 invTexCoord = vec2(fTex.x, 1.0 - fTex.y);
    FragColor = texture(uSampler, invTexCoord) * vec4(fColor.rgb, 1.0);
}
