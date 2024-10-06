#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Output fragment color
out vec4 finalColor;

// Custom variables
#define PI 3.14159265358979323846
uniform float uTime = 0.0;
uniform int uCursorPositionX = 0;
uniform int uCursorPositionY = 0;

void main()
{
    vec3 color = fragColor.xyz;
    color *= 1.0;

    float alpha = 0.0;
    float cursorDistance = length(fragTexCoord.xy - vec2(uCursorPositionX, uCursorPositionY)) - 20.0;
    alpha = min(0.0, cursorDistance);

    finalColor = vec4(color, alpha);
}