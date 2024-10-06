// stdlib
const std = @import("std");

// raylib
const rl = @import("raylib");
const rg = @import("raygui");

const SHADER_FRAG_FILEPATH = "assets/shaders/lighting.frag.glsl";

const BallLight = struct {
    const Self = @This();

    id: usize,
    selected: i32,
    position: rl.Vector2,
    color: rl.Vector4,

    locSelected: i32,
    locPosition: i32,
    locColor: i32,

    pub fn init(id: usize, selected: bool, position: rl.Vector2, color: rl.Color, shader: rl.Shader) Self {
        const normcol = color.normalize();

        var ball = Self{
            .id = id,
            .selected = @intFromBool(selected),
            .position = position,
            .color = normcol,
            .locSelected = -1,
            .locPosition = -1,
            .locColor = -1,
        };

        ball.setShaderLocations(shader);
        ball.update(shader);

        return ball;
    }

    pub fn setShaderLocations(self: *Self, shader: rl.Shader) void {
        self.locSelected = rl.getShaderLocation(shader, rl.textFormat("balls[%i].selected", .{self.id}));
        self.locPosition = rl.getShaderLocation(shader, rl.textFormat("balls[%i].position", .{self.id}));
        self.locColor = rl.getShaderLocation(shader, rl.textFormat("balls[%i].color", .{self.id}));
    }

    pub fn update(self: *Self, shader: rl.Shader) void {
        rl.setShaderValue(shader, self.locSelected, &self.selected, rl.ShaderUniformDataType.shader_uniform_int);

        const position = [_]f32{ self.position.x, self.position.y };
        rl.setShaderValue(shader, self.locPosition, &position, rl.ShaderUniformDataType.shader_uniform_vec2);

        const colorvec = [_]f32{ self.color.x, self.color.y, self.color.z, self.color.w };
        rl.setShaderValue(shader, self.locColor, &colorvec, rl.ShaderUniformDataType.shader_uniform_vec4);
    }
};

pub const Lighting = struct {
    const Self = @This();

    ambientColor: rl.Color,
    texture: rl.Texture2D,
    shader: rl.Shader,
    shaderModTime: i64,
    timeLoc: i32,
    cursorPositionLoc: i32,
    cursorPosition: rl.Vector2,
    balls: std.BoundedArray(BallLight, 16),

    pub fn init(width: i32, height: i32) Lighting {
        const imBlank: rl.Image = rl.genImageColor(width, height, rl.Color.black);
        const texture: rl.Texture2D = rl.loadTextureFromImage(imBlank);
        rl.unloadImage(imBlank);

        const shaderModTime = rl.getFileModTime(SHADER_FRAG_FILEPATH);

        const shader = rl.loadShader(undefined, SHADER_FRAG_FILEPATH);

        var lighting = Self{
            .ambientColor = rl.Color.dark_gray,
            .texture = texture,
            .shader = shader,
            .shaderModTime = shaderModTime,
            .timeLoc = 0,
            .cursorPositionLoc = 0,
            .cursorPosition = rl.Vector2.zero(),
            .balls = std.BoundedArray(BallLight, 16).init(0) catch unreachable,
        };

        lighting.setupUniforms();
        return lighting;
    }

    fn setupUniforms(self: *Self) void {
        self.timeLoc = rl.getShaderLocation(self.shader, "time");
        self.cursorPositionLoc = rl.getShaderLocation(self.shader, "cursorPosition");

        const ambientColorLoc = rl.getShaderLocation(self.shader, "ambientColor");
        rl.setShaderValue(self.shader, ambientColorLoc, &self.ambientColor.normalize(), rl.ShaderUniformDataType.shader_uniform_vec4);
        for (self.balls.slice()) |*ball| {
            ball.setShaderLocations(self.shader);
            ball.update(self.shader);
        }

        const ballCountLoc = rl.getShaderLocation(self.shader, "ballCount");
        rl.setShaderValue(self.shader, ballCountLoc, &self.balls.len, rl.ShaderUniformDataType.shader_uniform_int);
    }

    pub fn add_ball(self: *Self, id: usize, selected: bool, position: rl.Vector2, color: rl.Color) void {
        const ball = BallLight.init(id, selected, position, color, self.shader);
        self.balls.append(ball) catch unreachable;
    }

    pub fn update(self: *Self) void {
        const shaderModTime = rl.getFileModTime(SHADER_FRAG_FILEPATH);
        if (self.shaderModTime != shaderModTime) {
            // hot reload shader
            const newShader = rl.loadShader(undefined, SHADER_FRAG_FILEPATH);
            if (rl.isShaderReady(newShader)) {
                rl.unloadShader(self.shader);
                self.shader = newShader;
                self.setupUniforms();

                self.shaderModTime = shaderModTime;
            }
        }

        const time: f32 = @floatCast(rl.getTime());
        rl.setShaderValue(self.shader, self.timeLoc, &time, rl.ShaderUniformDataType.shader_uniform_float);

        self.cursorPosition = rl.Vector2.init(@floatFromInt(rl.getMouseX()), @floatFromInt(self.texture.height - rl.getMouseY()));
    }

    pub fn update_ball(self: *Self, index: usize, selected: bool, position: rl.Vector2) void {
        for (self.balls.slice()) |*ball| {
            if (ball.id == index) {
                ball.selected = @intFromBool(selected);
                ball.position = position;
                ball.update(self.shader);
                break;
            }
        }
    }

    pub fn draw(self: *Self) void {
        const pos = [_]f32{ self.cursorPosition.x, self.cursorPosition.y };
        rl.setShaderValue(self.shader, self.cursorPositionLoc, &pos, rl.ShaderUniformDataType.shader_uniform_float);

        rl.beginShaderMode(self.shader);
        rl.drawTexture(self.texture, 0, 0, rl.Color.white);
        rl.endShaderMode();
    }

    pub fn clear_balls(self: *Self) void {
        self.balls = std.BoundedArray(BallLight, 16).init(0) catch unreachable;
    }

    pub fn unload(self: *Self) void {
        rl.unloadShader(self.shader);
        rl.unloadTexture(self.texture);
    }
};
