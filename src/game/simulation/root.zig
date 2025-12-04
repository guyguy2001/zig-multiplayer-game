const std = @import("std");

const lib = @import("lib");

const engine = @import("../engine.zig");
const game_net = @import("../game_net.zig");

const movement = @import("movement.zig");

pub fn simulateServer(world: *engine.World, input_map: [3]engine.Input) !void {
    movement.serverMovePlayers(world, input_map);
    movement.moveEnemies(world);
}

pub fn applySnapshots(timeline: *ClientTimeline, target_frame: u64, snapshots: []engine.EntityDiff) !void {
    const world = &(try timeline.at(target_frame)).world;
    for (snapshots) |entity_diff| {
        const entity = world.entities.get_mut(entity_diff.id);
        try entity.apply_diff(entity_diff);
    }
}

pub fn simulateClient(
    world: *engine.World,
    input: engine.Input,
    client_id: game_net.ClientId,
) !void {
    movement.movePlayer(world, input, client_id);
    movement.moveEnemies(world);
}

pub const ClientTimelineNode = struct {
    world: engine.World,
    input: engine.Input,

    // We don't store the snapshots,
    // since we only re-simulate nodes that didn't yet get the server authoritative state,
    // and then drop them from the timeline.
};

pub const ClientTimeline = lib.FrameCyclicBuffer(ClientTimelineNode, undefined, false);

pub fn resimulateFrom(
    timeline: *ClientTimeline,
    client_id: game_net.ClientId,
    starting_frame: u64,
) !engine.World {
    var world = (try timeline.at(starting_frame)).world;

    // Do not apply the input of the first frame, as the snapshot is from after applying the input
    var frame = starting_frame + 1;

    while (frame < timeline.first_frame + timeline.len) : (frame += 1) {
        const node = try timeline.at(frame);

        // Update the starting point to be the simulated previous state, to make the new snapshots we're rebasing onto propagate.

        // TODO: Extract the time outside of world, add an assert at the end of this function to make sure outside-of-world-time is synced with in-world time
        world.time.update();
        try simulateClient(&world, node.input, client_id);

        node.world = world;
    }
    // This function runs after we already updated the time on the real world,
    // and since we undid it, we need to redo it here
    world.time.update();

    return world;
}
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
