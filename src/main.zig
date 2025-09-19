const std = @import("std");
const rl = @import("raylib");
const engine = @import("engine.zig");
const game_systems = @import("game_systems.zig");
const game_net = @import("game_net.zig");

pub fn main() anyerror!void {
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 800;
    const screenHeight = 450;
    const fps = 60;

    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(50); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    var world = engine.World{
        .entities = engine.EntityList{
            .entities = undefined,
            .is_alive = [_]bool{false} ** 100,
            .next_id = 0x00,
        },
        .time = engine.Time.init(1000 / fps),
        .screen_size = rl.Vector2.init(screenHeight, screenHeight),
        .state = .menu,
    };
    _ = world.entities.spawn(.{
        .position = .{ .x = screenWidth / 2, .y = screenHeight / 4 },
        .render = .{
            .button = .{ .color = .red, .text = "Client [C]", .width = 300, .height = 100 },
        },
        .tag = .ui,
        .networked = false,
    });
    _ = world.entities.spawn(.{
        .position = .{ .x = screenWidth / 2, .y = screenHeight / 4 * 3 },
        .render = .{
            .button = .{ .color = .red, .text = "Server [S]", .width = 300, .height = 100 },
        },
        .tag = .ui,
        .networked = false,
    });

    var network: ?game_net.NetworkState = null;

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
        //----------------------------------------------------------------------------------

        switch (world.state) {
            .menu => {
                if (rl.isKeyPressed(.c)) {
                    std.debug.print("Client\n", .{});
                    network = try game_net.connectToServer();
                } else if (rl.isKeyPressed(.s)) {
                    std.debug.print("Server\n", .{});
                    network = try game_net.waitForConnection();
                }
                if (network) |_| {
                    world.state = .game;
                    hideMenu(&world);
                    spawnGame(&world);
                }
            },
            .game => {
                world.time.update();
                game_systems.movePlayer(&world);
                game_systems.moveEnemies(&world);
            },
        }

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.light_gray);
        var iter = world.entities.iter();
        while (iter.next()) |ent| {
            if (!ent.visible) continue;
            switch (ent.render) {
                .circle => |circle| {
                    rl.drawCircle(
                        @intFromFloat(ent.position.x),
                        @intFromFloat(ent.position.y),
                        circle.radius,
                        circle.color,
                    );
                },
                .button => |button| {
                    rl.drawRectangleLines(
                        @intFromFloat(ent.position.x - button.width / 2),
                        @intFromFloat(ent.position.y - button.height / 2),
                        @intFromFloat(button.width),
                        @intFromFloat(button.height),
                        button.color,
                    );
                    rl.drawText(
                        button.text,
                        @intFromFloat(ent.position.x - 40),
                        @intFromFloat(ent.position.y - 10),
                        20,
                        button.color,
                    );
                },
                .texture => {},
            }
        }

        if (world.state == .game) {
            rl.drawFPS(0, 0);
            var b = [_]u8{0} ** 20;
            const slice = try std.fmt.bufPrintZ(&b, "-{d}", .{world.time.getDrift()});
            rl.drawText(slice, 0, 32, 32, .black);
        }
        // rl.drawText("Congrats! You created your first window!", 190, 200, 20, .black);
        //----------------------------------------------------------------------------------
    }
    if (network) |*net| {
        try net.cleanup();
    }
}

pub fn hideMenu(world: *engine.World) void {
    var iter = world.entities.iter();
    while (iter.next()) |ent| {
        if (ent.tag == .ui) {
            ent.visible = false;
        }
    }
}
pub fn spawnGame(world: *engine.World) void {
    world.time.reset();
    const screen_size = world.screen_size;
    _ = world.entities.spawn(.{
        .position = .{ .x = screen_size.x / 2, .y = screen_size.y / 2 },
        .speed = 200,
        .render = .{
            .circle = .{
                .color = .red,
                .radius = 50,
            },
        },
        .tag = .player,
        .networked = true,
    });
    _ = world.entities.spawn(.{
        .position = .{
            .x = screen_size.x / 8,
            .y = screen_size.y / 2,
        },
        .speed = 100,
        .render = .{
            .circle = .{
                .color = .green,
                .radius = 25,
            },
        },
        .tag = .enemy,
        .networked = false,
        .timer = engine.Timer{
            .max = 1500,
            .remaining = 750,
            .just_finished = false,
        },
    });
    _ = world.entities.spawn(.{
        .position = .{ .x = screen_size.x * 7 / 8, .y = screen_size.y / 2 },
        .speed = 100,
        .render = .{
            .circle = .{
                .color = .green,
                .radius = 25,
            },
        },
        .tag = .enemy,
        .networked = false,
        .timer = engine.Timer{
            .max = 1500,
            .remaining = 750,
            .just_finished = false,
        },
    });
}
