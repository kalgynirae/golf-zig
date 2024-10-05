const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const rl = @import("raylib");
const Vector2 = rl.Vector2;

const Ball = struct {
    pos: Vector2,
    radius: f32,
    velocity: Vector2,
    spin: Vector2,

    fn init(x: f32, y: f32) Ball {
        return Ball{
            .pos = Vector2.init(x, y),
            .radius = 12,
            .velocity = Vector2.zero(),
            .spin = Vector2.zero(),
        };
    }
};

const Cursor = struct {
    state: CursorState,
    current_ball: u8,
    pos: Vector2,
    angle: Vector2,
    radius: f32,

    fn init(ball_index: u8, pos: Vector2) Cursor {
        return Cursor{
            .state = .inactive,
            .current_ball = ball_index,
            .pos = pos,
            .angle = Vector2.init(1, 0),
            .radius = 24,
        };
    }
};

const CursorState = enum {
    inactive,
    active,
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
    selecting,
    aiming,
};

const GameState = struct {
    mode: GameMode = .selecting,

    balls: ArrayList(Ball),
    cursors: ArrayList(Cursor),
    holes: ArrayList(Hole),

    fn init(allocator: Allocator) GameState {
        return GameState{
            .balls = ArrayList(Ball).init(allocator),
            .cursors = ArrayList(Cursor).init(allocator),
            .holes = ArrayList(Hole).init(allocator),
        };
    }

    fn clone(self: GameState) !GameState {
        return GameState{
            .balls = try self.balls.clone(),
            .cursors = try self.cursors.clone(),
            .holes = try self.holes.clone(),
        };
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var pastStates = ArrayList(GameState).init(allocator);
    var futureStates = ArrayList(GameState).init(allocator);
    var state = GameState.init(allocator);

    try state.balls.append(Ball.init(50, 50));
    try state.balls.append(Ball.init(500, 100));
    try state.cursors.append(Cursor.init(0, Vector2.init(50, 50)));
    try state.cursors.append(Cursor.init(1, Vector2.init(50, 50)));
    try state.holes.append(Hole.init(600, 400));

    var last_mode: GameMode = state.mode;
    var hovered_cursor_i: ?usize = null;

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

        const commands = getCommands();
        if (commands.quit) {
            break :main;
        }
        if (commands.undo) {
            if (pastStates.popOrNull()) |prev| {
                try futureStates.append(state);
                state = prev;
            }
        }
        if (commands.redo) {
            if (futureStates.popOrNull()) |fut| {
                try pastStates.append(state);
                state = fut;
            }
        }

        // Update hovered cursor
        hovered_cursor_i = null;
        const mousepos = rl.getMousePosition();
        var min_distance: f32 = 50;
        for (state.cursors.items, 0..) |cursor, i| {
            const distance = cursor.pos.subtract(mousepos).length();
            if (distance < min_distance) {
                min_distance = distance;
                hovered_cursor_i = i;
            }
        }

        switch (state.mode) {
            .selecting => {
                if (commands.act or commands.shift_act) {
                    // Set cursor active and switch mode
                    if (hovered_cursor_i) |i| {
                        var cursor = &state.cursors.items[i];
                        cursor.state = .active;
                        state.mode = .aiming;
                    }
                }
            },
            .aiming => {
                if (commands.act) {
                    try pastStates.append(state);
                    state = try state.clone();
                    for (state.cursors.items) |*cursor| {
                        if (cursor.state == .active) {
                            cursor.state = .inactive;
                            var ball = &state.balls.items[cursor.current_ball];
                            const mouse_pos = rl.getMousePosition();
                            const dir = rl.math.vector2Scale(mouse_pos.subtract(ball.pos), 0.04);
                            ball.velocity = ball.velocity.add(dir);
                        }
                    }
                    state.mode = .selecting;
                } else if (commands.shift_act) {
                    if (hovered_cursor_i) |i| {
                        var cursor = &state.cursors.items[i];
                        cursor.state = if (cursor.state == .inactive) .active else .inactive;
                    }
                    any: {
                        for (state.cursors.items) |cursor| {
                            if (cursor.state == .active) {
                                break :any;
                            }
                        }
                        state.mode = .selecting;
                    }
                }
            },
        }

        // -- PHYSICS ----------------------------
        process_physics(state.balls);

        // Align cursors to balls
        for (state.cursors.items) |*cursor| {
            cursor.pos = state.balls.items[cursor.current_ball].pos;
        }
        // Point cursors at mouse
        for (state.cursors.items) |*cursor| {
            cursor.angle = rl.getMousePosition().subtract(cursor.pos).normalize();
        }

        // -- DRAWING ----------------------------
        // holes
        for (state.holes.items) |hole| {
            rl.drawCircleV(hole.pos, hole.radius, rl.Color.init(20, 80, 20, 255));
        }
        // balls
        for (state.balls.items) |ball| {
            rl.drawCircleV(ball.pos, ball.radius, rl.Color.blue);
        }
        // cursors
        for (state.cursors.items, 0..) |cursor, i| {
            const ball = state.balls.items[cursor.current_ball];
            const color = if (i == hovered_cursor_i or cursor.state == .active) rl.Color.orange else rl.Color.green;
            rl.drawCircleLinesV(ball.pos, 24, color);
            if (state.mode == .aiming and cursor.state == .active) {
                rl.drawTriangle(
                    ball.pos.add(cursor.angle.normalize().scale(cursor.radius).rotate(0.2)),
                    ball.pos.add(cursor.angle.normalize().scale(cursor.radius).scale(1.4)),
                    ball.pos.add(cursor.angle.normalize().scale(cursor.radius).rotate(-0.2)),
                    color,
                );
            }
        }
        // mouse indicator
        rl.drawCircle(rl.getMouseX(), rl.getMouseY(), 8, rl.Color.gold);
    }
}

fn process_physics(balls: ArrayList(Ball)) void {
    for (balls.items) |*ball| {
        ball.pos = ball.pos.add(ball.velocity.clampValue(0, 10.0));
        ball.velocity = ball.velocity.scale(0.96);
        if (ball.velocity.length() < 0.1) {
            ball.velocity = Vector2.zero();
        }
    }
}

const Commands = struct {
    quit: bool = false,
    undo: bool = false,
    redo: bool = false,
    act: bool = false,
    shift_act: bool = false,
};

fn getCommands() Commands {
    var commands = Commands{};
    if (rl.isKeyPressed(.key_q)) {
        commands.quit = true;
    }
    if (rl.isKeyPressed(.key_u) or rl.isKeyPressed(.key_z)) {
        if (isShiftDown()) {
            commands.redo = true;
        } else {
            commands.undo = true;
        }
    }
    if (rl.isKeyPressed(.key_space) or rl.isMouseButtonPressed(.mouse_button_left)) {
        if (isShiftDown()) {
            commands.shift_act = true;
        } else {
            commands.act = true;
        }
    }
    return commands;
}

fn isShiftDown() bool {
    return rl.isKeyDown(.key_left_shift) or rl.isKeyDown(.key_right_shift);
}
