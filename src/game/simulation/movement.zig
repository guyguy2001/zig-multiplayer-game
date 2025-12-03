const std = @import("std");
const rl = @import("raylib");
const engine = @import("../engine.zig");
const game_net = @import("../game_net.zig");

pub fn movePlayer(world: *engine.World, input: engine.Input, client_id: game_net.ClientId) void {
    const direction = input.getDirection();
    // Do ask the snapshot the server sent for the player position, but:
    // If a snapshot arrived - we should have 3 snapshots, so interpolate.
    // If it didn't - we still have the prev 2, and we live in a delayed world (see the interpolation section in the Source document), so still interpolate.
    // If we're in problem - wait?????

    var iter = world.entities.iter();
    while (iter.next()) |e| {
        if (e.tag == .player and e.isSimulatedLocally(client_id)) {
            const player = world.entities.get_mut(e.id);
            const magnitude = world.time.deltaSecs() * player.speed;
            player.position = player.position.add(direction.normalize().scale(magnitude));
        }
    }
}

pub fn serverMovePlayers(world: *engine.World, input_map: [3]engine.Input) void {
    var iter = world.entities.iter();
    while (iter.next()) |e| {
        if (e.tag == .player) {
            const direction = input_map[e.network.?.owner_id.value].getDirection();
            if (direction.x != 0 or direction.y != 0) {
                const player = world.entities.get_mut(e.id);
                const magnitude = world.time.deltaSecs() * player.speed;
                player.position = player.position.add(
                    direction.normalize().scale(magnitude),
                );
            }
        }
    }
}

pub fn moveEnemies(world: *engine.World) void {
    var iter = world.entities.iter();
    while (iter.next()) |ent| {
        if (ent.tag == .enemy) {
            const enemy = world.entities.get_mut(ent.id);
            const direction = if (enemy.direction) rl.Vector2.init(0, 1) else rl.Vector2.init(0, -1);
            enemy.position = enemy.position.add(direction.scale(world.time.deltaSecs() * enemy.speed));
            enemy.timer.update(&world.time);
            if (enemy.timer.just_finished) {
                enemy.direction = !enemy.direction;
            }
        }
    }
}
