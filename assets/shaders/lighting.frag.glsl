#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Output fragment color
out vec4 finalColor;

// Custom variables
#define PI 3.14159265358979323846
uniform float uTime = 0.0;
uniform float uCursorPositionX = 0;
uniform float uCursorPositionY = 0;

#define MAX_ALPHA_FALLOFF 0.7

void main()
{
    vec3 color = vec3(0,0,0);
    float alpha = MAX_ALPHA_FALLOFF;

    vec2 fragCoord = vec2(gl_FragCoord.x, gl_FragCoord.y);

    float cursorDistance = length(fragCoord - vec2(uCursorPositionX, 600-uCursorPositionY));
    if (cursorDistance <= 160.0) {
      color = fragColor.xyz;
      alpha = 0.0;
    } else {
      float dist = cursorDistance - 160.0;
      alpha = min((dist*dist)/160.0, MAX_ALPHA_FALLOFF);
    }
    finalColor = vec4(color, alpha);
}