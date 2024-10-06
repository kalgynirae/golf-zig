#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Output fragment color
out vec4 finalColor;

uniform float time;
uniform vec2 cursorPosition;

struct Ball {
  int selected;
  vec2 position;
  vec4 color;
};

#define MAX_BALLS 16
uniform Ball balls[MAX_BALLS];
uniform vec4 ambientColor;
uniform int ballCount = 0;

void main() {
  float alpha = 1.0;

  vec2 pos = gl_FragCoord.xy;
  vec4 color = vec4(0.0);

  float d = 65000;
  int fi = -1;

  for (int i = 0; i < MAX_BALLS; i++) {
    float maxDistance = 64.0;
    vec2 ballPosition = vec2(balls[i].position.x, 600-balls[i].position.y);
    float dist = length(pos - ballPosition);
    if (dist < maxDistance) {
      alpha -= smoothstep(maxDistance, 0.0, dist);
      color += balls[i].color;
    }
  }

  if (alpha > 0.7) {
    alpha = 0.7;
  }

  finalColor = vec4(color.rgb, alpha);
}