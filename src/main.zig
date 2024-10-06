const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const BoundedArray = std.BoundedArray;

const rl = @import("raylib");
const Vector2 = rl.Vector2;

const rg = @import("raygui");

const CURSOR_SPACING: f32 = 12;
const WIDTH: i32 = 800;
const HEIGHT: i32 = 600;

const BallState = enum {
    alive,
    dead,
    sunk,
};

const ShadowVolume = struct {
    v1: Vector2,
    v2: Vector2,
    v3: Vector2,
    v4: Vector2,

    pub fn init(v1: Vector2, v2: Vector2, v3: Vector2, v4: Vector2) ShadowVolume {
        return ShadowVolume{
            .v1 = v1,
            .v2 = v2,
            .v3 = v3,
            .v4 = v4,
        };
    }

    pub fn fromPoints(lightPos: Vector2, radius: f32, sp: Vector2, ep: Vector2) ShadowVolume {
        const falloff = radius * 2.0;
        const shadowDir: Vector2 = sp.subtract(lightPos).normalize();
        const shadowProj: Vector2 = sp.add(shadowDir.scale(falloff));

        const edgeDir: Vector2 = ep.subtract(lightPos).normalize();
        const edgeProj: Vector2 = ep.add(edgeDir.scale(falloff));

        return ShadowVolume{
            .v1 = sp,
            .v2 = ep,
            .v3 = edgeProj,
            .v4 = shadowProj,
        };
    }
};

const Light = struct {
    const Self = @This();

    pos: Vector2,
    color: rl.Color,
    active: bool,
    intensity: f32,
    radius: f32,
    needsLightingUpdate: bool,
    lightMask: rl.RenderTexture,
    bounds: rl.Rectangle,
    shadows: BoundedArray(ShadowVolume, 30),

    pub fn init(pos: Vector2, color: rl.Color, active: bool, intensity: f32, radius: f32) Self {
        const lightMask = rl.loadRenderTexture(WIDTH, HEIGHT);
        const bounds = rl.Rectangle.init(pos.x - radius, pos.y - radius, pos.x + radius, pos.y + radius);

        return Self{
            .pos = pos,
            .color = color,
            .active = active,
            .intensity = intensity,
            .radius = radius,
            .needsLightingUpdate = true,
            .lightMask = lightMask,
            .bounds = bounds,
            .shadows = BoundedArray(ShadowVolume, 30).init(0) catch unreachable,
        };
    }

    fn draw(self: *Self) void {
        rl.beginTextureMode(self.lightMask);

        rl.clearBackground(rl.Color.white);

        rl.gl.rlSetBlendFactors(rl.gl.rl_src_alpha, rl.gl.rl_src_alpha, rl.gl.rl_min);
        rl.gl.rlSetBlendMode(rl.gl.rlBlendMode.rl_blend_custom);

        rl.drawCircleGradient(self.pos.x, self.pos.y, self.radius, rl.colorAlpha(self.color, 0.0), self.color);

        rl.gl.rlDrawRenderBatchActive();

        rl.gl.rlSetBlendMode(rl.gl.rlBlendMode.rl_blend_alpha);
        rl.gl.rlSetBlendFactors(rl.gl.rl_src_alpha, rl.gl.rl_blend_src_alpha, rl.gl.rl_max);
        rl.gl.rlSetBlendMode(rl.gl.rlBlendMode.rl_blend_custom);

        for (self.shadows.slice()) |shadow| {
            const points = [_]Vector2{
                shadow.vertexUR, shadow.vertexUL, shadow.vertexLL, shadow.vertexLR,
            };
            rl.drawTriangleFan(points, rl.Color.white);
        }

        rl.gl.rlDrawRenderBatchActive();

        rl.gl.rlSetBlendMode(rl.gl.rlBlendMode.rl_blend_alpha);

        rl.endTextureMode(self.lightMask);
    }

    pub fn update(self: *Self, state: GameState) void {
        if (!self.active) {
            return;
        }

        self.shadows = BoundedArray(ShadowVolume, 30).init(0) catch unreachable;

        for (state.platforms.slice()) |platform| {
            // skip calculation if we're not inside of a platform
            if (!rl.checkCollisionPointRec(self.pos, platform.rec)) {
                continue;
            }

            // if a platform is outside of our light radius, skip it
            if (!rl.checkCollisionRecs(self.bounds, platform.rec)) {
                continue;
            }

            // top side of platform
            var shadowPoint = Vector2(platform.rec.x, platform.rec.y);
            var edgePoint = Vector2(platform.rec.x + platform.rec.width, platform.rec.y);
            if (self.pos.y > edgePoint.y) {
                self.shadows.appendAssumeCapacity(ShadowVolume.fromPoints(self.pos, self.radius, shadowPoint, edgePoint));
            }

            // right side of platform
            shadowPoint = edgePoint;
            edgePoint.y += platform.height;
            if (self.pos.x < edgePoint.x) {
                self.shadows.appendAssumeCapacity(ShadowVolume.fromPoints(self.pos, self.radius, shadowPoint, edgePoint));
            }

            // Bottom
            shadowPoint = edgePoint;
            edgePoint.x -= platform.width;
            if (self.pos.y < edgePoint.y) {
                self.shadows.appendAssumeCapacity(ShadowVolume.fromPoints(self.pos, self.radius, shadowPoint, edgePoint));
            }

            // Left
            shadowPoint = edgePoint;
            edgePoint -= platform.height;
            if (self.post.x > edgePoint.x) {
                self.shadows.appendAssumeCapacity(ShadowVolume.fromPoints(self.pos, self.radius, shadowPoint, edgePoint));
            }

            const platformShadow = ShadowVolume.init(Vector2(platform.x, platform.y), Vector2(platform.x, platform.y + platform.height), Vector2(platform.x + platform.width, platform.y + platform.height), Vector2(platform.x + platform.width, platform.y));
            self.shadows.appendAssumeCapacity(platformShadow);
            self.draw();
        }

        self.needsLightingUpdate = false;
    }
};

const Ball = struct {
    const Self = @This();

    pos: Vector2,
    radius: f32,
    velocity: Vector2,
    spin: Vector2,

    light: Light,

    cursors: BoundedArray(Cursor, 8),
    state: BallState,

    fn init(x: f32, y: f32) Self {
        return Self{
            .pos = Vector2.init(x, y),
            .radius = CURSOR_SPACING,
            .velocity = Vector2.zero(),
            .spin = Vector2.zero(),

            .light = Light.init(Vector2.init(x, y), rl.Color.white, true, 5.0, CURSOR_SPACING * 2.0),

            .cursors = BoundedArray(Cursor, 8).init(0) catch unreachable,
            .state = .alive,
        };
    }

    fn addCursor(self: *Self) void {
        const radius = CURSOR_SPACING * @as(f32, @floatFromInt(2 + self.cursors.len));
        self.cursors.appendAssumeCapacity(Cursor.init(radius));
    }

    fn clearCursors(self: *Self) void {
        self.cursors.resize(0) catch unreachable;
    }

    fn popCursor(self: *Self) void {
        _ = self.cursors.popOrNull();
    }

    fn hit(self: *Self, strength: u32) void {
        if (self.cursors.len > 0) {
            const cursor = self.cursors.orderedRemove(0);
            const delta = cursor.angle.normalize().scale(@floatFromInt(strength));
            self.velocity = self.velocity.scale(0.2).add(delta);
        }
    }

    fn sink(self: *Self) void {
        self.clearCursors();
        self.state = .sunk;
        rl.playSound(SUNK);
    }
};

const Cursor = struct {
    state: CursorState,
    angle: Vector2,
    radius: f32,

    fn init(radius: f32) Cursor {
        return Cursor{
            .state = .aiming,
            .angle = Vector2.init(1, 0),
            .radius = radius,
        };
    }
};

const CursorState = enum {
    aiming,
    set,
};

const Hole = struct {
    pos: Vector2,
    radius: f32,
    remaining_balls: u32,

    fn init(x: f32, y: f32, needed_balls: u32) Hole {
        return Hole{
            .pos = Vector2.init(x, y),
            .radius = 24,
            .remaining_balls = needed_balls,
        };
    }
};

const Platform = struct {
    rec: rl.Rectangle,

    fn init(x: f32, y: f32, width: f32, height: f32) Platform {
        return Platform{
            .rec = rl.Rectangle.init(x, y, width, height),
        };
    }
};

const GameMode = enum {
    playing,
    paused,
};

const GameState = struct {
    const Self = @This();

    levelnum: usize,
    mode: GameMode = .playing,
    next_mode: ?GameMode = null,
    shots: u32 = 0,

    balls: BoundedArray(Ball, 16),
    holes: BoundedArray(Hole, 16),
    platforms: BoundedArray(Platform, 32),

    fn init(levelnum: usize) Self {
        return Self{
            .levelnum = levelnum,
            .balls = BoundedArray(Ball, 16).init(0) catch unreachable,
            .holes = BoundedArray(Hole, 16).init(0) catch unreachable,
            .platforms = BoundedArray(Platform, 32).init(0) catch unreachable,
        };
    }

    fn clone(self: Self) Self {
        return Self{
            .levelnum = self.levelnum,
            .shots = self.shots,
            .balls = self.balls,
            .holes = self.holes,
            .platforms = self.platforms,
        };
    }
};

var CLICK: rl.Sound = undefined;
var LOWCLICK: rl.Sound = undefined;
var SUNK: rl.Sound = undefined;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    _ = rg.guiLoadIcons("assets/iconset.rgi", false);
    _ = rg.guiSetIconScale(2);
    rl.setConfigFlags(rl.ConfigFlags{ .vsync_hint = true });
    rl.initWindow(WIDTH, HEIGHT, "Golf!");
    defer rl.closeWindow();

    var pastStates = ArrayList(GameState).init(allocator);
    var futureStates = ArrayList(GameState).init(allocator);
    var state = level1();

    var last_mode: GameMode = state.mode;
    var hovered_ball: ?usize = null;
    var any_aiming_cursors = false;
    var any_set_cursors = false;
    var potentially_adding_cursor = false;
    var strength: ?u32 = null;

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    CLICK = rl.loadSound("assets/click.wav");
    LOWCLICK = rl.loadSound("assets/lowclick.wav");
    SUNK = rl.loadSound("assets/sunk.wav");

    const music = rl.loadMusicStream("assets/placeholder-music.ogg");
    rl.setMusicVolume(music, 0.4);
    rl.playMusicStream(music);

    rl.setTargetFPS(60);

    var camera = rl.Camera2D{
        .offset = Vector2.zero(),
        .target = Vector2.zero(),
        .rotation = 0,
        .zoom = 1.0,
    };

    main: while (!rl.windowShouldClose()) {
        if (state.mode != last_mode) {
            std.debug.print("\x1b[1;36mMode changed: {}\x1b[0m\n", .{state.mode});
            last_mode = state.mode;
        }

        const input = getInput();
        if (input.quit) {
            break :main;
        }

        if (input.level) |levelnum| {
            state = switch (levelnum) {
                1 => level1(),
                2 => level2(),
                3 => level3(),
                4 => level4(),
                5 => level5(),
                else => |v| lvl: {
                    std.debug.print("\x1b[1;31mUnhandled level number: {}\x1b[0m\n", .{v});
                    break :lvl level1();
                },
            };
            pastStates.clearRetainingCapacity();
            futureStates.clearRetainingCapacity();
        }

        rl.updateMusicStream(music);
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);

        if (state.next_mode) |mode| {
            state.mode = mode;
            state.next_mode = null;
        }
        if (input.tick) {
            state.mode = .playing;
            state.next_mode = .paused;
        }
        switch (state.mode) {
            .paused => {
                if (input.pause) {
                    state.mode = .playing;
                }
            },
            .playing => {
                if (input.pause) {
                    state.mode = .paused;
                }
                if (input.undo) {
                    if (pastStates.popOrNull()) |prev| {
                        try futureStates.append(state);
                        state = prev;
                    }
                }
                if (input.redo) {
                    if (futureStates.popOrNull()) |fut| {
                        try pastStates.append(state);
                        state = fut;
                    }
                }

                // Update hovered cursor
                hovered_ball = null;
                const mousepos = rl.getMousePosition().transform(camera.getMatrix().invert());
                var min_distance: f32 = 100;
                for (state.balls.slice(), 0..) |ball, i| {
                    if (ball.state != .alive) continue;
                    const distance = ball.pos.subtract(mousepos).length();
                    if (distance < min_distance) {
                        min_distance = distance;
                        hovered_ball = i;
                    }
                }

                any_aiming_cursors = false;
                any_set_cursors = false;
                for (state.balls.constSlice()) |ball| {
                    for (ball.cursors.constSlice()) |cursor| {
                        if (cursor.state == .aiming) {
                            any_aiming_cursors = true;
                        } else if (cursor.state == .set) {
                            any_set_cursors = true;
                        }
                    }
                }

                potentially_adding_cursor = (!any_aiming_cursors and !any_set_cursors) or input.shift;

                if (strength) |s| {
                    try pastStates.append(state);
                    state = state.clone();
                    for (state.balls.slice()) |*ball| {
                        ball.hit(s);
                    }
                    state.shots += 1;
                }
                if (input.primary) {
                    if (potentially_adding_cursor) {
                        if (hovered_ball) |i| {
                            state.balls.buffer[i].addCursor();
                        }
                    } else if (any_aiming_cursors) {
                        for (state.balls.slice()) |*ball| {
                            for (ball.cursors.slice()) |*cursor| {
                                if (cursor.state == .aiming) {
                                    cursor.state = .set;
                                }
                            }
                        }
                    }
                }
                if (input.secondary) {
                    if (hovered_ball) |i| {
                        state.balls.buffer[i].popCursor();
                    }
                }

                // -- PHYSICS ----------------------------
                processPhysics(
                    state.balls.slice(),
                    state.holes.slice(),
                    state.platforms.slice(),
                );

                // Point cursors at mouse
                for (state.balls.slice()) |*ball| {
                    for (ball.cursors.slice()) |*cursor| {
                        if (cursor.state == .aiming) {
                            cursor.angle = rl.getMousePosition().transform(camera.getMatrix().invert()).subtract(ball.pos);
                        }
                    }
                }
            },
        }

        // -- DRAWING ----------------------------
        {
            camera.begin();
            defer camera.end();

            //platforms
            for (state.platforms.slice()) |platform| {
                rl.drawRectangleRec(platform.rec, rl.Color.init(30, 80, 95, 255));
            }
            // holes
            for (state.holes.slice()) |hole| {
                switch (hole.remaining_balls) {
                    0 => {
                        rl.drawCircleV(hole.pos, hole.radius, rl.Color.init(35, 65, 75, 255));
                    },
                    1 => {
                        rl.drawCircleV(hole.pos, hole.radius, rl.Color.init(0, 60, 20, 255));
                    },
                    else => {
                        rl.drawCircleV(hole.pos, hole.radius, rl.Color.init(0, 30, 0, 255));
                    },
                }
                rl.drawText(
                    std.fmt.allocPrintZ(allocator, "{}", .{hole.remaining_balls}) catch unreachable,
                    @intFromFloat(hole.pos.x - 4),
                    @intFromFloat(hole.pos.y - 2),
                    32,
                    rl.Color.white,
                );
            }
            // balls
            for (state.balls.slice()) |ball| {
                switch (ball.state) {
                    .alive => {
                        rl.drawCircleV(ball.pos, ball.radius, rl.Color.blue);
                        rl.drawCircle(
                            @intFromFloat(ball.pos.x - 4),
                            @intFromFloat(ball.pos.y - 2),
                            2,
                            rl.Color.black,
                        );
                        rl.drawCircle(
                            @intFromFloat(ball.pos.x + 4),
                            @intFromFloat(ball.pos.y - 2),
                            2,
                            rl.Color.black,
                        );
                        if (ball.velocity.equals(Vector2.zero()) == 1) {
                            rl.drawLine(
                                @intFromFloat(ball.pos.x - 3),
                                @intFromFloat(ball.pos.y + 5),
                                @intFromFloat(ball.pos.x + 3),
                                @intFromFloat(ball.pos.y + 5),
                                rl.Color.black,
                            );
                        } else {
                            rl.drawEllipse(
                                @intFromFloat(ball.pos.x),
                                @intFromFloat(ball.pos.y + 5),
                                4,
                                1 + @min(5, @round(ball.velocity.length() * 1.5)),
                                rl.Color.black,
                            );
                        }
                        // DEBUGGING:
                        // rl.drawLineV(ball.pos, ball.pos.add(ball.velocity.scale(5)), rl.Color.purple);
                        // rl.drawLineV(ball.pos, ball.pos.add(ball.spin.scale(5)), rl.Color.sky_blue);
                    },
                    .dead => {
                        rl.drawCircleV(ball.pos, ball.radius, rl.Color.dark_gray);
                    },
                    .sunk => {},
                }
            }
            // cursors
            for (state.balls.slice()) |ball| {
                for (ball.cursors.slice()) |cursor| {
                    const color = switch (cursor.state) {
                        .aiming => rl.Color.orange,
                        .set => rl.Color.green,
                    };
                    rl.drawCircleLinesV(ball.pos, cursor.radius, color);
                    rl.drawTriangle(
                        ball.pos.add(cursor.angle.normalize().scale(cursor.radius).rotate(0.2)),
                        ball.pos.add(cursor.angle.normalize().scale(cursor.radius + 6)),
                        ball.pos.add(cursor.angle.normalize().scale(cursor.radius).rotate(-0.2)),
                        color,
                    );
                }
            }
            // placeholder cursor
            if (potentially_adding_cursor) {
                if (hovered_ball) |i| {
                    const ball = state.balls.get(i);
                    const next_level: u32 = ball.cursors.len + 1;
                    rl.drawCircleLinesV(
                        ball.pos,
                        ball.radius + CURSOR_SPACING * @as(f32, @floatFromInt(next_level)),
                        rl.Color.sky_blue,
                    );
                }
            }
        }

        // mouse indicator
        rl.drawCircle(rl.getMouseX(), rl.getMouseY(), 8, rl.Color.gold);

        rl.drawText("Golf!", 710, 10, 32, rl.Color.light_gray);
        rl.drawText(
            std.fmt.allocPrintZ(allocator, "Level: {}", .{state.levelnum}) catch unreachable,
            710,
            42,
            16,
            rl.Color.light_gray,
        );
        rl.drawText(
            std.fmt.allocPrintZ(allocator, "Shots: {}", .{state.shots}) catch unreachable,
            710,
            58,
            16,
            rl.Color.light_gray,
        );
        rl.drawText(
            std.fmt.allocPrintZ(allocator, "{} FPS", .{rl.getFPS()}) catch unreachable,
            720,
            580,
            16,
            rl.Color.light_gray,
        );

        strength = null;
        if (!potentially_adding_cursor and !any_aiming_cursors) {
            strength = getHitStrength();
        }
    }
}

fn processPhysics(balls: []Ball, holes: []Hole, platforms: []Platform) void {
    const STEPS = 8;
    const SCALE: f32 = 1.0 / @as(f32, @floatFromInt(STEPS));
    const MAX_SPEED: f32 = 25.0 / @as(f32, @floatFromInt(STEPS));

    for (0..STEPS) |step| {
        for (balls) |*ball| {
            if (ball.state == .sunk) {
                continue;
            }
            if (ball.velocity.length() < 0.5 and ball.spin.length() < 0.5) {
                ball.spin = Vector2.zero();
                ball.velocity = Vector2.zero();
            }

            // platforms
            platformcheck: {
                for (platforms) |platform| {
                    if (rl.checkCollisionPointRec(ball.pos, platform.rec)) {
                        ball.state = .alive;
                        break :platformcheck;
                    }
                }
                ball.state = .dead;
                continue;
            }

            if (ball.velocity.equals(Vector2.zero()) == 1) {
                continue;
            }

            // movement & collisions
            const delta = ball.velocity.scale(SCALE).clampValue(0, MAX_SPEED);
            const reflection = reflect: {
                const NORMALS: [4]Vector2 = .{ Vector2.zero(), Vector2.init(1, 0), Vector2.init(0, 1), Vector2.init(1, 1) };
                for (NORMALS) |normal| {
                    const reflected = delta.reflect(normal);
                    const tentative_pos = ball.pos.add(reflected);
                    for (platforms) |platform| {
                        if (rl.checkCollisionPointRec(tentative_pos, platform.rec)) {
                            break :reflect normal;
                        }
                    }
                }
                break :reflect Vector2.zero();
            };
            if (reflection.equals(Vector2.zero()) == 0) {
                rl.playSound(LOWCLICK);
            }
            ball.pos = ball.pos.add(delta.reflect(reflection));
            ball.velocity = ball.velocity.reflect(reflection);

            if (step == 0) {
                // spin
                // reduce in perpendicular direction
                const velocity_dir = ball.velocity.normalize();
                const parallel_spin_len = ball.spin.dotProduct(velocity_dir);
                const parallel_spin = velocity_dir.scale(parallel_spin_len);
                // rl.drawLineEx(ball.pos, ball.pos.add(parallel_component), 5, rl.Color.red);
                const perpendicular_spin = ball.spin.subtract(parallel_spin);
                // rl.drawLineEx(ball.pos, ball.pos.add(perpendicular_component.scale(10)), 5, rl.Color.yellow);
                ball.spin = ball.spin.subtract(perpendicular_spin.scale(0.1));

                // normalize toward velocity in parallel direction
                const velocity_spin_diff = ball.velocity.length() - parallel_spin_len;
                if (velocity_spin_diff > 0) {
                    ball.spin = ball.spin.add(velocity_dir.scale(velocity_spin_diff).scale(0.2));
                } else {
                    // backward spin decreases faster
                    ball.spin = ball.spin.add(velocity_dir.scale(velocity_spin_diff).scale(0.3));
                }

                // spin adjusts velocity
                ball.velocity = ball.velocity.add(ball.spin.subtract(ball.velocity).scale(0.01));

                // friction
                // parallel spin reduces friction
                const friction = 0.08 - 0.05 * (parallel_spin_len / ball.velocity.length());
                ball.spin = ball.spin.scale(1.0 - friction);
                ball.velocity = ball.velocity.scale(1.0 - friction);
            }
        }

        // other balls
        for (balls[0..(balls.len - 1)], 0..) |*a, ai| {
            if (a.state != .alive) continue;
            for (balls[(ai + 1)..balls.len]) |*b| {
                if (b.state != .alive) continue;
                if (rl.checkCollisionCircles(a.pos, a.radius, b.pos, b.radius)) {
                    const between = a.pos.subtract(b.pos).normalize();
                    const a_parallel_vel = between.scale(a.velocity.dotProduct(between));
                    const b_parallel_vel = between.scale(b.velocity.dotProduct(between));
                    a.velocity = a.velocity.subtract(a_parallel_vel).add(b_parallel_vel);
                    b.velocity = b.velocity.add(a_parallel_vel).subtract(b_parallel_vel);
                    a.spin = a.spin.scale(0.5);
                    b.spin = b.spin.scale(0.5);
                    rl.playSound(CLICK);
                }
            }
        }

        // holes
        for (balls) |*ball| {
            if (ball.state != .alive) continue;
            for (holes) |*hole| {
                if (hole.remaining_balls == 0) continue;
                if (rl.checkCollisionPointCircle(ball.pos, hole.pos, (hole.radius - (ball.radius / 2)))) {
                    ball.sink();
                    hole.remaining_balls -= 1;
                }
            }
        }
    }
}

const Input = struct {
    quit: bool = false,
    pause: bool = false,
    tick: bool = false,
    undo: bool = false,
    redo: bool = false,
    primary: bool = false,
    secondary: bool = false,
    shift: bool = false,
    level: ?usize = null,
};

fn getInput() Input {
    var input = Input{};
    if (rl.isKeyPressed(.key_q)) {
        input.quit = true;
    }
    if (rl.isKeyPressed(.key_p)) {
        input.pause = true;
    }
    if (rl.isKeyPressed(.key_t)) {
        input.tick = true;
    }
    input.shift = rl.isKeyDown(.key_left_shift) or rl.isKeyDown(.key_right_shift);
    if (rl.isKeyPressed(.key_u) or rl.isKeyPressed(.key_z)) {
        if (input.shift) {
            input.redo = true;
        } else {
            input.undo = true;
        }
    }
    if (rl.isKeyPressed(.key_space) or rl.isMouseButtonPressed(.mouse_button_left)) {
        input.primary = true;
    }
    if (rl.isKeyPressed(.key_backspace) or rl.isMouseButtonPressed(.mouse_button_right)) {
        input.secondary = true;
    }

    if (rl.isKeyPressed(.key_one)) {
        input.level = 1;
    }
    if (rl.isKeyPressed(.key_two)) {
        input.level = 2;
    }
    if (rl.isKeyPressed(.key_three)) {
        input.level = 3;
    }
    if (rl.isKeyPressed(.key_four)) {
        input.level = 4;
    }
    if (rl.isKeyPressed(.key_five)) {
        input.level = 5;
    }
    if (rl.isKeyPressed(.key_six)) {
        input.level = 6;
    }
    if (rl.isKeyPressed(.key_seven)) {
        input.level = 7;
    }
    if (rl.isKeyPressed(.key_eight)) {
        input.level = 8;
    }
    if (rl.isKeyPressed(.key_nine)) {
        input.level = 9;
    }
    if (rl.isKeyPressed(.key_zero)) {
        input.level = 10;
    }

    return input;
}

fn getHitStrength() ?u32 {
    var strength: ?u32 = null;
    if (rg.guiButton(rl.Rectangle.init(0, HEIGHT - 50, WIDTH / 4, 50), "#220#") != 0) {
        strength = 5;
    }
    if (rg.guiButton(rl.Rectangle.init(1 * (WIDTH / 4), HEIGHT - 50, WIDTH / 4, 50), "#221#") != 0) {
        strength = 15;
    }
    if (rg.guiButton(rl.Rectangle.init(2 * (WIDTH / 4), HEIGHT - 50, WIDTH / 4, 50), "#222#") != 0) {
        strength = 35;
    }
    if (rg.guiButton(rl.Rectangle.init(3 * (WIDTH / 4), HEIGHT - 50, WIDTH / 4, 50), "#223#") != 0) {
        strength = 80;
    }
    return strength;
}

fn level1() GameState {
    var state = GameState.init(1);
    state.balls.appendAssumeCapacity(Ball.init(50, 50));
    state.balls.appendAssumeCapacity(Ball.init(500, 100));
    state.holes.appendAssumeCapacity(Hole.init(600, 400, 1));
    state.holes.appendAssumeCapacity(Hole.init(500, 520, 1));
    state.platforms.appendAssumeCapacity(Platform.init(20, 20, 460, 560));
    state.platforms.appendAssumeCapacity(Platform.init(460, 40, 200, 500));
    return state;
}

fn level2() GameState {
    var state = GameState.init(2);
    state.platforms.appendAssumeCapacity(Platform.init(20, 50, 180, 500));
    state.platforms.appendAssumeCapacity(Platform.init(200, 250, 400, 100));
    state.platforms.appendAssumeCapacity(Platform.init(600, 50, 180, 500));

    state.holes.appendAssumeCapacity(Hole.init(710, 500, 1));

    state.balls.appendAssumeCapacity(Ball.init(90, 100));

    return state;
}

fn level3() GameState {
    var state = GameState.init(3);
    inline for (0..4) |i| {
        state.platforms.appendAssumeCapacity(Platform.init(20 + 190 * i, 260, 95, 100));
        state.platforms.appendAssumeCapacity(Platform.init(115 + 190 * i, 240, 95, 100));
    }

    state.holes.appendAssumeCapacity(Hole.init(735, 272, 1));

    state.balls.appendAssumeCapacity(Ball.init(68, 350));

    return state;
}

fn level4() GameState {
    var state = GameState.init(4);
    state.platforms.appendAssumeCapacity(Platform.init(50, 50, 700, 500));

    state.holes.appendAssumeCapacity(Hole.init(200, 460, 0));
    state.holes.appendAssumeCapacity(Hole.init(400, 460, 2));
    state.holes.appendAssumeCapacity(Hole.init(600, 460, 1));

    state.balls.appendAssumeCapacity(Ball.init(200, 120));
    state.balls.appendAssumeCapacity(Ball.init(400, 120));
    state.balls.appendAssumeCapacity(Ball.init(600, 120));

    return state;
}

fn level5() GameState {
    var state = GameState.init(5);
    state.platforms.appendAssumeCapacity(Platform.init(50, 100, 200, 400));
    state.platforms.appendAssumeCapacity(Platform.init(250, 200, 150, 200));
    state.platforms.appendAssumeCapacity(Platform.init(400, 100, 150, 150));
    state.platforms.appendAssumeCapacity(Platform.init(400, 350, 150, 150));
    state.platforms.appendAssumeCapacity(Platform.init(550, 100, 200, 400));

    state.holes.appendAssumeCapacity(Hole.init(600, 300, 2));

    state.balls.appendAssumeCapacity(Ball.init(90, 165));
    state.balls.appendAssumeCapacity(Ball.init(90, 435));

    return state;
}
