#version 330 core
layout (location = 0) in vec2 aPos;
layout (location = 1) in vec4 aColor;

uniform mat4 uTransform;

out vec4 fColor;

void main() {
    gl_Position = uTransform * vec4(aPos, 0.0, 1.0);
    fColor = aColor;
}
