// stdlib
const std = @import("std");

// raylib
const rl = @import("raylib");
const rg = @import("raygui");

pub const Lighting = struct {
    const Self = @This();

    texture: rl.Texture2D,
    shader: rl.Shader,
    shaderModTime: i64,
    time: f32,
    timeLoc: i32,
    cursorLoc: i32,

    pub fn init(width: i32, height: i32) Lighting {
        const imBlank: rl.Image = rl.genImageColor(width, height, rl.colorAlpha(rl.Color.blank, 1.0));
        const texture: rl.Texture2D = rl.loadTextureFromImage(imBlank);
        rl.unloadImage(imBlank);

        const shaderModTime = rl.getFileModTime("assets/shaders/cubes_panning.frag.glsl");

        const shader = rl.loadShader("", "assets/shaders/cubes_panning.frag.glsl");

        var lighting = Self{
            .texture = texture,
            .shader = shader,
            .shaderModTime = shaderModTime,
            .timeLoc = 0,
            .time = 0.0,
            .cursorLoc = 0,
        };

        lighting.populateLocations();
        return lighting;
    }

    fn populateLocations(self: *Self) void {
        self.timeLoc = rl.getShaderLocation(self.shader, "uTime");
        self.cursorLoc = rl.getShaderLocation(self.shader, "uCursor");
    }

    pub fn update(self: *Self) void {
        const time: f32 = @floatCast(rl.getTime());
        self.time = time;

        const shaderModTime = rl.getFileModTime("assets/shaders/cubes_panning.frag.glsl");
        if (self.shaderModTime != shaderModTime) {
            // hot reload shader
            const newShader = rl.loadShader("", "assets/shaders/cubes_panning.frag.glsl");
            if (newShader.id != rl.gl.rlGetShaderIdDefault()) {
                rl.unloadShader(self.shader);
                self.shader = newShader;
                self.populateLocations();
                self.shaderModTime = shaderModTime;
            }
        }
    }

    pub fn draw(self: *Self, cursorPos: rl.Vector2) void {
        rl.setShaderValue(self.shader, self.timeLoc, &self.time, rl.ShaderUniformDataType.shader_uniform_float);
        rl.setShaderValue(self.shader, self.cursorLoc, &cursorPos, rl.ShaderUniformDataType.shader_uniform_vec2);
        rl.beginShaderMode(self.shader);
        rl.drawTexture(self.texture, 0, 0, rl.Color.white);
        rl.endShaderMode();
    }

    pub fn unload(self: *Self) void {
        rl.unloadShader(self.shader);
        rl.unloadTexture(self.texture);
    }
};
