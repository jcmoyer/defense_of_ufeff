#version 330 core
layout (location = 0) in vec4 aPosTex;
layout (location = 1) in vec4 aWorldPos;

uniform mat4 uTransform;

out vec2 fPos;
out vec2 fTex;

void main() {
    gl_Position = uTransform * vec4(aPosTex.xy, 0.0, 1.0);
    fTex = aPosTex.zw;
    fPos = aWorldPos.xy;
}
