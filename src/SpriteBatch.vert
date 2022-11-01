#version 330 core
layout (location = 0) in vec4 aPosTex;
layout (location = 1) in vec4 aColor;
layout (location = 2) in float aFlash;

uniform mat4 uTransform;

out vec2 fTex;
out vec4 fColor;
out float fFlash;

void main() {
    gl_Position = uTransform * vec4(aPosTex.xy, 0.0, 1.0);
    fTex = aPosTex.zw;
    fColor = aColor;
    fFlash = aFlash;
}
