const std = @import("std");
const rl = @import("raylib");
const engine = @import("engine.zig");
const game_net = @import("game_net.zig");

pub fn movePlayer(world: *engine.World, input: engine.Input, client_id: game_net.ClientId) void {
    var direction = rl.Vector2.zero();
    if (input.up) {
        direction = direction.add(rl.Vector2.init(0, -1));
    }
    if (input.left) {
        direction = direction.add(rl.Vector2.init(-1, 0));
    }
    if (input.down) {
        direction = direction.add(rl.Vector2.init(0, 1));
    }
    if (input.right) {
        direction = direction.add(rl.Vector2.init(1, 0));
    }

    // Do ask the snapshot the server sent for the player position, but:
    // If a snapshot arrived - we should have 3 snapshots, so interpolate.
    // If it didn't - we still have the prev 2, and we live in a delayed world (see the interpolation section in the Source document), so still interpolate.
    // If we're in problem - wait?????

    var iter = world.entities.iter();
    while (iter.next()) |player| {
        if (player.tag == .player and player.isSimulatedLocally(client_id)) {
            const magnitude = world.time.deltaSecs() * player.speed;
            player.position = player.position.add(direction.normalize().scale(magnitude));
        }
    }
}

pub fn moveEnemies(world: *engine.World) void {
    var iter = world.entities.iter();
    while (iter.next()) |ent| {
        if (ent.tag == .enemy) {
            const direction = if (ent.direction) rl.Vector2.init(0, 1) else rl.Vector2.init(0, -1);
            ent.position = ent.position.add(direction.scale(world.time.deltaSecs() * ent.speed));
            ent.timer.update(&world.time);
            if (ent.timer.just_finished) {
                ent.direction = !ent.direction;
            }
        }
    }
}
