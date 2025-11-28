const engine = @import("../engine.zig");
const game_net = @import("../game_net.zig");

const movement = @import("movement.zig");

pub fn simulateServer(world: *engine.World) !void {
    movement.serverMovePlayers(world);
    movement.moveEnemies(world);
}

fn applySnapshots(world: *engine.World, snapshots: []engine.EntityDiff) !void {
    for (snapshots) |entity_diff| {
        try world.entities.get_mut(entity_diff.id).apply_diff(entity_diff);
    }
}

pub fn simulateClient(
    world: *engine.World,
    input: engine.Input,
    client_id: game_net.ClientId,
    snapshots: []engine.EntityDiff,
) !void {
    try applySnapshots(world, snapshots);
    movement.movePlayer(world, input, client_id);
    movement.moveEnemies(world);
}

// const ClientTimelineNode = struct {
//     world: engine.World,
//     snapshots: []engine.EntityDiff,
//     input: engine.Input,
// };

// const ServerTimelineNode = struct {
//     world: engine.World,
//     inputs: [3]engine.Input, // This is currently in the world - I should probably change that
// }

// fn main() !void {
//     const timeline: []ClientTimelineNode = undefined;
//     const input: engine.Input = undefined;
//     _ = input; // autofix

//     for (timeline) |item| {
//         const world = item.world.clone();
//         for (item.snapshots) |snapshot| {
//             apply(snapshot);
//         }
//         simulate(world, input);
//     }
// }
