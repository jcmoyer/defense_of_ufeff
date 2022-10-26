#version 330 core

in vec2 q;
in vec2 b1;
in vec2 b2;
in vec2 b3;

uniform sampler2D uSampler;

out vec4 FragColor;

float wedge2D(vec2 v, vec2 w) {
    return v.x*w.y - v.y*w.x;
}

void main() {
    float A = wedge2D(b2, b3);
    float B = wedge2D(b3, q) - wedge2D(b1, b2);
    float C = wedge2D(b1, q);
    vec2 uv;
    if (abs(A) < 0.001) {
        uv.y = -C/B;
    } else {
        float discrim = B*B - 4*A*C;
        uv.y = 0.5*(-B + sqrt(discrim))/A;
    }

    vec2 denom = b1 + uv.y * b3;
    if (abs(denom.x) > abs(denom.y)) {
        uv.x = (q.x - b2.x * uv.y) / denom.x;
    } else {
        uv.x = (q.y - b2.y * uv.y) / denom.y;
    }

    FragColor = texture(uSampler, uv);
}
