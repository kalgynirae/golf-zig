// stdlib
const std = @import("std");

// raylib
const rl = @import("raylib");
const rg = @import("raygui");

const SHADER_FRAG_FILEPATH = "assets/shaders/lighting.frag.glsl";

pub const Lighting = struct {
    const Self = @This();

    texture: rl.Texture2D,
    shader: rl.Shader,
    shaderModTime: i64,
    time: f32,
    timeLoc: i32,
    cursorPositionXLoc: i32,
    cursorPositionYLoc: i32,
    cursorPositionX: f32,
    cursorPositionY: f32,

    pub fn init(width: i32, height: i32) Lighting {
        const imBlank: rl.Image = rl.genImageColor(width, height, rl.Color.black);
        const texture: rl.Texture2D = rl.loadTextureFromImage(imBlank);
        rl.unloadImage(imBlank);

        const shaderModTime = rl.getFileModTime(SHADER_FRAG_FILEPATH);

        const shader = rl.loadShader("", SHADER_FRAG_FILEPATH);

        var lighting = Self{
            .texture = texture,
            .shader = shader,
            .shaderModTime = shaderModTime,
            .timeLoc = 0,
            .time = 0.0,
            .cursorPositionXLoc = 0,
            .cursorPositionYLoc = 0,
            .cursorPositionX = 0,
            .cursorPositionY = 0,
        };

        lighting.populateLocations();
        return lighting;
    }

    fn populateLocations(self: *Self) void {
        self.timeLoc = rl.getShaderLocation(self.shader, "uTime");
        self.cursorPositionXLoc = rl.getShaderLocation(self.shader, "uCursorPositionX");
        self.cursorPositionYLoc = rl.getShaderLocation(self.shader, "uCursorPositionY");
    }

    pub fn update(self: *Self) void {
        const time: f32 = @floatCast(rl.getTime());
        self.time = time;

        const shaderModTime = rl.getFileModTime(SHADER_FRAG_FILEPATH);
        if (self.shaderModTime != shaderModTime) {
            // hot reload shader
            const newShader = rl.loadShader("", SHADER_FRAG_FILEPATH);
            if (rl.isShaderReady(newShader)) {
                rl.unloadShader(self.shader);
                self.shader = newShader;
                self.populateLocations();
                self.shaderModTime = shaderModTime;
            }
        }

        const cursorPosition = rl.getMousePosition();
        self.cursorPositionX = cursorPosition.x;
        self.cursorPositionY = cursorPosition.y;
    }

    pub fn draw(self: *Self) void {
        rl.setShaderValue(self.shader, self.timeLoc, &self.time, rl.ShaderUniformDataType.shader_uniform_float);
        rl.setShaderValue(self.shader, self.cursorPositionXLoc, &self.cursorPositionX, rl.ShaderUniformDataType.shader_uniform_float);
        rl.setShaderValue(self.shader, self.cursorPositionYLoc, &self.cursorPositionY, rl.ShaderUniformDataType.shader_uniform_float);

        rl.beginShaderMode(self.shader);
        rl.drawTexture(self.texture, 0, 0, rl.Color.white);
        rl.endShaderMode();
    }

    pub fn unload(self: *Self) void {
        rl.unloadShader(self.shader);
        rl.unloadTexture(self.texture);
    }
};
