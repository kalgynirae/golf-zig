const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const BoundedArray = std.BoundedArray;

const rl = @import("raylib");
const Vector2 = rl.Vector2;

const CURSOR_SPACING: f32 = 12;

const Ball = struct {
    const Self = @This();

    pos: Vector2,
    radius: f32,
    velocity: Vector2,
    spin: Vector2,

    cursors: BoundedArray(Cursor, 8),

    fn init(x: f32, y: f32) Self {
        return Self{
            .pos = Vector2.init(x, y),
            .radius = CURSOR_SPACING,
            .velocity = Vector2.zero(),
            .spin = Vector2.zero(),

            .cursors = BoundedArray(Cursor, 8).init(0) catch unreachable,
        };
    }

    fn addCursor(self: *Self) void {
        self.cursors.appendAssumeCapacity(Cursor.init(self.cursors.len));
    }

    fn hit(self: *Self) void {
        if (self.cursors.len > 0) {
            const cursor = self.cursors.orderedRemove(0);
            const delta = cursor.angle.scale(0.04);
            self.velocity = self.velocity.add(delta);
        }
    }
};

const Cursor = struct {
    state: CursorState,
    angle: Vector2,
    radius: f32,

    fn init(level: u32) Cursor {
        return Cursor{
            .state = .aiming,
            .angle = Vector2.init(1, 0),
            .radius = @as(f32, @floatFromInt(level + 1)) * CURSOR_SPACING,
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

    fn init(x: f32, y: f32) Hole {
        return Hole{
            .pos = Vector2.init(x, y),
            .radius = 24,
        };
    }
};

const GameMode = enum {
    playing,
    paused,
};

const GameState = struct {
    const Self = @This();

    mode: GameMode = .playing,

    balls: BoundedArray(Ball, 16),
    holes: BoundedArray(Hole, 16),

    fn init() Self {
        return Self{
            .balls = BoundedArray(Ball, 16).init(0) catch unreachable,
            .holes = BoundedArray(Hole, 16).init(0) catch unreachable,
        };
    }

    fn clone(self: Self) Self {
        return Self{
            .balls = self.balls,
            .holes = self.holes,
        };
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var pastStates = ArrayList(GameState).init(allocator);
    var futureStates = ArrayList(GameState).init(allocator);
    var state = GameState.init();

    try state.balls.append(Ball.init(50, 50));
    try state.balls.append(Ball.init(500, 100));
    try state.holes.append(Hole.init(600, 400));

    var last_mode: GameMode = state.mode;
    var hovered_ball: ?usize = null;
    var potentially_adding_cursor = false;

    rl.setConfigFlags(rl.ConfigFlags{ .vsync_hint = true });
    rl.initWindow(800, 600, "test");
    defer rl.closeWindow();

    main: while (!rl.windowShouldClose()) {
        if (state.mode != last_mode) {
            std.debug.print("Mode changed: {}", .{state.mode});
            last_mode = state.mode;
        }
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);
        rl.drawText("Golf!", 710, 10, 32, rl.Color.light_gray);

        const input = getInput();
        if (input.quit) {
            break :main;
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
                const mousepos = rl.getMousePosition();
                var min_distance: f32 = 100;
                for (state.balls.slice(), 0..) |ball, i| {
                    const distance = ball.pos.subtract(mousepos).length();
                    if (distance < min_distance) {
                        min_distance = distance;
                        hovered_ball = i;
                    }
                }

                var any_aiming_cursors = false;
                var any_set_cursors = false;
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
                    } else {
                        try pastStates.append(state);
                        state = state.clone();
                        for (state.balls.slice()) |*ball| {
                            ball.hit();
                        }
                    }
                }

                // -- PHYSICS ----------------------------
                processPhysics(state.balls.slice());

                // Point cursors at mouse
                for (state.balls.slice()) |*ball| {
                    for (ball.cursors.slice()) |*cursor| {
                        if (cursor.state == .aiming) {
                            cursor.angle = rl.getMousePosition().subtract(ball.pos);
                        }
                    }
                }
            },
        }

        // -- DRAWING ----------------------------
        // holes
        for (state.holes.slice()) |hole| {
            rl.drawCircleV(hole.pos, hole.radius, rl.Color.init(20, 80, 20, 255));
        }
        // balls
        for (state.balls.slice()) |ball| {
            rl.drawCircleV(ball.pos, ball.radius, rl.Color.blue);
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
                    ball.pos.add(cursor.angle),
                    ball.pos.add(cursor.angle.normalize().scale(cursor.radius).rotate(-0.2)),
                    color,
                );
            }
        }
        // placeholder cursor
        if (potentially_adding_cursor) {
            if (hovered_ball) |i| {
                const ball = state.balls.get(i);
                const nesting: u32 = ball.cursors.len + 1;
                rl.drawCircleLinesV(
                    ball.pos,
                    ball.radius + CURSOR_SPACING * @as(f32, @floatFromInt(nesting)),
                    rl.Color.sky_blue,
                );
            }
        }
        // mouse indicator
        rl.drawCircle(rl.getMouseX(), rl.getMouseY(), 8, rl.Color.gold);
    }
}

fn processPhysics(balls: []Ball) void {
    for (balls) |*ball| {
        ball.pos = ball.pos.add(ball.velocity.clampValue(0, 10.0));
        ball.velocity = ball.velocity.scale(0.96);
        if (ball.velocity.length() < 0.1) {
            ball.velocity = Vector2.zero();
        }
    }
}

const Input = struct {
    quit: bool = false,
    pause: bool = false,
    undo: bool = false,
    redo: bool = false,
    primary: bool = false,
    secondary: bool = false,
    shift: bool = false,
};

fn getInput() Input {
    var input = Input{};
    if (rl.isKeyPressed(.key_q)) {
        input.quit = true;
    }
    if (rl.isKeyPressed(.key_p)) {
        input.pause = true;
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
    return input;
}
