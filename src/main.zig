const std = @import("std");
const rl = @import("raylib");
const entity = @import("entity.zig");
const systems = @import("systems.zig");

pub fn main() anyerror!void {
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 800;
    const screenHeight = 450;

    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    var entities = entity.EntityList{
        .entities = undefined,
        .is_alive = [_]bool{false} ** 100,
        .next_id = 0x00,
    };
    const player = entities.spawn(.{
        .position = .{ .x = screenHeight / 2, .y = screenHeight / 2 },
        .render = .{
            .circle = .{
                .color = .red,
                .radius = 50,
            },
        },
        .networked = true,
    });
    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
        //----------------------------------------------------------------------------------
        try systems.movePlayer(&entities, player);

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.light_gray);
        var iter = entities.iter();
        while (iter.next()) |ent| {
            switch (ent.render) {
                .circle => |circle| {
                    rl.drawCircle(@intFromFloat(ent.position.x), @intFromFloat(ent.position.y), circle.radius, circle.color);
                },
                .texture => {},
            }
        }
        rl.drawText("Congrats! You created your first window!", 190, 200, 20, .black);
        //----------------------------------------------------------------------------------
    }
}
