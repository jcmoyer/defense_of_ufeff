#version 330 core
layout (location = 0) in int aID;

uniform vec2 uPos[4];

uniform mat4 uTransform;

out vec2 q;
out vec2 b1;
out vec2 b2;
out vec2 b3;

void main() {
    gl_Position = uTransform * vec4(uPos[aID], 0.0, 1.0);
    q = uPos[aID] - uPos[0];
    b1= uPos[1] - uPos[0];
    b2= uPos[2] - uPos[0];
    b3= uPos[0] - uPos[1] - uPos[2] + uPos[3];
}
