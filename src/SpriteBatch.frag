#version 330 core

in vec2 fTex;
in vec4 fColor;
in float fFlash;

uniform sampler2D uSampler;
uniform vec3 uFlashRGB;

out vec4 FragColor;

void main() {
    vec4 base_color = texture(uSampler, vec2(fTex.x, fTex.y));
    FragColor = mix(
        base_color * fColor,
        vec4(uFlashRGB, base_color.a),
        fFlash
    );
}
