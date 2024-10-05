const std = @import("std");
const Allocator = std.mem.Allocator;

const rl = @import("raylib");
const Vector2 = rl.Vector2;

const Ball = struct {
    pos: Vector2,
    velocity: Vector2,
    spin: Vector2,

    fn init(x: f32, y: f32) Ball {
        return Ball{
            .pos = Vector2.init(x, y),
            .velocity = Vector2.zero(),
            .spin = Vector2.zero(),
        };
    }
    fn x_i32(self: Ball) i32 {
        return @intFromFloat(self.pos.x);
    }
    fn y_i32(self: Ball) i32 {
        return @intFromFloat(self.pos.y);
    }
};

const Cursor = struct {
    current_ball: u8,
    state: CursorState,

    fn init(ball: u8) Cursor {
        return Cursor{
            .current_ball = ball,
            .state = .inactive,
        };
    }
};

const CursorState = enum {
    inactive,
    aiming,
};

const Hole = struct {
    pos: Vector2,
    size: u8,

    fn init(x: f32, y: f32) Hole {
        return Hole{
            .pos = Vector2.init(x, y),
            .size = 24,
        };
    }
    fn x_i32(self: Hole) i32 {
        return @intFromFloat(self.pos.x);
    }
    fn y_i32(self: Hole) i32 {
        return @intFromFloat(self.pos.y);
    }
};

const GameState = struct {
    balls: std.ArrayList(Ball),
    cursors: std.ArrayList(Cursor),
    holes: std.ArrayList(Hole),

    fn init(allocator: Allocator) GameState {
        return GameState{
            .balls = std.ArrayList(Ball).init(allocator),
            .cursors = std.ArrayList(Cursor).init(allocator),
            .holes = std.ArrayList(Hole).init(allocator),
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

    var pastStates = std.ArrayList(GameState).init(allocator);
    var futureStates = std.ArrayList(GameState).init(allocator);
    var state = GameState.init(allocator);
    try state.balls.append(Ball.init(50, 50));
    try state.cursors.append(Cursor.init(0));
    try state.holes.append(Hole.init(600, 400));

    rl.setConfigFlags(rl.ConfigFlags{ .vsync_hint = true });
    rl.initWindow(800, 600, "test");
    defer rl.closeWindow();

    main: while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);
        rl.drawText("Golf!", 710, 10, 32, rl.Color.light_gray);

        var commands = try getCommands(allocator);
        defer commands.deinit();
        for (commands.items) |command| {
            switch (command) {
                .quit => break :main,
                .undo => {
                    if (pastStates.popOrNull()) |prev| {
                        try futureStates.append(state);
                        state = prev;
                    }
                },
                .redo => {
                    if (futureStates.popOrNull()) |fut| {
                        try pastStates.append(state);
                        state = fut;
                    }
                },
                .act => {
                    for (state.cursors.items) |*cursor| {
                        switch (cursor.state) {
                            .inactive => {
                                cursor.state = .aiming;
                            },
                            .aiming => {
                                cursor.state = .inactive;
                                try pastStates.append(state);
                                state = try state.clone();
                                var ball = &state.balls.items[cursor.current_ball];
                                const mouse_pos = rl.getMousePosition();
                                const dir = rl.math.vector2Scale(mouse_pos.subtract(ball.pos), 0.04);
                                ball.velocity = ball.velocity.add(dir);
                            },
                        }
                    }
                },
            }
        }
        // -- KEYS -------------------------------
        // act

        // -- PHYSICS ----------------------------
        process_physics(state.balls);

        // -- DRAWING ----------------------------
        // holes
        for (state.holes.items) |hole| {
            rl.drawCircle(hole.x_i32(), hole.y_i32(), @floatFromInt(hole.size), rl.Color.init(20, 80, 20, 255));
        }
        // balls
        for (state.balls.items) |ball| {
            rl.drawCircle(ball.x_i32(), ball.y_i32(), 12, rl.Color.blue);
        }
        // cursors
        for (state.cursors.items) |cursor| {
            const ball = state.balls.items[cursor.current_ball];
            rl.drawCircleLines(ball.x_i32(), ball.y_i32(), 24, switch (cursor.state) {
                .inactive => rl.Color.green,
                .aiming => rl.Color.orange,
            });
        }
        // mouse indicator
        rl.drawCircle(rl.getMouseX(), rl.getMouseY(), 8, rl.Color.gold);
    }
}

fn process_physics(balls: std.ArrayList(Ball)) void {
    for (balls.items) |*ball| {
        ball.pos = ball.pos.add(ball.velocity.clampValue(0, 10.0));
        ball.velocity = ball.velocity.scale(0.96);
        if (ball.velocity.length() < 0.1) {
            ball.velocity = Vector2.zero();
        }
    }
}

const Command = enum {
    quit,
    act,
    undo,
    redo,
};

fn getCommands(allocator: Allocator) !std.ArrayList(Command) {
    var commands = std.ArrayList(Command).init(allocator);
    if (rl.isKeyPressed(.key_q)) {
        try commands.append(.quit);
    }
    if (rl.isKeyPressed(.key_u) or rl.isKeyPressed(.key_z)) {
        try commands.append(if (isShiftDown()) .redo else .undo);
    }
    if (rl.isKeyPressed(.key_space) or rl.isMouseButtonPressed(.mouse_button_left)) {
        try commands.append(.act);
    }
    return commands;
}

fn isShiftDown() bool {
    return rl.isKeyDown(.key_left_shift) or rl.isKeyDown(.key_right_shift);
}
