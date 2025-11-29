const argsParser = @import("args");
// const config = @import("config");
const std = @import("std");
const rl = @import("raylib");

const consts = @import("consts.zig");
const debug = @import("debug.zig");
const engine = @import("engine.zig");
const simulation = @import("simulation/root.zig");
const game_net = @import("game_net.zig");
const server = @import("server.zig");
const client = @import("client.zig");
const utils = @import("utils.zig");

pub fn main() anyerror!void {
    // Initialization
    const argsAllocator = std.heap.page_allocator;
    //--------------------------------------------------------------------------------------
    const options = argsParser.parseForCurrentProcess(struct {
        // This declares long options for double hyphen
        @"client-id": u4 = 0,
        server: bool = false,
    }, argsAllocator, .print) catch return;
    defer options.deinit();

    const client_id = game_net.ClientId{ .value = options.options.@"client-id" };
    const is_server = options.options.server;

    std.debug.print("is server!: {}\n", .{is_server});
    if (!is_server) {
        std.debug.print("client id: {}\n", .{client_id});
    }

    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_alloc.deinit();
    const alloc = debug_alloc.allocator();

    const screenWidth = 800;
    const screenHeight = 450;
    const fps = 60;

    rl.setTraceLogLevel(.none);
    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
    if (!is_server) {
        switch (client_id.value) {
            1 => rl.setWindowPosition(0, 0),
            2 => rl.setWindowPosition(screenWidth, 0),
            else => {},
        }
    } else {
        rl.setWindowPosition(screenWidth / 2, @intFromFloat(screenHeight * 1.25));
    }
    defer rl.closeWindow(); // Close window and OpenGL context

    //--------------------------------------------------------------------------------------

    var world = engine.World{
        .entities = engine.EntityList{
            .entities = undefined,
            .is_alive = [_]bool{false} ** 100,
            .modified_this_frame = [_]bool{false} ** 100,
            .next_id = 0x00,
        },
        .time = engine.Time.init(1000 / fps),
        .screen_size = rl.Vector2.init(screenWidth, screenHeight),
        .state = .menu,
    };

    rl.setTargetFPS(120);

    // TODO: add a menu back to the game, maybe allow via build/commandline options to skip it
    world.state = .game;
    hideMenu(&world);
    spawnGame(&world);
    var debug_flags = debug.DebugFlags{ .outgoing_pl_percent = 0 };
    var network: game_net.NetworkState =
        (if (is_server)
            try game_net.setupServer(alloc)
        else
            try game_net.connectToServer(client_id, alloc, &debug_flags));
    defer network.cleanup();

    if (!is_server) {
        std.Thread.sleep(3_000_000);
    }

    // Main game loop
    main_loop: while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
        //----------------------------------------------------------------------------------
        switch (network) {
            .server => if (world.time.getDrift() < 0) {
                // TODO: This probably conflicts with the "waiting for server" logic
                const to_sleep: u64 = utils.millisToNanos(@intFromFloat(
                    world.time.getDrift() * -1 * @as(f32, @floatFromInt(world.time.time_per_frame)),
                ));
                std.Thread.sleep(to_sleep);
            },
            else => {},
        }

        // switch (world.state) {
        //     .menu => {
        //         unreachable;
        //     },
        //     .game => {
        world.time.update();
        switch (network) {
            .server => |*s| {
                while (try s.hasMessageWaiting()) {
                    const client_address, const message = game_net.serverReceiveMessage(s.socket) catch |err| {
                        if (err == error.ConnectionResetByPeer) {
                            std.debug.print("Disconnected by peer!\n", .{});
                            break :main_loop;
                        } else {
                            return err;
                        }
                    };
                    try s.handleMessage(world.time.frame_number, client_address, message);
                }
                const inputs = try s.input.consumeFrame(world.time.frame_number);

                try simulation.simulateServer(&world, inputs);
                try game_net.sendSnapshots(s, &world);
                try debugServerState(s);
            },

            .client => |*c| {
                const input = engine.Input.fromRaylib();

                const status = try client.handleIncomingMessages(c, world.time.frame_number, world.time.time_per_frame);
                if (status == .quit) {
                    break :main_loop;
                }

                try game_net.sendInput(c, input, world.time.frame_number);

                if (world.time.frame_number > consts.frame_buffer_size) {
                    // We look 2 frames ago, see timeline.md.
                    const snapshot_frame = world.time.frame_number - consts.frame_buffer_size;
                    var snapshots = try c.server_snapshots.consumeFrame(snapshot_frame);
                    defer snapshots.deinit(c.server_snapshots.gpa);

                    if (!snapshots.is_done) {
                        std.debug.print("W: F{d} snapshots aren't done\n", .{snapshot_frame});
                    }
                    const snapshotList = snapshots.snapshots.items;
                    // == Update rest of the world to frame 101, rebase myself (102-110) on top of 101

                    // For current frame - apply the rest of the worlds' frame 101 to our 111
                    // try simulation.applyRemoteEntitiesSnapshots(&world, client_id, snapshotList);
                    try simulation.applySnapshots(&c.timeline, snapshot_frame, snapshotList);

                    // For myself - go back 10 frames to my 101, update myself, rebase from there
                    const time_before = world.time.frame_number;
                    world = try simulation.resimulateFrom(&c.timeline, client_id, snapshot_frame);
                    if (time_before != world.time.frame_number) {
                        std.debug.print("Mismatch! {d}!={d}\n", .{ time_before, world.time.frame_number });
                        unreachable;
                    }
                    c.timeline.freeBlock(c.timeline.dropFrame(snapshot_frame));
                    // now my 111 is updated with knowledge of my authoritative position of 101

                    // Now we have authoritative state of 101, slightly better state for 102 onwards
                    // Simulates myself for frame 111
                }
                try simulation.simulateClient(&world, input, client_id);

                // TODO: Make sure this needs to sit here, after everything. If this is saved to frame number 111,
                // I think the important question is: what will be in the packet the server sends as 111?
                // Will it be this state, after simulating the input, or pre?
                try c.timeline.append(
                    simulation.ClientTimelineNode{
                        .world = world,
                        .input = input,
                    },
                    world.time.frame_number,
                );
            },
        }
        std.debug.print("Finished simulating frame {}\n", .{world.time.frame_number});
        // },
        // }

        // Draw
        try drawGame(&world, &network);

        // Cleanup
        //----------------------------------------------------------------------------------
        world.entities.modified_this_frame = .{false} ** world.entities.modified_this_frame.len;
        //----------------------------------------------------------------------------------
    }
}

fn debugClientState(c: *game_net.Client) void {
    std.debug.print("START !!!!!!!!!!\n", .{});
    {
        var frame_number = c.timeline.first_frame;
        while (frame_number < c.timeline.first_frame + c.timeline.len) : (frame_number += 1) {
            const my_world = (try c.timeline.at(frame_number)).world;
            std.debug.print("POS: {}\n", .{my_world.time.frame_number});
        }
    }
    std.debug.print("MID !!!!!!!!!!\n", .{});
    {
        var frame_number = c.server_snapshots.list.first_frame;
        while (frame_number < c.server_snapshots.list.first_frame + c.server_snapshots.list.len) : (frame_number += 1) {
            const snapshot = try c.server_snapshots.list.at(frame_number);
            std.debug.print("snapshots: {any}\n", .{snapshot.snapshots.items});
        }
    }
    std.debug.print("END !!!!!!!!!!\n", .{});
}

fn debugServerState(s: *game_net.Server) !void {
    std.debug.print("START !!!!!!!!!!\n", .{});
    {
        var frame_number = s.input.list.first_frame;
        while (frame_number < s.input.list.first_frame + s.input.list.len) : (frame_number += 1) {
            const inputs = try s.input.list.at(frame_number);
            std.debug.print("inputs: {}\n", .{inputs});
        }
    }
    std.debug.print("MID !!!!!!!!!!\n", .{});
    // {
    //     var frame_number = s.server_snapshots.list.first_frame;
    //     while (frame_number < s.server_snapshots.list.first_frame + s.server_snapshots.list.len) : (frame_number += 1) {
    //         const snapshot = try s.server_snapshots.list.at(frame_number);
    //         std.debug.print("snapshots: {any}\n", .{snapshot.snapshots.items});
    //     }
    // }
    // std.debug.print("END !!!!!!!!!!\n", .{});
}

fn drawGame(world: *engine.World, network: *game_net.NetworkState) !void {
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
        {
            var buff = [_]u8{0} ** 20;
            const drift_text = try std.fmt.bufPrintZ(&buff, "{d}", .{world.time.getDrift()});
            rl.drawText(drift_text, 0, 32, 32, .black);
        }
        {
            var buff = [_]u8{0} ** 20;
            const frame_number_text = try std.fmt.bufPrintZ(&buff, "{d}", .{world.time.frame_number});
            rl.drawText(frame_number_text, 0, 32 * 2, 32, .black);
        }
        switch (network.*) {
            .server => |*s| {
                var buff = [_]u8{0} ** 20;
                const frame_number_text = try std.fmt.bufPrintZ(&buff, "{d}", .{try s.input.numReadyFrames()});
                rl.drawText(frame_number_text, 0, 32 * 3, 32, .green);
            },
            .client => |*c| {
                {
                    var buff = [_]u8{0} ** 20;
                    const frame_number_text = try std.fmt.bufPrintZ(&buff, "{d}", .{c.snapshot_done_server_frame});
                    rl.drawText(frame_number_text, 0, 32 * 3, 32, .blue);
                }
                {
                    var buff = [_]u8{0} ** 20;
                    const frame_number_text = try std.fmt.bufPrintZ(&buff, "{d}", .{c.ack_server_frame});
                    rl.drawText(frame_number_text, 0, 32 * 4, 32, .blue);
                }
            },
        }
    }
}
// Currently unused, as the server/client is passed in the build options.
fn spawnMenu(world: *engine.World) void {
    _ = world.entities.spawn(.{
        .position = .{ .x = world.screen_size.x / 2, .y = world.screen_size.y / 4 },
        .render = .{
            .button = .{ .color = .red, .text = "Client [C]", .width = 300, .height = 100 },
        },
        .tag = .ui,
    });
    _ = world.entities.spawn(.{
        .position = .{ .x = world.screen_size.x / 2, .y = world.screen_size.y / 4 * 3 },
        .render = .{
            .button = .{ .color = .red, .text = "Server [S]", .width = 300, .height = 100 },
        },
        .tag = .ui,
    });
}

fn hideMenu(world: *engine.World) void {
    var iter = world.entities.iter();
    while (iter.next()) |ent| {
        if (ent.tag == .ui) {
            const ui_node = world.entities.get_mut(ent.id);
            ui_node.visible = false;
        }
    }
}

fn spawnGame(world: *engine.World) void {
    world.time.reset();
    const screen_size = world.screen_size;
    _ = world.entities.spawn(.{
        .position = .{ .x = screen_size.x / 3, .y = screen_size.y / 2 },
        .speed = 500,
        .render = .{
            .circle = .{
                .color = .red,
                .radius = 40,
            },
        },
        .tag = .player,
        .network = .{ .owner_id = .client_id(1) },
        .name = "Player 1",
    });
    _ = world.entities.spawn(.{
        .position = .{ .x = screen_size.x / 3 * 2, .y = screen_size.y / 2 },
        .speed = 500,
        .render = .{
            .circle = .{
                .color = .red,
                .radius = 40,
            },
        },
        .tag = .player,
        .network = .{ .owner_id = .client_id(2) },
        .name = "Player 2",
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
        .timer = engine.Timer{
            .max = 1500,
            .remaining = 750,
            .just_finished = false,
        },
        .name = "Green Ball",
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
        .timer = engine.Timer{
            .max = 1500,
            .remaining = 750,
            .just_finished = false,
        },
        .name = "Green Ball",
    });
}
